-- SEC-02: Document graph writes go through RPCs; table invariants enforce ownership/cycles/roles/size.

CREATE OR REPLACE FUNCTION public.validate_document_row()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    parent_owner uuid;
    walk uuid;
    depth integer := 0;
BEGIN
    IF NEW.role NOT IN ('mosaic', 'pursuit', 'node', 'page') THEN
        RAISE EXCEPTION 'invalid role' USING ERRCODE = '22023';
    END IF;

    IF NEW.visibility NOT IN ('public', 'private', 'hidden') THEN
        RAISE EXCEPTION 'invalid visibility' USING ERRCODE = '22023';
    END IF;

    IF NEW.role = 'mosaic' AND NEW.visibility NOT IN ('public', 'private') THEN
        RAISE EXCEPTION 'invalid mosaic visibility' USING ERRCODE = '22023';
    END IF;

    IF NEW.revision IS NULL OR NEW.revision <= 0 THEN
        RAISE EXCEPTION 'invalid revision' USING ERRCODE = '22023';
    END IF;

    IF octet_length(COALESCE(NEW.body, '{}'::jsonb)::text) > 2000000 THEN
        RAISE EXCEPTION 'document body too large' USING ERRCODE = '22023';
    END IF;

    IF TG_OP = 'UPDATE' AND NEW.owner_id IS DISTINCT FROM OLD.owner_id THEN
        RAISE EXCEPTION 'document owner is immutable' USING ERRCODE = '22023';
    END IF;

    IF TG_OP = 'UPDATE'
       AND OLD.role IS DISTINCT FROM NEW.role
       AND NOT (
           (OLD.role = 'pursuit' AND NEW.role = 'node')
           OR (OLD.role = 'node' AND NEW.role = 'pursuit')
       ) THEN
        RAISE EXCEPTION 'invalid role change' USING ERRCODE = '22023';
    END IF;

    IF NEW.parent_id IS NOT NULL THEN
        IF NEW.parent_id = NEW.id THEN
            RAISE EXCEPTION 'document cannot parent itself' USING ERRCODE = '22023';
        END IF;

        SELECT documents.owner_id
          INTO parent_owner
          FROM public.documents
         WHERE documents.id = NEW.parent_id;

        IF parent_owner IS NULL THEN
            RAISE EXCEPTION 'parent not found' USING ERRCODE = '23503';
        END IF;

        IF parent_owner IS DISTINCT FROM NEW.owner_id THEN
            RAISE EXCEPTION 'parent not owned' USING ERRCODE = '42501';
        END IF;

        walk := NEW.parent_id;
        WHILE walk IS NOT NULL LOOP
            depth := depth + 1;
            IF depth > 32 THEN
                RAISE EXCEPTION 'document parent chain too deep' USING ERRCODE = '22023';
            END IF;
            IF walk = NEW.id THEN
                RAISE EXCEPTION 'document parent cycle' USING ERRCODE = '22023';
            END IF;
            SELECT documents.parent_id INTO walk FROM public.documents WHERE documents.id = walk;
        END LOOP;
    ELSIF NEW.role IN ('node', 'page') THEN
        RAISE EXCEPTION 'node and page require a parent' USING ERRCODE = '22023';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS documents_validate_row ON public.documents;
CREATE TRIGGER documents_validate_row
    BEFORE INSERT OR UPDATE ON public.documents
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_document_row();

