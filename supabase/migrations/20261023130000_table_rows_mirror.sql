-- A table's visible rows (`tableRows`) are a copy of the entry on screen, which always exists, so
-- an edit counted there too would be one change counted twice. Only the entry's rows count.

create or replace function public.board_key_ignored(p_key text)
 returns boolean
 language sql
 immutable
 set search_path to 'public'
as $function$
    select p_key ~ ('^(id|kind|rawValue|year|month|day|stampedAt|style|position|rotation|scale|opacity|shadow'
                    '|background|isLocked|drawingData|preserved|listMarker|platform|socialPlatform|graphKind'
                    '|graphXAxis|graphYAxis|mediaAssets|tableRows)$'
                    '|(ID|IDs|Id|Ids|Index|Zoom|Width|Height|Aspect|Shape|Layout|Fill|Warp|Scale|Style|Color|Sticky|Border)$'
                    '|^(pan|selected|tab[A-Z]|shadow|frame(?!Caption))'
                    '|[a-z][XY]$');
$function$;

revoke all on function public.board_key_ignored(text) from public, anon, authenticated;
grant execute on function public.board_key_ignored(text) to service_role;
