-- The Pursuit card shows how many people follow a Pursuit, only to people who may open it.
drop function if exists public.viewer_pursuits(uuid);

create or replace function public.viewer_pursuits(p_owner uuid)
 returns table(
    pursuit_id uuid,
    title text,
    visibility text,
    can_open boolean,
    request_status text,
    following boolean,
    follower_count bigint
 )
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    select doc.id,
           doc.title,
           doc.visibility,
           gate.can_open,
           (
               select request.status
               from public.pursuit_access_requests request
               where request.pursuit_id = doc.id
                 and request.requester_id = auth.uid()
           ),
           exists (
               select 1
               from public.follows follow
               where follow.follower_id = auth.uid()
                 and follow.target_type = 'pursuit'
                 and follow.target_id = doc.id
           ),
           case when gate.can_open then (
               select count(*)
               from public.follows follow
               where follow.target_type = 'pursuit'
                 and follow.target_id = doc.id
           ) end
    from public.documents doc
    cross join lateral (select public.viewer_can_open_pursuit(doc.id) as can_open) gate
    where doc.owner_id = p_owner
      and doc.role = 'pursuit'
      and doc.visibility <> 'hidden'
      and auth.uid() is not null
      and public.viewer_passes_mosaic_gate(p_owner)
    order by doc.created_at;
$function$;

revoke all on function public.viewer_pursuits(uuid) from public, anon;
grant execute on function public.viewer_pursuits(uuid) to authenticated, service_role;
