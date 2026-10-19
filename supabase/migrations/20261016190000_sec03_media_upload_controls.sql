-- SEC-03: Bound media uploads with bucket limits, path shape checks, and finalize RPC quotas.

UPDATE storage.buckets
SET file_size_limit = 26214400, -- 25 MiB
    allowed_mime_types = ARRAY[
        'image/jpeg',
        'image/png',
        'image/gif',
        'image/webp',
        'image/heic',
        'image/heif',
        'video/mp4',
        'video/quicktime'
    ]::text[]
WHERE id = 'media';

-- Owner writes require uid / asset-uuid / {original|display|thumb}.
DROP POLICY IF EXISTS media_storage_owner_all ON storage.objects;
CREATE POLICY media_storage_owner_insert ON storage.objects
    AS PERMISSIVE FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'media'
        AND (storage.foldername(name))[1] = (auth.uid())::text
        AND (storage.foldername(name))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        AND name ~ '[[:alnum:]_/-]+/(original|display|thumb)$'
    );
CREATE POLICY media_storage_owner_update ON storage.objects
    AS PERMISSIVE FOR UPDATE TO authenticated
    USING (
        bucket_id = 'media'
        AND (storage.foldername(name))[1] = (auth.uid())::text
        AND (storage.foldername(name))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        AND name ~ '[[:alnum:]_/-]+/(original|display|thumb)$'
    )
    WITH CHECK (
        bucket_id = 'media'
        AND (storage.foldername(name))[1] = (auth.uid())::text
        AND (storage.foldername(name))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        AND name ~ '[[:alnum:]_/-]+/(original|display|thumb)$'
    );
CREATE POLICY media_storage_owner_delete ON storage.objects
    AS PERMISSIVE FOR DELETE TO authenticated
    USING (
        bucket_id = 'media'
        AND (storage.foldername(name))[1] = (auth.uid())::text
    );

CREATE OR REPLACE FUNCTION public.finalize_media_asset(
    p_id uuid,
    p_document_id uuid,
    p_kind text,
    p_original_path text,
    p_display_path text DEFAULT NULL,
    p_thumb_path text DEFAULT NULL,
    p_width integer DEFAULT NULL,
    p_height integer DEFAULT NULL,
    p_duration_ms integer DEFAULT NULL,
    p_byte_size bigint DEFAULT NULL,
    p_content_type text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'storage'
AS $$
DECLARE
    day_count integer;
    day_bytes bigint;
    prefix text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'sign in required' USING ERRCODE = '28000';
    END IF;

    IF p_kind NOT IN ('photo', 'video') THEN
        RAISE EXCEPTION 'invalid media kind' USING ERRCODE = '22023';
    END IF;

    IF p_content_type IS NULL OR p_content_type NOT IN (
        'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/heic', 'image/heif',
        'video/mp4', 'video/quicktime'
    ) THEN
        RAISE EXCEPTION 'invalid content type' USING ERRCODE = '22023';
    END IF;

    IF p_byte_size IS NULL OR p_byte_size <= 0 OR p_byte_size > 26214400 THEN
        RAISE EXCEPTION 'invalid media size' USING ERRCODE = '22023';
    END IF;

    IF p_kind = 'video' AND (p_duration_ms IS NULL OR p_duration_ms <= 0 OR p_duration_ms > 10000) THEN
        RAISE EXCEPTION 'invalid video duration' USING ERRCODE = '22023';
    END IF;

    IF p_document_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.documents
        WHERE id = p_document_id AND owner_id = auth.uid()
    ) THEN
        RAISE EXCEPTION 'document not owned' USING ERRCODE = '42501';
    END IF;

    prefix := lower(auth.uid()::text) || '/' || lower(p_id::text) || '/';
    IF p_original_path IS DISTINCT FROM (prefix || 'original')
       OR (p_display_path IS NOT NULL AND p_display_path IS DISTINCT FROM (prefix || 'display'))
       OR (p_thumb_path IS NOT NULL AND p_thumb_path IS DISTINCT FROM (prefix || 'thumb')) THEN
        RAISE EXCEPTION 'invalid media path' USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM storage.objects
        WHERE bucket_id = 'media' AND name = p_original_path
    ) THEN
        RAISE EXCEPTION 'original object missing' USING ERRCODE = '42501';
    END IF;

    SELECT count(*), coalesce(sum(byte_size), 0)
      INTO day_count, day_bytes
      FROM public.media_assets
     WHERE owner_id = auth.uid()
       AND created_at >= date_trunc('day', now());

    IF day_count >= 200 THEN
        RAISE EXCEPTION 'daily media count quota exceeded' USING ERRCODE = '54000';
    END IF;
    IF day_bytes + p_byte_size > 524288000 THEN -- 500 MiB / day
        RAISE EXCEPTION 'daily media size quota exceeded' USING ERRCODE = '54000';
    END IF;

    INSERT INTO public.media_assets (
        id, owner_id, document_id, kind, status,
        original_path, display_path, thumb_path,
        width, height, duration_ms, byte_size, content_type
    ) VALUES (
        p_id, auth.uid(), p_document_id, p_kind, 'ready',
        p_original_path, p_display_path, p_thumb_path,
        p_width, p_height, p_duration_ms, p_byte_size, p_content_type
    )
    ON CONFLICT (id) DO UPDATE
        SET document_id = EXCLUDED.document_id,
            kind = EXCLUDED.kind,
            status = 'ready',
            original_path = EXCLUDED.original_path,
            display_path = EXCLUDED.display_path,
            thumb_path = EXCLUDED.thumb_path,
            width = EXCLUDED.width,
            height = EXCLUDED.height,
            duration_ms = EXCLUDED.duration_ms,
            byte_size = EXCLUDED.byte_size,
            content_type = EXCLUDED.content_type
        WHERE media_assets.owner_id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_media_asset(
    uuid, uuid, text, text, text, text, integer, integer, integer, bigint, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_media_asset(
    uuid, uuid, text, text, text, text, integer, integer, integer, bigint, text
) TO authenticated, service_role;

DROP POLICY IF EXISTS media_owner_all ON public.media_assets;
CREATE POLICY media_owner_select ON public.media_assets
    AS PERMISSIVE FOR SELECT TO authenticated
    USING (owner_id = (SELECT auth.uid()));
CREATE POLICY media_owner_delete ON public.media_assets
    AS PERMISSIVE FOR DELETE TO authenticated
    USING (owner_id = (SELECT auth.uid()));

REVOKE INSERT, UPDATE ON TABLE public.media_assets FROM authenticated, anon;
GRANT SELECT, DELETE ON TABLE public.media_assets TO authenticated;
GRANT ALL ON TABLE public.media_assets TO service_role;