-- Guard recursive helpers against runaway cycles (defense in depth).
CREATE OR REPLACE FUNCTION public.ancestor_pursuit_id(p_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
    WITH RECURSIVE chain AS (
        SELECT id, parent_id, role, 0 AS depth
        FROM public.documents
        WHERE id = p_id
        UNION ALL
        SELECT parent.id, parent.parent_id, parent.role, chain.depth + 1
        FROM public.documents parent
        JOIN chain ON parent.id = chain.parent_id
        WHERE chain.depth < 32
    )
    SELECT id
    FROM chain
    WHERE role = 'pursuit'
    ORDER BY depth
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.ancestor_pursuit_is_public(p_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
    WITH RECURSIVE chain AS (
        SELECT id, parent_id, role, visibility, 0 AS depth
        FROM public.documents
        WHERE id = p_id
        UNION ALL
        SELECT parent.id, parent.parent_id, parent.role, parent.visibility, chain.depth + 1
        FROM public.documents parent
        JOIN chain ON parent.id = chain.parent_id
        WHERE chain.depth < 32
    )
    SELECT coalesce(bool_or(role = 'pursuit' AND visibility = 'public'), false)
    FROM chain;
$$;

-- Explicit owned deletions. Cascades remove child documents via FK.
CREATE OR REPLACE FUNCTION public.delete_documents(p_ids uuid[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    removed integer := 0;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'sign in required' USING ERRCODE = '28000';
    END IF;

    IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN
        RETURN 0;
    END IF;

    DELETE FROM public.documents
    WHERE owner_id = auth.uid()
      AND id = ANY (p_ids)
      AND role <> 'mosaic';

    GET DIAGNOSTICS removed = ROW_COUNT;
    RETURN removed;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_documents(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_documents(uuid[]) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.validate_document_row() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_document_row() TO service_role;

-- Write RPCs must be SECURITY DEFINER once table INSERT/UPDATE/DELETE are revoked.
CREATE OR REPLACE FUNCTION public.save_document(
    p_id uuid,
    p_parent_id uuid,
    p_role text,
    p_title text,
    p_body jsonb,
    p_expected_revision bigint
)
RETURNS TABLE(revision bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    next_revision bigint;
    previous_role text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'sign in required' USING ERRCODE = '28000';
    END IF;

    IF p_role NOT IN ('mosaic', 'pursuit', 'node', 'page') THEN
        RAISE EXCEPTION 'invalid role' USING ERRCODE = '22023';
    END IF;

    IF p_parent_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM public.documents parent
        WHERE parent.id = p_parent_id
          AND parent.owner_id = auth.uid()
    ) THEN
        RAISE EXCEPTION 'parent not owned' USING ERRCODE = '42501';
    END IF;

    SELECT documents.role
      INTO previous_role
      FROM public.documents
     WHERE documents.id = p_id
       AND documents.owner_id = auth.uid();

    IF previous_role IS NOT NULL
       AND previous_role IS DISTINCT FROM p_role
       AND NOT (
           (previous_role = 'pursuit' AND p_role = 'node')
           OR (previous_role = 'node' AND p_role = 'pursuit')
       ) THEN
        RAISE EXCEPTION 'invalid role change' USING ERRCODE = '22023';
    END IF;

    UPDATE public.documents
    SET parent_id = p_parent_id,
        role = p_role,
        title = p_title,
        body = p_body,
        visibility = CASE
            WHEN previous_role IS DISTINCT FROM p_role
                 AND p_role IN ('pursuit', 'node')
            THEN 'hidden'
            ELSE documents.visibility
        END,
        revision = documents.revision + 1,
        updated_at = now()
    WHERE documents.id = p_id
      AND documents.owner_id = auth.uid()
      AND documents.revision = p_expected_revision
    RETURNING documents.revision INTO next_revision;

    IF next_revision IS NOT NULL THEN
        revision := next_revision;
        RETURN NEXT;
        RETURN;
    END IF;

    IF EXISTS (SELECT 1 FROM public.documents existing WHERE existing.id = p_id) THEN
        RAISE EXCEPTION 'revision conflict' USING ERRCODE = 'P0001';
    END IF;

    IF p_role = 'mosaic' AND EXISTS (
        SELECT 1
        FROM public.documents existing
        WHERE existing.owner_id = auth.uid()
          AND existing.role = 'mosaic'
    ) THEN
        RAISE EXCEPTION 'mosaic exists' USING ERRCODE = '23505';
    END IF;

    INSERT INTO public.documents (id, owner_id, parent_id, role, title, visibility, body, revision)
    VALUES (
        p_id,
        auth.uid(),
        p_parent_id,
        p_role,
        coalesce(p_title, ''),
        CASE WHEN p_role = 'mosaic' THEN 'private' ELSE 'hidden' END,
        p_body,
        1
    );

    revision := 1;
    RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_document_visibility(p_id uuid, p_visibility text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'sign in required' USING ERRCODE = '28000';
    END IF;

    IF p_visibility NOT IN ('public', 'private', 'hidden') THEN
        RAISE EXCEPTION 'invalid visibility' USING ERRCODE = '22023';
    END IF;

    UPDATE public.documents
    SET visibility = p_visibility,
        updated_at = now()
    WHERE id = p_id
      AND owner_id = auth.uid()
      AND (
          (role = 'pursuit')
          OR (role = 'mosaic' AND p_visibility IN ('public', 'private'))
      );

    IF NOT FOUND THEN
        RAISE EXCEPTION 'visibility not updated' USING ERRCODE = '42501';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.save_document(uuid, uuid, text, text, jsonb, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_document(uuid, uuid, text, text, jsonb, bigint) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.set_document_visibility(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_document_visibility(uuid, text) TO authenticated, service_role;

-- Direct table mutations are closed; save_document / delete_documents remain the write path.
DROP POLICY IF EXISTS documents_owner_all ON public.documents;
CREATE POLICY documents_owner_select ON public.documents
    AS PERMISSIVE FOR SELECT TO authenticated
    USING (owner_id = (SELECT auth.uid()));

REVOKE INSERT, UPDATE, DELETE ON TABLE public.documents FROM authenticated, anon;
GRANT SELECT ON TABLE public.documents TO authenticated;
GRANT ALL ON TABLE public.documents TO service_role;
