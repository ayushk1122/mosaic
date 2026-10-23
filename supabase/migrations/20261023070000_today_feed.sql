-- Today: boards people follow that gained new pieces in the last 24 hours. A save that adds pieces
-- (photos, notes, drawings, a page inside a Pursuit) records them; moving or restyling a piece
-- records nothing. What a viewer gets is filtered at read time to pieces they can see now, so a
-- hidden Pursuit's widget or anything on a board they can't open never shows. Discover's update
-- marks and Explore's "Recently updated" order use the same records.

create table public.board_additions (
    id bigint generated always as identity primary key,
    -- The Mosaic or Pursuit the pieces count toward; a page's pieces count toward its Pursuit.
    board_id uuid not null references public.documents(id) on delete cascade,
    owner_id uuid not null references public.profiles(id) on delete cascade,
    -- The board or page the pieces landed on.
    source_id uuid not null references public.documents(id) on delete cascade,
    added_at timestamptz not null default now(),
    -- [{"id": "<piece id, lowercased>", "kind": "media"}]
    pieces jsonb not null
);
create index board_additions_board_time_idx on public.board_additions using btree (board_id, added_at desc);
create index board_additions_owner_id_idx on public.board_additions using btree (owner_id);
create index board_additions_source_id_idx on public.board_additions using btree (source_id);
create index board_additions_added_at_idx on public.board_additions using btree (added_at);
alter table public.board_additions enable row level security;
-- Written by the trigger and read through functions only.
revoke all on table public.board_additions from anon, authenticated;
grant all on table public.board_additions to service_role;

-- Every piece on a board, inside groups too.
create or replace function public.board_piece_list(p_body jsonb)
 returns table(id text, kind text)
 language sql
 immutable
 set search_path to 'public'
