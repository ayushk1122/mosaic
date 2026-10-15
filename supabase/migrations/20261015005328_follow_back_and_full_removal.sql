-- Removing someone from the Mosaic removes every follow they have of the owner's boards,
-- matching unfollow_mosaic on the follower's side. A Pursuit list still removes just that Pursuit.
create or replace function public.remove_follower(p_document_id uuid, p_follower_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if exists (
        select 1 from public.documents
        where id = p_document_id and owner_id = auth.uid() and role = 'mosaic'
    ) then
        delete from public.follows
        where follower_id = p_follower_id
          and target_owner_id = auth.uid();
    else
        delete from public.follows
        where target_id = p_document_id
          and follower_id = p_follower_id
          and target_owner_id = auth.uid();
    end if;
    if not found then
        raise exception 'follower not found' using errcode = '42501';
    end if;
end;
$$;

-- Each person also carries what the follow button needs: whether they follow the owner's Mosaic,
-- whether the owner follows or has asked to see theirs, and whether theirs can be followed now.
drop function public.circle_people(uuid);

create function public.circle_people(p_document_id uuid)
returns table(
    kind text, request_id uuid, person_id uuid, username text, display_name text, avatar_path text,
    created_at timestamptz, follows_me boolean, i_follow boolean, i_requested boolean,
    has_mosaic boolean, can_follow boolean
)
language sql
stable
security definer
set search_path = public
as $$
    with bubble as (
        select doc.id, doc.role
        from public.documents doc
        where doc.id = p_document_id
          and doc.owner_id = auth.uid()
          and doc.role in ('mosaic', 'pursuit')
    ),
    entries as (
        select 'request'::text as kind, request.id as request_id, request.requester_id as person_id, request.created_at
        from bubble
        join public.mosaic_access_requests request
            on bubble.role = 'mosaic' and request.owner_id = auth.uid() and request.status = 'pending'
        union all
        select 'request', request.id, request.requester_id, request.created_at
        from bubble
        join public.pursuit_access_requests request
            on bubble.role = 'pursuit' and request.pursuit_id = bubble.id and request.status = 'pending'
        union all
        select 'follower', null, follow.follower_id, follow.created_at
        from bubble
        join public.follows follow
            on follow.target_id = bubble.id and follow.target_type = bubble.role
    )
    select entries.kind, entries.request_id, entries.person_id,
           profile.username, profile.display_name, profile.avatar_path, entries.created_at,
           exists (
               select 1 from public.follows f
               where f.follower_id = entries.person_id and f.target_owner_id = auth.uid() and f.target_type = 'mosaic'
           ),
           exists (
               select 1 from public.follows f
               where f.follower_id = auth.uid() and f.target_owner_id = entries.person_id and f.target_type = 'mosaic'
           ),
           exists (
               select 1 from public.mosaic_access_requests r
               where r.requester_id = auth.uid() and r.owner_id = entries.person_id and r.status = 'pending'
           ),
           their.id is not null,
           their.id is not null and public.viewer_passes_mosaic_gate(entries.person_id)
    from entries
    join public.profiles profile on profile.id = entries.person_id
    left join public.documents their on their.owner_id = entries.person_id and their.role = 'mosaic'
    order by (entries.kind = 'request') desc, entries.created_at desc;
$$;

revoke execute on function public.circle_people(uuid) from public, anon;
grant execute on function public.circle_people(uuid) to authenticated;
