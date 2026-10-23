-- The walk ran over every piece on both versions of a board at each save: about 90 ms for the
-- largest board, and seconds near the 2 MB cap. A piece saved exactly as it was can't hold a
-- change, so only pieces that differ are walked; a typical save touches one or two. The walk also
-- skips plain values and empty lists, and checks ignored keys with one pattern.

create or replace function public.board_key_ignored(p_key text)
 returns boolean
 language sql
 immutable
 set search_path to 'public'
as $function$
    select p_key ~ ('^(id|kind|rawValue|year|month|day|stampedAt|style|position|rotation|scale|opacity|shadow'
                    '|background|isLocked|drawingData|preserved|listMarker|platform|socialPlatform|graphKind'
                    '|graphXAxis|graphYAxis|mediaAssets)$'
                    '|(ID|IDs|Id|Ids|Index|Zoom|Width|Height|Aspect|Shape|Layout|Fill|Warp|Scale|Style|Color|Sticky|Border)$'
                    '|^(pan|selected|tab[A-Z]|shadow|frame(?!Caption))'
                    '|[a-z][XY]$');
$function$;

create or replace function public.board_addressed(p_body jsonb)
 returns table(address text, piece_id text, unit_kind text, is_piece boolean, texts jsonb, files jsonb,
               checks jsonb, has_content boolean)
 language sql
 immutable
 set search_path to 'public'
