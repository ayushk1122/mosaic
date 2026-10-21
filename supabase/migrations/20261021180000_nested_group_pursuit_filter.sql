-- Groups can hold groups. The visitor filter and the Pursuit widget list looked only one group
-- level deep, so a hidden Pursuit inside a nested group reached visitors (title, id, and cover
-- image, which then counted as a used file for viewer_can_read_media). Both now walk every level.
CREATE OR REPLACE FUNCTION public.filter_pursuit_blocks(p_blocks jsonb, p_owner uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    result jsonb := '[]'::jsonb;
    block jsonb;
    shown jsonb;
begin
    if p_blocks is null or jsonb_typeof(p_blocks) <> 'array' then
        return '[]'::jsonb;
    end if;

    for block in select value from jsonb_array_elements(p_blocks)
    loop
        if block->>'kind' = 'pursuit' then
            shown := public.viewer_pursuit_block(block, p_owner);
            if shown is not null then
                result := result || jsonb_build_array(shown);
            end if;
        elsif block->>'kind' = 'group' then
            result := result || jsonb_build_array(jsonb_set(
                block,
                '{groupMembers}',
                public.filter_pursuit_blocks(coalesce(block->'groupMembers', '[]'::jsonb), p_owner),
                true
            ));
        else
            result := result || jsonb_build_array(block);
        end if;
    end loop;

    return result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.board_pursuit_widgets(p_body jsonb)
 RETURNS SETOF jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
    with recursive walk(value) as (
        select value
        from jsonb_array_elements(
            case jsonb_typeof(p_body->'blocks') when 'array' then p_body->'blocks' else '[]'::jsonb end
        )
        union all
        select member.value
        from walk
        cross join lateral jsonb_array_elements(
            case jsonb_typeof(walk.value->'groupMembers') when 'array' then walk.value->'groupMembers' else '[]'::jsonb end
        ) member
    )
    select value from walk where value ? 'pursuitID';
$function$;

REVOKE ALL ON FUNCTION public.filter_pursuit_blocks(p_blocks jsonb, p_owner uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.filter_pursuit_blocks(p_blocks jsonb, p_owner uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.filter_pursuit_blocks(p_blocks jsonb, p_owner uuid) TO service_role;
REVOKE ALL ON FUNCTION public.board_pursuit_widgets(p_body jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.board_pursuit_widgets(p_body jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.board_pursuit_widgets(p_body jsonb) TO service_role;
