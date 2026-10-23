-- Orbit is for catching up on what the follower chose to see: only boards they follow
-- themselves. A followed Mosaic no longer brings in its owner's Pursuits that aren't followed too.

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
    seen boolean,
    cover_file text,
    cover_asset text,
    seen_keys jsonb
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
                       'in', public.board_path(recent.source_id, recent.board_id),
                       'at', recent.added_at
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
           coalesce(seen.read_at >= grouped.latest_at, false),
           cover.file,
           cover.asset,
           (select coalesce(jsonb_object_agg(mine.key, mine.seen_through), '{}'::jsonb)
              from public.orbit_seen mine
             where mine.viewer_id = auth.uid() and mine.board_id = doc.id)
    from grouped
    join public.documents doc on doc.id = grouped.board_id
    join public.profiles person on person.id = doc.owner_id
    left join public.board_reads seen on seen.viewer_id = auth.uid() and seen.document_id = doc.id
    left join lateral (
        select widget->>'pursuitImageFileName' as file,
               mosaic.body->'mediaAssets'->>(widget->>'pursuitImageFileName') as asset
        from public.documents mosaic
        cross join lateral public.board_pursuit_widgets(mosaic.body) widget
        where doc.role = 'pursuit'
          and mosaic.owner_id = doc.owner_id
          and mosaic.role = 'mosaic'
          and lower(widget #>> '{pursuitID,rawValue}') = doc.id::text
          and widget->>'pursuitImageFileName' is not null
        limit 1
    ) cover on true
    where auth.uid() is not null
      and doc.owner_id <> auth.uid()
    order by coalesce(seen.read_at >= grouped.latest_at, false), grouped.latest_at desc;
$function$;

revoke all on function public.today_feed() from public, anon;
grant execute on function public.today_feed() to authenticated, service_role;
