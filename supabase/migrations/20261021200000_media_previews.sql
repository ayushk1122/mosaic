-- Boards carry `mediaPreviews`: a tiny blurred stand-in per file name, shown to visitors while a
-- photo downloads. Visitors' copy keeps only previews of files their filtered board still uses,
-- and the previews never count as a use: otherwise a preview of a hidden Pursuit's photo, or of
-- a saved sticker, would make that file readable through viewer_can_read_media.
CREATE OR REPLACE FUNCTION public.viewer_board_body(p_body jsonb, p_owner uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    filtered jsonb;
    used_text text;
    assets jsonb := '{}'::jsonb;
    previews jsonb := '{}'::jsonb;
    file_name text;
    value jsonb;
begin
    filtered := jsonb_set(
        coalesce(p_body, '{}'::jsonb) - 'stickerLibrary',
        '{blocks}',
        public.filter_pursuit_blocks(coalesce(p_body->'blocks', '[]'::jsonb), p_owner),
        true
    );
    used_text := (filtered - 'mediaAssets' - 'mediaPreviews')::text;
    for file_name, value in
        select key, item from jsonb_each(coalesce(p_body->'mediaAssets', '{}'::jsonb)) as entries(key, item)
    loop
        if position(to_jsonb(file_name)::text in used_text) > 0 then
            assets := assets || jsonb_build_object(file_name, value);
        end if;
    end loop;
    for file_name, value in
        select key, item from jsonb_each(coalesce(p_body->'mediaPreviews', '{}'::jsonb)) as entries(key, item)
    loop
        if position(to_jsonb(file_name)::text in used_text) > 0 then
            previews := previews || jsonb_build_object(file_name, value);
        end if;
    end loop;
    filtered := filtered - 'mediaAssets' - 'mediaPreviews';
    if assets <> '{}'::jsonb then
        filtered := jsonb_set(filtered, '{mediaAssets}', assets, true);
    end if;
    if previews <> '{}'::jsonb then
        filtered := jsonb_set(filtered, '{mediaPreviews}', previews, true);
    end if;
    return filtered;
end;
$function$;

REVOKE ALL ON FUNCTION public.viewer_board_body(p_body jsonb, p_owner uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.viewer_board_body(p_body jsonb, p_owner uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.viewer_board_body(p_body jsonb, p_owner uuid) TO service_role;
