-- Daily Visits: someone opening another person's Mosaic or Pursuit.
-- Owners read these back only as counts of distinct visitors since their local midnight.
-- Rows are kept for 90 days so longer-range visit analytics stay possible.

create table public.visits (
    id bigint generated always as identity primary key,
    document_id uuid not null references public.documents (id) on delete cascade,
    owner_id uuid not null references public.profiles (id) on delete cascade,
    visitor_id uuid not null references public.profiles (id) on delete cascade,
    visited_at timestamptz not null default now()
);

create index visits_owner_visited_at on public.visits (owner_id, visited_at);
create index visits_visitor_document_visited_at on public.visits (visitor_id, document_id, visited_at desc);
create index visits_visited_at on public.visits (visited_at);

-- Rows are written and read only through the functions below.
alter table public.visits enable row level security;
revoke all on table public.visits from anon, authenticated;

-- Records a visit when the caller can see the board and isn't its owner. Anything else is ignored
-- rather than raised, so a visit never fails because of it.
create or replace function public.record_visit(p_document_id uuid)
returns void
language plpgsql
security definer
set search_path = public
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

-- Distinct visitors today for each of the caller's boards that has any.
-- "Today" starts at midnight in p_time_zone (the owner's device); an unknown zone falls back to UTC.
create or replace function public.circle_visits(p_time_zone text)
returns table (document_id uuid, visit_count bigint)
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
    zone text := 'UTC';
    day_start timestamptz;
begin
    if auth.uid() is null then
        return;
    end if;

    begin
        perform now() at time zone p_time_zone;
        zone := coalesce(p_time_zone, 'UTC');
    exception when others then
        zone := 'UTC';
    end;

    day_start := date_trunc('day', now() at time zone zone) at time zone zone;

    return query
    select visit.document_id, count(distinct visit.visitor_id)
    from public.visits visit
    where visit.owner_id = auth.uid()
      and visit.visited_at >= day_start
    group by visit.document_id;
end;
$function$;

revoke all on function public.record_visit(uuid) from public, anon;
revoke all on function public.circle_visits(text) from public, anon;
grant execute on function public.record_visit(uuid) to authenticated;
grant execute on function public.circle_visits(text) to authenticated;
