-- Removing someone from the Mosaic also takes back an approved view request,
-- so following a private Mosaic again needs a new request.
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
        if not found then
            raise exception 'follower not found' using errcode = '42501';
        end if;
        update public.mosaic_access_requests
        set status = 'revoked', responded_at = now()
        where owner_id = auth.uid()
          and requester_id = p_follower_id
          and status = 'accepted';
    else
        delete from public.follows
        where target_id = p_document_id
          and follower_id = p_follower_id
          and target_owner_id = auth.uid();
        if not found then
            raise exception 'follower not found' using errcode = '42501';
        end if;
    end if;
end;
$$;
