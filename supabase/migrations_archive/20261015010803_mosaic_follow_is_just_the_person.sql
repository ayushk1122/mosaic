-- Following a Mosaic follows the person, not their Pursuits; Pursuits are followed one at a time.
-- Unfollowing a Mosaic still unfollows every Pursuit of that owner.
create or replace function public.follow_mosaic(p_owner uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    mosaic uuid;
begin
    select id into mosaic from public.documents where owner_id = p_owner and role = 'mosaic';
    if auth.uid() is null or p_owner = auth.uid() or mosaic is null
       or not public.viewer_passes_mosaic_gate(p_owner) then
        raise exception 'mosaic not followable' using errcode = '42501';
    end if;

    insert into public.follows (follower_id, target_owner_id, target_type, target_id)
    values (auth.uid(), p_owner, 'mosaic', mosaic)
    on conflict do nothing;
end;
$$;

create or replace function public.respond_to_request(p_request_id uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    next_status text := case when p_accept then 'accepted' else 'declined' end;
    requester uuid;
    pursuit uuid;
begin
    update public.mosaic_access_requests
    set status = next_status, responded_at = now()
    where id = p_request_id and owner_id = auth.uid() and status = 'pending'
    returning requester_id into requester;
    if found then
        if p_accept then
            insert into public.follows (follower_id, target_owner_id, target_type, target_id)
            select requester, auth.uid(), 'mosaic', doc.id
            from public.documents doc
            where doc.owner_id = auth.uid() and doc.role = 'mosaic'
            on conflict do nothing;
        end if;
        return;
    end if;

    update public.pursuit_access_requests
    set status = next_status, responded_at = now()
    where id = p_request_id and owner_id = auth.uid() and status = 'pending'
    returning requester_id, pursuit_id into requester, pursuit;
    if found then
        if p_accept then
            insert into public.follows (follower_id, target_owner_id, target_type, target_id)
            values (requester, auth.uid(), 'pursuit', pursuit)
            on conflict do nothing;
        end if;
        return;
    end if;

    raise exception 'request not found' using errcode = '42501';
end;
$$;

-- Pursuit follows written in the same transaction as the Mosaic follow were added by the old
-- follow_mosaic or respond_to_request, not chosen; they share its created_at exactly.
delete from public.follows pursuit_follow
using public.follows mosaic_follow
where pursuit_follow.target_type = 'pursuit'
  and mosaic_follow.target_type = 'mosaic'
  and mosaic_follow.follower_id = pursuit_follow.follower_id
  and mosaic_follow.target_owner_id = pursuit_follow.target_owner_id
  and mosaic_follow.created_at = pursuit_follow.created_at
  and not exists (
      select 1 from public.pursuit_access_requests request
      where request.requester_id = pursuit_follow.follower_id
        and request.pursuit_id = pursuit_follow.target_id
        and request.status = 'accepted'
  );
