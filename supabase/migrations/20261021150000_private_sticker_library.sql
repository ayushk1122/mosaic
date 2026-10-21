-- Saved stickers ("Your stickers") ride in the owner's Mosaic board body as `stickerLibrary`, so
-- they sync with the account like everything else. They are the owner's alone: visitors' copy
-- of a board drops the list, and a file that only the list mentions no longer counts as used,
-- so viewer_can_read_media (which checks this function's mediaAssets) refuses it. Stickers
-- placed on a board are blocks and stay visible as before.
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
    file_name text;
    asset jsonb;
begin
    filtered := jsonb_set(
        coalesce(p_body, '{}'::jsonb) - 'stickerLibrary',
        '{blocks}',
        public.filter_pursuit_blocks(coalesce(p_body->'blocks', '[]'::jsonb), p_owner),
        true
    );
    used_text := (filtered - 'mediaAssets')::text;
    for file_name, asset in
        select key, value from jsonb_each(coalesce(p_body->'mediaAssets', '{}'::jsonb))
    loop
        if position(to_jsonb(file_name)::text in used_text) > 0 then
            assets := assets || jsonb_build_object(file_name, asset);
        end if;
    end loop;
    if assets = '{}'::jsonb then
        return filtered - 'mediaAssets';
    end if;
    return jsonb_set(filtered, '{mediaAssets}', assets, true);
end;
$function$;

REVOKE ALL ON FUNCTION public.viewer_board_body(p_body jsonb, p_owner uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.viewer_board_body(p_body jsonb, p_owner uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.viewer_board_body(p_body jsonb, p_owner uuid) TO service_role;
