-- The profile card shows how many people follow a Mosaic, only to people who may see that Mosaic.
drop function if exists public.profile_view(uuid);

create or replace function public.profile_view(p_user_id uuid)
 returns table(
    user_id uuid,
    username text,
    display_name text,
    avatar_path text,
    mosaic_id uuid,
    mosaic_visibility text,
    can_view boolean,
    request_status text,
    follows_mosaic boolean,
    follower_count bigint
 )
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    select person.id,
           person.username,
           person.display_name,
           person.avatar_path,
           mosaic.id,
           mosaic.visibility,
           gate.can_view,
           (
               select request.status
               from public.mosaic_access_requests request
               where request.owner_id = person.id
                 and request.requester_id = auth.uid()
           ),
           exists (
               select 1
               from public.follows follow
               where follow.follower_id = auth.uid()
                 and follow.target_type = 'mosaic'
                 and follow.target_owner_id = person.id
           ),
           case when gate.can_view then (
               select count(*)
               from public.follows follow
               where follow.target_type = 'mosaic'
                 and follow.target_id = mosaic.id
           ) end
    from public.profiles person
    left join public.documents mosaic
        on mosaic.owner_id = person.id and mosaic.role = 'mosaic'
    cross join lateral (
        select mosaic.id is not null and public.viewer_passes_mosaic_gate(person.id) as can_view
    ) gate
    where person.id = p_user_id
      and auth.uid() is not null;
$function$;

revoke all on function public.profile_view(uuid) from public, anon;
grant execute on function public.profile_view(uuid) to authenticated, service_role;
