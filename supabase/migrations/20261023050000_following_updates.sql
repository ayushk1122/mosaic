-- Following updates: Discover marks each followed Mosaic and Pursuit that changed since the
-- follower last opened it. Opening a board records when; a change is a save of the board itself or
-- of a page inside it. A Mosaic is also marked while one of its Pursuits the follower can open has
-- changed since they last saw that Pursuit or the Mosaic.

create table public.board_reads (
    viewer_id uuid not null references public.profiles(id) on delete cascade,
    document_id uuid not null references public.documents(id) on delete cascade,
    read_at timestamptz not null default now(),
    primary key (viewer_id, document_id)
);
create index board_reads_document_id_idx on public.board_reads using btree (document_id);
alter table public.board_reads enable row level security;
-- Written by record_visit and read by my_follows only.
revoke all on table public.board_reads from anon, authenticated;
grant all on table public.board_reads to service_role;

-- Boards already opened recently start as read, so the first look isn't a wall of marks.
insert into public.board_reads (viewer_id, document_id, read_at)
select visit.visitor_id, visit.document_id, max(visit.visited_at)
from public.visits visit
group by visit.visitor_id, visit.document_id
on conflict (viewer_id, document_id) do nothing;

-- When a board or anything inside it was last saved. Pursuits are boards of their own, so a tree
-- stops at them.
create or replace function public.board_changed_at(p_document_id uuid)
 returns timestamptz
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    with recursive tree as (
        select doc.id, doc.updated_at
        from public.documents doc
        where doc.id = p_document_id
        union all
        select child.id, child.updated_at
        from public.documents child
        join tree on child.parent_id = tree.id
        where child.role <> 'pursuit'
    )
    select max(tree.updated_at) from tree;
$function$;

revoke all on function public.board_changed_at(uuid) from public, anon, authenticated;
grant execute on function public.board_changed_at(uuid) to service_role;

create or replace function public.record_visit(p_document_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
    target public.documents%rowtype;
begin
    if auth.uid() is null then
        return;
    end if;

    select * into target
    from public.documents doc
    where doc.id = p_document_id
      and doc.role in ('mosaic', 'pursuit');

    if not found or target.owner_id = auth.uid() then
        return;
    end if;

    if target.role = 'mosaic' then
        if not public.viewer_passes_mosaic_gate(target.owner_id) then
            return;
        end if;
    elsif not public.viewer_can_open_pursuit(target.id) then
        return;
    end if;

    -- Every open counts as reading it, even one too soon after the last to count as a visit.
    insert into public.board_reads (viewer_id, document_id, read_at)
    values (auth.uid(), target.id, now())
    on conflict (viewer_id, document_id) do update set read_at = excluded.read_at;

    -- Distinct visitors are counted on read; this only keeps repeat opens from adding rows.
    if exists (
        select 1
        from public.visits visit
        where visit.visitor_id = auth.uid()
          and visit.document_id = target.id
          and visit.visited_at > now() - interval '10 minutes'
    ) then
        return;
    end if;

    insert into public.visits (document_id, owner_id, visitor_id)
    values (target.id, target.owner_id, auth.uid());

    delete from public.visits visit
    where visit.visited_at < now() - interval '90 days';
end;
$function$;

drop function if exists public.my_follows();

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
               when follow.target_type = 'pursuit' then
                   public.board_changed_at(follow.target_id) > coalesce(own_read.read_at, follow.created_at)
               else
                   public.viewer_passes_mosaic_gate(follow.target_owner_id)
                   and (
                       public.board_changed_at(follow.target_id) > coalesce(own_read.read_at, follow.created_at)
                       or exists (
                           select 1
                           from public.documents pursuit
                           left join public.board_reads pursuit_read
                               on pursuit_read.viewer_id = auth.uid() and pursuit_read.document_id = pursuit.id
                           where pursuit.owner_id = follow.target_owner_id
                             and pursuit.role = 'pursuit'
                             and pursuit.visibility <> 'hidden'
                             and public.viewer_can_open_pursuit(pursuit.id)
                             and public.board_changed_at(pursuit.id) > greatest(
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

revoke all on function public.my_follows() from public, anon;
grant execute on function public.my_follows() to authenticated, service_role;