as $function$
    with recursive walk(address, piece_id, unit_kind, is_piece, path, key, value, depth) as (
        select lower(b #>> '{id,rawValue}'), lower(b #>> '{id,rawValue}'), b->>'kind', true, '', '', b, 0
        from jsonb_array_elements(case when jsonb_typeof(p_body->'blocks') = 'array' then p_body->'blocks' else '[]'::jsonb end) b
        where b #>> '{id,rawValue}' is not null
        union all
        select step.*
        from walk w
        cross join lateral (
            -- An object's fields belong to the thing it's part of.
            select w.address, w.piece_id, w.unit_kind, w.is_piece,
                   case when w.path = '' then field.key else w.path || '.' || field.key end,
                   field.key, field.value, w.depth + 1
            from jsonb_each(case when jsonb_typeof(w.value) = 'object' then w.value else '{}'::jsonb end) field
            where field.value not in ('[]'::jsonb, '{}'::jsonb)
              and not public.board_key_ignored(field.key)
            union all
            -- A list's members are pieces, things of their own, or plain parts of what holds them.
            select case when member.piece is not null then member.piece
                        when member.item is not null then w.address || '/' || lower(w.key) || '/' || member.item
                        else w.address end,
                   coalesce(member.piece, w.piece_id),
                   case when member.piece is not null then element->>'kind'
                        when member.item is not null then coalesce(element->>'kind', lower(w.key))
                        else w.unit_kind end,
                   member.piece is not null or (w.is_piece and member.item is null),
                   case when member.piece is not null or member.item is not null then '' else w.path || '.' || ord end,
                   w.key, element, w.depth + 1
            from jsonb_array_elements(case when jsonb_typeof(w.value) = 'array' then w.value else '[]'::jsonb end)
                with ordinality as members(element, ord)
            cross join lateral (
                select case when jsonb_typeof(element) = 'object' and element ? 'kind' then lower(element #>> '{id,rawValue}') end as piece,
                       case when jsonb_typeof(element) <> 'object' or element #>> '{id,rawValue}' is not null then null
                            when jsonb_typeof(element->'id') = 'string' and element->>'id' <> '' then lower(element->>'id')
                            when element ? 'year' and element ? 'month' and element ? 'day' then
                                lpad(element->>'year', 4, '0') || '-' || lpad(element->>'month', 2, '0') || '-' || lpad(element->>'day', 2, '0')
                            when coalesce(element->>'fileName', '') <> '' then lower(element->>'fileName')
                       end as item
            ) member
        ) step
        where w.depth < 40 and jsonb_typeof(w.value) in ('object', 'array')
    ),
    thing as (
        select distinct on (walk.address) walk.address, walk.piece_id, walk.unit_kind, walk.is_piece
        from walk
        where walk.path = ''
        order by walk.address, walk.depth
    ),
    leaf as (
        select walk.address, walk.path, walk.key, walk.value
        from walk
        where walk.path <> '' and jsonb_typeof(walk.value) in ('string', 'number', 'boolean')
    ),
    fields as (
        select thing.address,
               coalesce(jsonb_object_agg(leaf.path, leaf.value) filter (
                   where jsonb_typeof(leaf.value) = 'string' and leaf.key !~* 'filename$'), '{}'::jsonb) as texts,
               coalesce(jsonb_object_agg(leaf.path, leaf.value) filter (
                   where jsonb_typeof(leaf.value) = 'string' and leaf.key ~* 'filename$'), '{}'::jsonb) as files,
               coalesce(jsonb_object_agg(leaf.path, leaf.value) filter (
                   where jsonb_typeof(leaf.value) = 'boolean' and leaf.key = 'isChecked'), '{}'::jsonb) as checks,
               coalesce(bool_or(
                   (jsonb_typeof(leaf.value) = 'string' and btrim(leaf.value #>> '{}') <> '')
                   or (jsonb_typeof(leaf.value) = 'boolean' and leaf.key = 'isChecked' and leaf.value = 'true'::jsonb)
                   or jsonb_typeof(leaf.value) = 'number'
               ), false) as filled,
               coalesce(bool_or(leaf.key = 'text' and btrim(leaf.value #>> '{}') <> ''), false) as has_words
        from thing
        left join leaf on leaf.address = thing.address
        group by thing.address
    )
    select thing.address, thing.piece_id, thing.unit_kind, thing.is_piece, fields.texts, fields.files, fields.checks,
           -- A piece counts once placed, except containers and text waiting for words; anything
           -- inside one counts once something is in it.
           case when thing.is_piece then thing.unit_kind not in ('group', 'tabs', 'unsupported')
                                         and (thing.unit_kind not in ('text', 'heading') or fields.has_words)
                else fields.filled end
    from thing
    join fields on fields.address = thing.address;
$function$;

-- The changes between two versions of a board that count, each with the piece to mark. Only the
-- pieces that differ between the two are walked: whatever is in a piece saved exactly as it was is
-- the same on both sides.
create or replace function public.board_changes(p_old jsonb, p_new jsonb)
 returns jsonb
 language sql
 immutable
 set search_path to 'public'
as $function$
    with old_blocks as (
             select b from jsonb_array_elements(case when jsonb_typeof(p_old->'blocks') = 'array' then p_old->'blocks' else '[]'::jsonb end) b
         ),
         new_blocks as (
             select b from jsonb_array_elements(case when jsonb_typeof(p_new->'blocks') = 'array' then p_new->'blocks' else '[]'::jsonb end) b
         ),
         fresh as (
             select * from public.board_addressed(jsonb_build_object('blocks', coalesce(
                 (select jsonb_agg(new_blocks.b) from new_blocks where new_blocks.b not in (select old_blocks.b from old_blocks)),
                 '[]'::jsonb)))
         ),
         before as (
             select * from public.board_addressed(jsonb_build_object('blocks', coalesce(
                 (select jsonb_agg(old_blocks.b) from old_blocks where old_blocks.b not in (select new_blocks.b from new_blocks)),
                 '[]'::jsonb)))
         ),
         change as (
             -- Something new, or something that was there empty and now has content.
             select fresh.address as id, fresh.piece_id as piece, fresh.unit_kind as kind
             from fresh
             left join before on before.address = fresh.address
             where fresh.has_content and (before.address is null or not before.has_content)
             union all
             -- About ten or more characters written into text that was already there.
             select fresh.address || '#text:' || written.key, fresh.piece_id, 'writing'
             from fresh
             join before on before.address = fresh.address and before.has_content
             cross join lateral jsonb_each_text(fresh.texts) written
             where length(written.value) - length(coalesce(before.texts->>written.key, '')) >= 10
             union all
             -- A checkbox turned on.
             select fresh.address || '#on:' || ticked.key, fresh.piece_id, 'checked'
             from fresh
             join before on before.address = fresh.address and before.has_content
             cross join lateral jsonb_each(fresh.checks) ticked
             where ticked.value = 'true'::jsonb and coalesce(before.checks->ticked.key, 'false'::jsonb) <> 'true'::jsonb
             union all
             -- A different photo or video.
             select fresh.address || '#file:' || swapped.key, fresh.piece_id,
                    case when fresh.unit_kind = 'banner' then 'banner' else 'photo' end
             from fresh
             join before on before.address = fresh.address and before.has_content
             cross join lateral jsonb_each_text(fresh.files) swapped
             where swapped.value <> '' and swapped.value is distinct from before.files->>swapped.key
         )
    select coalesce(jsonb_agg(jsonb_build_object('id', change.id, 'piece', change.piece, 'kind', change.kind)), '[]'::jsonb)
    from change;
$function$;

revoke all on function public.board_key_ignored(text) from public, anon, authenticated;
revoke all on function public.board_addressed(jsonb) from public, anon, authenticated;
revoke all on function public.board_changes(jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.board_key_ignored(text) to service_role;
grant execute on function public.board_addressed(jsonb) to service_role;
grant execute on function public.board_changes(jsonb, jsonb) to service_role;
