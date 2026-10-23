-- What counts as an update, beyond whole new pieces: something new inside a piece (a carousel
-- card, a calendar day's photo, a list item, a tab, a graph point, a table entry), a photo swapped
-- into a photo or banner piece, about ten or more characters written into existing text, and a
-- list item checked off. Moving, resizing, restyling, cropping, reordering, deleting, backgrounds,
-- and privacy never count. Each change names the piece to mark, and Today also lists the nodes and
-- pages it sits in, so the pieces that lead there are marked too.

-- Everything on a board that can change in a way that counts, inside groups too.
create or replace function public.board_units(p_body jsonb)
 returns table(unit_id text, piece_id text, unit_kind text, text_value text, checked boolean, file text)
 language sql
 immutable
 set search_path to 'public'
as $function$
    with recursive block as (
        select b
        from jsonb_array_elements(case when jsonb_typeof(p_body->'blocks') = 'array' then p_body->'blocks' else '[]'::jsonb end) b
        union all
        select member
        from block
        cross join lateral jsonb_array_elements(
            case when jsonb_typeof(block.b->'groupMembers') = 'array' then block.b->'groupMembers' else '[]'::jsonb end
        ) member
    ),
    piece as (
        select lower(block.b #>> '{id,rawValue}') as id, block.b->>'kind' as kind, block.b
        from block
        where block.b #>> '{id,rawValue}' is not null
    )
    -- The pieces themselves.
    select piece.id, piece.id, piece.kind, piece.b->>'text', null::boolean, piece.b->>'mediaFileName'
    from piece
    where piece.kind not in ('group', 'tabs', 'unsupported')
    union all
    -- Carousel cards.
    select piece.id || '/card/' || coalesce(lower(card->>'id'), card->>'fileName', cards.ord::text), piece.id,
           case when coalesce(card->>'kind', 'media') = 'media' then 'photo' else 'link' end,
           null, null, card->>'fileName'
    from piece
    cross join lateral jsonb_array_elements(
        case when jsonb_typeof(piece.b->'carouselItems') = 'array' then piece.b->'carouselItems' else '[]'::jsonb end
    ) with ordinality as cards(card, ord)
    union all
    -- A calendar day's photos.
    select piece.id || '/day/' || concat_ws('-', day->>'year', day->>'month', day->>'day') || '/'
               || coalesce(lower(media->>'id'), media->>'fileName', photos.ord::text),
           piece.id, 'photo', null, null, media->>'fileName'
    from piece
    cross join lateral jsonb_array_elements(
        case when jsonb_typeof(piece.b->'calendarEntries') = 'array' then piece.b->'calendarEntries' else '[]'::jsonb end
    ) day
    cross join lateral jsonb_array_elements(
        case when jsonb_typeof(day->'media') = 'array' then day->'media' else '[]'::jsonb end
    ) with ordinality as photos(media, ord)
    union all
    -- A calendar day's note.
    select piece.id || '/day/' || concat_ws('-', day->>'year', day->>'month', day->>'day') || '/note',
           piece.id, 'note', day->>'note', null, null
    from piece
    cross join lateral jsonb_array_elements(
        case when jsonb_typeof(piece.b->'calendarEntries') = 'array' then piece.b->'calendarEntries' else '[]'::jsonb end
    ) day
    union all
    -- List items.
    select piece.id || '/item/' || lower(item->>'id'), piece.id, 'item', item->>'text',
           coalesce((item->>'isChecked')::boolean, false), null
    from piece
    cross join lateral jsonb_array_elements(
        case when jsonb_typeof(piece.b->'listItems') = 'array' then piece.b->'listItems' else '[]'::jsonb end
    ) item
    where item->>'id' is not null
    union all
    -- Graph points.
    select piece.id || '/point/' || lower(point->>'id'), piece.id, 'point', null, null, null
    from piece
    cross join lateral jsonb_array_elements(
        case when jsonb_typeof(piece.b->'graphPoints') = 'array' then piece.b->'graphPoints' else '[]'::jsonb end
    ) point
    where point->>'id' is not null
    union all
    -- Tabs.
    select piece.id || '/tab/' || lower(tab->>'id'), piece.id, 'tab', tab->>'title', null, null
    from piece
    cross join lateral jsonb_array_elements(
        case when jsonb_typeof(piece.b->'tabs') = 'array' then piece.b->'tabs' else '[]'::jsonb end
    ) tab
    where tab->>'id' is not null
    union all
    -- Table entries, by position.
    select piece.id || '/cell/' || cells.ord, piece.id, 'cell', cells.cell #>> '{}', null, null
    from piece
    cross join lateral jsonb_path_query(
        case when jsonb_typeof(piece.b->'tableEntries') in ('array', 'object') then piece.b->'tableEntries' else '[]'::jsonb end,
        'strict $.**'
    ) with ordinality as cells(cell, ord)
    where jsonb_typeof(cells.cell) = 'string';
$function$;

-- The changes between two versions of a board that count, each with the piece to mark.
create or replace function public.board_changes(p_old jsonb, p_new jsonb)
 returns jsonb
 language sql
 immutable
 set search_path to 'public'
as $function$
    with fresh as (select * from public.board_units(p_new)),
         before as (select * from public.board_units(p_old)),
         change as (
             -- Something new; text and table entries only once they have words in them.
             select fresh.unit_id as id, fresh.piece_id as piece, fresh.unit_kind as kind
             from fresh
             where not exists (select 1 from before where before.unit_id = fresh.unit_id)
               and not (fresh.unit_kind in ('text', 'note', 'item', 'cell') and coalesce(btrim(fresh.text_value), '') = '')
             union all
             -- About ten or more characters written into text that was already there.
             select fresh.unit_id || '#writing', fresh.piece_id, 'writing'
             from fresh
             join before on before.unit_id = fresh.unit_id
             where length(coalesce(fresh.text_value, '')) - length(coalesce(before.text_value, '')) >= 10
               and fresh.unit_kind not in ('tab', 'photo', 'link')
             union all
             -- A list item checked off.
             select fresh.unit_id || '#checked', fresh.piece_id, 'checked'
             from fresh
             join before on before.unit_id = fresh.unit_id
             where fresh.checked and not coalesce(before.checked, false)
             union all
             -- A different photo in a photo or banner piece, or a card.
             select fresh.unit_id || '#file:' || fresh.file, fresh.piece_id,
                    case when fresh.unit_kind = 'banner' then 'banner' else 'photo' end
             from fresh
             join before on before.unit_id = fresh.unit_id
             where fresh.file is not null
               and fresh.file is distinct from before.file
               and fresh.unit_kind in ('media', 'banner', 'photo')
         )
    select coalesce(jsonb_agg(jsonb_build_object('id', change.id, 'piece', change.piece, 'kind', change.kind)), '[]'::jsonb)
    from change;
$function$;

create or replace function public.record_board_additions()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
    added jsonb;
    target uuid;
begin
    if tg_op = 'UPDATE' and old.body is not distinct from new.body then
        return null;
    end if;
    added := public.board_changes(case when tg_op = 'UPDATE' then old.body else null end, new.body);
    if tg_op = 'INSERT' and new.role = 'page' then
        added := added || jsonb_build_array(jsonb_build_object('id', new.id::text, 'piece', new.id::text, 'kind', 'page'));
    end if;
    if jsonb_array_length(added) = 0 then
        return null;
    end if;
    target := case when new.role in ('mosaic', 'pursuit') then new.id else public.owning_pursuit(new.id) end;
    if target is null then
        return null;
    end if;
    insert into public.board_additions (board_id, owner_id, source_id, pieces)
    values (target, new.owner_id, new.id, added);
    delete from public.board_additions where added_at < now() - interval '30 days';
    return null;
end;
$function$;

-- The boards between a page or node and the board it counts toward, nearest first.
create or replace function public.board_path(p_source uuid, p_board uuid)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    with recursive chain as (
        select doc.id, doc.parent_id, 0 as depth
        from public.documents doc
        where doc.id = p_source and doc.id <> p_board
        union all
        select parent.id, parent.parent_id, chain.depth + 1
        from public.documents parent
        join chain on parent.id = chain.parent_id
        where parent.id <> p_board and chain.depth < 20
    )
    select coalesce(jsonb_agg(chain.id::text order by chain.depth), '[]'::jsonb) from chain;
$function$;

-- What the caller can see now of the changes to a board in the last month, each once, with when
-- it last happened. A change counts while the piece it marks is still on a board the caller sees.
drop function if exists public.board_visible_additions(uuid);
create or replace function public.board_visible_additions(p_board_id uuid)
 returns table(piece_id text, kind text, added_at timestamptz, block_id text, source_id uuid)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    with added as (
        select addition.source_id,
               piece->>'id' as piece_id,
               coalesce(piece->>'piece', piece->>'id') as block_id,
               piece->>'kind' as kind,
               addition.added_at
        from public.board_additions addition
        cross join lateral jsonb_array_elements(addition.pieces) piece
        where addition.board_id = p_board_id
    ),
    readable as (
        select doc.id, doc.body, doc.owner_id
        from public.documents doc
        where doc.id in (select distinct added.source_id from added)
          and (doc.id = p_board_id or public.viewer_can_read_document(doc.id))
    ),
    shown as (
        select readable.id as source_id, list.id as block_id
        from readable
        cross join lateral public.board_piece_list(public.viewer_board_body(readable.body, readable.owner_id)) list
    )
    select distinct on (added.piece_id) added.piece_id, added.kind, added.added_at, added.block_id, added.source_id
    from added
    join readable on readable.id = added.source_id
    where (added.kind = 'page' and added.block_id = added.source_id::text)
       or exists (select 1 from shown where shown.source_id = added.source_id and shown.block_id = added.block_id)
    order by added.piece_id, added.added_at desc;
$function$;

-- Each change now carries the piece to mark ("piece") and the nodes and pages it sits in ("in").
create or replace function public.today_feed()
 returns table(
    board_id uuid,
    role text,
    title text,
    owner_id uuid,
    username text,
    display_name text,
    avatar_path text,
    latest_at timestamptz,
    pieces jsonb,
    seen boolean
 )
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    with candidates as (
        select follow.target_id as board_id
        from public.follows follow
        where follow.follower_id = auth.uid()
          and follow.target_type = 'pursuit'
          and public.viewer_can_open_pursuit(follow.target_id)
        union
        select pursuit.id
        from public.follows follow
        join public.documents pursuit
            on pursuit.owner_id = follow.target_owner_id
           and pursuit.role = 'pursuit'
           and pursuit.visibility <> 'hidden'
        where follow.follower_id = auth.uid()
          and follow.target_type = 'mosaic'
          and public.viewer_passes_mosaic_gate(follow.target_owner_id)
          and public.viewer_can_open_pursuit(pursuit.id)
        union
        select follow.target_id
        from public.follows follow
        where follow.follower_id = auth.uid()
          and follow.target_type = 'mosaic'
          and public.viewer_passes_mosaic_gate(follow.target_owner_id)
    ),
    recent as (
        select candidates.board_id, added.piece_id, added.block_id, added.kind, added.source_id, added.added_at
        from candidates
        cross join lateral public.board_visible_additions(candidates.board_id) added
        where added.added_at > now() - interval '24 hours'
    ),
    grouped as (
        select recent.board_id,
               max(recent.added_at) as latest_at,
               jsonb_agg(
                   jsonb_build_object(
                       'id', recent.piece_id,
                       'piece', recent.block_id,
                       'kind', recent.kind,
                       'in', public.board_path(recent.source_id, recent.board_id)
                   )
                   order by recent.added_at desc
               ) as pieces
        from recent
        group by recent.board_id
    )
    select doc.id,
           doc.role,
           doc.title,
           doc.owner_id,
           person.username,
           person.display_name,
           person.avatar_path,
           grouped.latest_at,
           grouped.pieces,
           coalesce(seen.read_at >= grouped.latest_at, false)
    from grouped
    join public.documents doc on doc.id = grouped.board_id
    join public.profiles person on person.id = doc.owner_id
    left join public.board_reads seen on seen.viewer_id = auth.uid() and seen.document_id = doc.id
    where auth.uid() is not null
      and doc.owner_id <> auth.uid()
    order by coalesce(seen.read_at >= grouped.latest_at, false), grouped.latest_at desc;
$function$;

revoke all on function public.board_units(jsonb) from public, anon, authenticated;
revoke all on function public.board_changes(jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.board_path(uuid, uuid) from public, anon, authenticated;
revoke all on function public.board_visible_additions(uuid) from public, anon, authenticated;
grant execute on function public.board_units(jsonb) to service_role;
grant execute on function public.board_changes(jsonb, jsonb) to service_role;
grant execute on function public.board_path(uuid, uuid) to service_role;
grant execute on function public.board_visible_additions(uuid) to service_role;
