-- Orbit keeps what each follower has seen on the server, so a board done on one phone is done on
-- every phone and after a reinstall. For each update the follower saw, the app records the time
-- of the version it saw ("seen through"). A later update to the same thing has a later time, so
-- it counts as new again. The app compares the two; the server only stores and returns them.

create table public.orbit_seen (
    viewer_id uuid not null references public.profiles(id) on delete cascade,
    board_id uuid not null references public.documents(id) on delete cascade,
    key text not null,
    seen_through timestamptz not null,
    updated_at timestamptz not null default now(),
    primary key (viewer_id, board_id, key)
);
create index orbit_seen_board_id_idx on public.orbit_seen using btree (board_id);
alter table public.orbit_seen enable row level security;
-- Written by mark_orbit_seen and read by today_feed only; owners never see who looked.
revoke all on table public.orbit_seen from anon, authenticated;
grant all on table public.orbit_seen to service_role;

-- Records what the caller has seen on a board: {"<key>": "<time of the version seen>", ...}.
-- Times later than now are treated as now. Rows untouched for two days are dropped, since
-- updates stay in Orbit for one.
create or replace function public.mark_orbit_seen(p_board uuid, p_seen jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
    if auth.uid() is null then
        raise exception 'not signed in' using errcode = '42501';
    end if;
    if p_seen is null or jsonb_typeof(p_seen) <> 'object' then
        raise exception 'seen must be an object' using errcode = '22023';
    end if;
    if not public.viewer_can_read_document(p_board) then
        return;
    end if;
    insert into public.orbit_seen (viewer_id, board_id, key, seen_through, updated_at)
    select auth.uid(), p_board, entry.key, least((entry.value #>> '{}')::timestamptz, now()), now()
    from jsonb_each(p_seen) entry
    where length(entry.key) between 1 and 300
      and jsonb_typeof(entry.value) = 'string'
    limit 500
    on conflict (viewer_id, board_id, key) do update
        set seen_through = greatest(public.orbit_seen.seen_through, excluded.seen_through),
            updated_at = now();
    delete from public.orbit_seen
    where viewer_id = auth.uid() and updated_at < now() - interval '2 days';
end;
$function$;

-- Each change now carries its time ("at"); each board, its Pursuit's cover and what the caller
-- has seen of it ("seen_keys").
drop function if exists public.today_feed();
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

revoke all on function public.mark_orbit_seen(uuid, jsonb) from public, anon;
revoke all on function public.today_feed() from public, anon;
grant execute on function public.mark_orbit_seen(uuid, jsonb) to authenticated, service_role;
grant execute on function public.today_feed() to authenticated, service_role;