as $function$
    with recursive piece as (
        select block
        from jsonb_array_elements(case when jsonb_typeof(p_body->'blocks') = 'array' then p_body->'blocks' else '[]'::jsonb end) block
        union all
        select member
        from piece
        cross join lateral jsonb_array_elements(
            case when jsonb_typeof(piece.block->'groupMembers') = 'array' then piece.block->'groupMembers' else '[]'::jsonb end
        ) member
    )
    select lower(piece.block #>> '{id,rawValue}'), piece.block->>'kind'
    from piece
    where piece.block #>> '{id,rawValue}' is not null;
$function$;

-- The Pursuit a page or node sits in.
create or replace function public.owning_pursuit(p_document_id uuid)
 returns uuid
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    with recursive chain as (
        select doc.id, doc.parent_id, doc.role, 0 as depth
        from public.documents doc
        where doc.id = p_document_id
        union all
        select parent.id, parent.parent_id, parent.role, chain.depth + 1
        from public.documents parent
        join chain on parent.id = chain.parent_id
        where chain.role <> 'pursuit' and chain.depth < 20
    )
    select chain.id from chain where chain.role = 'pursuit' limit 1;
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
    select coalesce(jsonb_agg(jsonb_build_object('id', fresh.id, 'kind', fresh.kind)), '[]'::jsonb)
      into added
      from public.board_piece_list(new.body) fresh
     where fresh.kind not in ('group', 'tabs', 'unsupported')
       and (tg_op = 'INSERT' or not exists (
           select 1 from public.board_piece_list(old.body) before where before.id = fresh.id
       ));
    if tg_op = 'INSERT' and new.role = 'page' then
        added := added || jsonb_build_array(jsonb_build_object('id', new.id::text, 'kind', 'page'));
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
    -- Discover's marks look back to the last time someone opened a board; a month is plenty.
    delete from public.board_additions where added_at < now() - interval '30 days';
    return null;
end;
$function$;

create trigger documents_record_additions
    after insert or update of body on public.documents
    for each row
    execute function public.record_board_additions();

-- The pieces added to a board in the last month that the caller can see now, each once, with
-- when it was last added. The caller checks the board itself can be opened.
create or replace function public.board_visible_additions(p_board_id uuid)
 returns table(piece_id text, kind text, added_at timestamptz)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    with added as (
        select addition.source_id, piece->>'id' as piece_id, piece->>'kind' as kind, addition.added_at
        from public.board_additions addition
        cross join lateral jsonb_array_elements(addition.pieces) piece
        where addition.board_id = p_board_id
    ),
    -- Each board or page the pieces landed on, once, if the caller may read it.
    readable as (
        select doc.id, doc.body, doc.owner_id
        from public.documents doc
        where doc.id in (select distinct added.source_id from added)
          and (doc.id = p_board_id or public.viewer_can_read_document(doc.id))
    ),
    -- What the caller sees on each of them now.
    shown as (
        select readable.id as source_id, list.id as piece_id
        from readable
        cross join lateral public.board_piece_list(public.viewer_board_body(readable.body, readable.owner_id)) list
    )
    select distinct on (added.piece_id) added.piece_id, added.kind, added.added_at
    from added
    join readable on readable.id = added.source_id
    where (added.kind = 'page' and added.piece_id = added.source_id::text)
       or exists (select 1 from shown where shown.source_id = added.source_id and shown.piece_id = added.piece_id)
    order by added.piece_id, added.added_at desc;
$function$;

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
        -- Pursuits followed directly.
        select follow.target_id as board_id
        from public.follows follow
        where follow.follower_id = auth.uid()
          and follow.target_type = 'pursuit'
          and public.viewer_can_open_pursuit(follow.target_id)
        union
        -- Open Pursuits of people whose Mosaic is followed.
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
        -- The followed Mosaics themselves.
        select follow.target_id
        from public.follows follow
        where follow.follower_id = auth.uid()
          and follow.target_type = 'mosaic'
          and public.viewer_passes_mosaic_gate(follow.target_owner_id)
    ),
    recent as (
        select candidates.board_id, added.piece_id, added.kind, added.added_at
        from candidates
        cross join lateral public.board_visible_additions(candidates.board_id) added
        where added.added_at > now() - interval '24 hours'
    ),
    grouped as (
        select recent.board_id,
               max(recent.added_at) as latest_at,
               jsonb_agg(jsonb_build_object('id', recent.piece_id, 'kind', recent.kind) order by recent.added_at desc) as pieces
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

-- Discover's marks: new pieces since the follower last opened the board (or followed it).
create or replace function public.my_follows()
 returns table(
    target_type text,
    target_id uuid,
    owner_id uuid,
    username text,
    display_name text,
    avatar_path text,
    title text,
    cover_file text,
    cover_asset text,
    followed_at timestamp with time zone,
    has_update boolean
 )
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    select follow.target_type,
           follow.target_id,
           person.id,
           person.username,
           person.display_name,
           person.avatar_path,
           case when follow.target_type = 'pursuit' then doc.title end,
           cover.file,
           cover.asset,
           follow.created_at,
           case
               when follow.target_type = 'pursuit' then coalesce(
                   (select max(added.added_at) from public.board_visible_additions(follow.target_id) added)
                       > coalesce(own_read.read_at, follow.created_at),
                   false
               )
               else
                   public.viewer_passes_mosaic_gate(follow.target_owner_id)
                   and (
                       coalesce(
                           (select max(added.added_at) from public.board_visible_additions(follow.target_id) added)
                               > coalesce(own_read.read_at, follow.created_at),
                           false
                       )
                       or exists (
                           select 1
                           from public.documents pursuit
                           left join public.board_reads pursuit_read
                               on pursuit_read.viewer_id = auth.uid() and pursuit_read.document_id = pursuit.id
                           where pursuit.owner_id = follow.target_owner_id
                             and pursuit.role = 'pursuit'
                             and pursuit.visibility <> 'hidden'
                             and public.viewer_can_open_pursuit(pursuit.id)
                             and (select max(added.added_at) from public.board_visible_additions(pursuit.id) added) > greatest(
                                 coalesce(own_read.read_at, follow.created_at),
                                 coalesce(pursuit_read.read_at, '-infinity'::timestamptz)
                             )
                       )
                   )
           end
    from public.follows follow
    join public.profiles person on person.id = follow.target_owner_id
    join public.documents doc on doc.id = follow.target_id
    left join public.board_reads own_read
        on own_read.viewer_id = auth.uid() and own_read.document_id = follow.target_id
    left join lateral (
        select widget->>'pursuitImageFileName' as file,
               mosaic.body->'mediaAssets'->>(widget->>'pursuitImageFileName') as asset
        from public.documents mosaic
        cross join lateral public.board_pursuit_widgets(mosaic.body) widget
        where follow.target_type = 'pursuit'
          and mosaic.owner_id = follow.target_owner_id
          and mosaic.role = 'mosaic'
          and lower(widget #>> '{pursuitID,rawValue}') = follow.target_id::text
          and widget->>'pursuitImageFileName' is not null
        limit 1
    ) cover on true
    where follow.follower_id = auth.uid()
      and (follow.target_type = 'mosaic' or public.viewer_can_open_pursuit(follow.target_id))
    order by follow.created_at desc;
$function$;

-- Explore's "Recently updated": the latest new piece, not the latest save.
create or replace function public.explore_feed(
    p_kind text default 'all',
    p_seed text default '',
    p_offset integer default 0,
    p_limit integer default 30,
    p_query text default '',
    p_sort text default 'shuffle',
    p_hide_followed boolean default false
)
 returns table(
    document_id uuid,
    role text,
    title text,
    owner_id uuid,
    username text,
    display_name text,
    avatar_path text,
    preview_path text,
    mosaic_id uuid,
    follower_count bigint
 )
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    with wanted as (
        select lower(left(btrim(coalesce(p_query, '')), 60)) as text
    ),
    shared as (
        select doc.id,
               doc.role,
               doc.title,
               doc.owner_id,
               person.username,
               person.display_name,
               person.avatar_path,
               doc.owner_id::text || '/' || doc.explore_preview::text || '/display' as preview_path,
               mosaic.id as mosaic_id,
               (select count(*) from public.follows follow
                 where follow.target_id = doc.id and follow.target_type = doc.role) as follower_count,
               (select count(*) from public.follows follow
                 where follow.target_id = doc.id and follow.target_type = doc.role
                   and follow.created_at > now() - interval '7 days') as recent_followers,
               doc.explore_shared_at,
               case when p_sort = 'updated' then
                   (select max(added.added_at) from public.board_visible_additions(doc.id) added)
               end as added_at,
               md5(doc.id::text || coalesce(p_seed, '')) as shuffle
        from public.documents doc
        join public.profiles person on person.id = doc.owner_id
        join public.documents mosaic on mosaic.owner_id = doc.owner_id and mosaic.role = 'mosaic'
        cross join wanted
        where auth.uid() is not null
          and doc.owner_id <> auth.uid()
          and doc.explore_shared
          and doc.explore_preview is not null
          and doc.role in ('mosaic', 'pursuit')
          and doc.visibility = 'public'
          and mosaic.visibility = 'public'
          and (
              coalesce(p_kind, 'all') = 'all'
              or (p_kind = 'mosaics' and doc.role = 'mosaic')
              or (p_kind = 'pursuits' and doc.role = 'pursuit')
          )
          and (
              wanted.text = ''
              or strpos(lower(doc.title), wanted.text) > 0
              or strpos(lower(coalesce(person.display_name, '')), wanted.text) > 0
              or strpos(lower(person.username), wanted.text) > 0
          )
          and not (
              coalesce(p_hide_followed, false)
              and exists (
                  select 1 from public.follows mine
                  where mine.follower_id = auth.uid() and mine.target_id = doc.id
              )
          )
    )
    select id, role, title, owner_id, username, display_name, avatar_path, preview_path, mosaic_id, follower_count
    from shared
    order by
        case when p_sort = 'popular' then follower_count end desc nulls last,
        case when p_sort = 'least_popular' then follower_count end asc nulls last,
        case when p_sort = 'trending' then recent_followers end desc nulls last,
        case when p_sort = 'trending' then follower_count end desc nulls last,
        case when p_sort = 'newest' then explore_shared_at end desc nulls last,
        case when p_sort = 'updated' then added_at end desc nulls last,
        shuffle,
        id
    limit least(greatest(coalesce(p_limit, 30), 1), 60)
    offset greatest(coalesce(p_offset, 0), 0);
$function$;

revoke all on function public.board_piece_list(jsonb) from public, anon, authenticated;
revoke all on function public.owning_pursuit(uuid) from public, anon, authenticated;
revoke all on function public.record_board_additions() from public, anon, authenticated;
revoke all on function public.board_visible_additions(uuid) from public, anon, authenticated;
revoke all on function public.today_feed() from public, anon;
grant execute on function public.board_piece_list(jsonb) to service_role;
grant execute on function public.owning_pursuit(uuid) to service_role;
grant execute on function public.board_visible_additions(uuid) to service_role;
grant execute on function public.today_feed() to authenticated, service_role;
