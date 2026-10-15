-- Fixes from the Supabase security and performance advisors. No access rule changes meaning.

-- Trigger functions run from their triggers without EXECUTE, so nobody needs to call them through the API.
-- This matches handle_new_user and enqueue_media_job.
revoke all on function public.revoke_pursuit_access_on_unfollow() from public, anon, authenticated;
revoke all on function public.touch_updated_at() from public, anon, authenticated;

-- A fixed search path, like every other function here.
alter function public.touch_updated_at() set search_path = public;

-- Row-level security: `(select auth.uid())` is evaluated once per query instead of once per row.

alter policy activity_insert_owner on public.activity_events
    with check (
        actor_id = (select auth.uid())
        and exists (
            select 1
            from public.documents doc
            where doc.id = activity_events.document_id
              and doc.owner_id = (select auth.uid())
        )
    );

alter policy activity_select_owner_or_follower on public.activity_events
    using (
        actor_id = (select auth.uid())
        or (
            public.viewer_can_read_document(document_id)
            and exists (
                select 1
                from public.follows follow
                join public.documents doc on doc.id = activity_events.document_id
                where follow.follower_id = (select auth.uid())
                  and (
                      (follow.target_type = 'pursuit' and follow.target_id = doc.id)
                      or (
                          follow.target_type = 'mosaic'
                          and follow.target_owner_id = doc.owner_id
                          and doc.role = any (array['mosaic', 'pursuit'])
                      )
                  )
            )
        )
    );

alter policy circle_seen_owner_all on public.circle_seen
    using (owner_id = (select auth.uid()))
    with check (owner_id = (select auth.uid()));

alter policy documents_owner_all on public.documents
    using (owner_id = (select auth.uid()))
    with check (owner_id = (select auth.uid()));

alter policy follows_delete_follower on public.follows
    using (follower_id = (select auth.uid()));

alter policy follows_insert_follower on public.follows
    with check (
        follower_id = (select auth.uid())
        and (
            (
                target_type = 'mosaic'
                and public.viewer_passes_mosaic_gate(target_owner_id)
                and exists (
                    select 1
                    from public.documents mosaic
                    where mosaic.id = follows.target_id
                      and mosaic.owner_id = follows.target_owner_id
                      and mosaic.role = 'mosaic'
                )
            )
            or (
                target_type = 'pursuit'
                and public.viewer_can_read_document(target_id)
                and exists (
                    select 1
                    from public.documents pursuit
                    where pursuit.id = follows.target_id
                      and pursuit.owner_id = follows.target_owner_id
                      and pursuit.role = 'pursuit'
                )
            )
        )
    );

alter policy follows_select_follower on public.follows
    using (follower_id = (select auth.uid()) or target_owner_id = (select auth.uid()));

alter policy media_owner_all on public.media_assets
    using (owner_id = (select auth.uid()))
    with check (owner_id = (select auth.uid()));

alter policy media_jobs_owner_select on public.media_jobs
    using (
        exists (
            select 1
            from public.media_assets asset
            where asset.id = media_jobs.asset_id
              and asset.owner_id = (select auth.uid())
        )
    );

alter policy access_insert_requester on public.mosaic_access_requests
    with check (
        requester_id = (select auth.uid())
        and owner_id <> (select auth.uid())
        and status = 'pending'
    );

alter policy access_select_parties on public.mosaic_access_requests
    using (owner_id = (select auth.uid()) or requester_id = (select auth.uid()));

alter policy access_update_owner on public.mosaic_access_requests
    using (owner_id = (select auth.uid()))
    with check (owner_id = (select auth.uid()));

alter policy profiles_update_self on public.profiles
    using (id = (select auth.uid()))
    with check (
        id = (select auth.uid())
        and username ~ '^[a-z0-9_]{3,20}$'
        and (avatar_path is null or split_part(avatar_path, '/', 1) = (select auth.uid())::text)
    );

alter policy pursuit_access_delete_requester on public.pursuit_access_requests
    using (requester_id = (select auth.uid()));

alter policy pursuit_access_insert_requester on public.pursuit_access_requests
    with check (
        requester_id = (select auth.uid())
        and owner_id <> (select auth.uid())
        and status = 'pending'
        and public.pursuit_is_requestable(pursuit_id, owner_id)
    );

alter policy pursuit_access_select_parties on public.pursuit_access_requests
    using (owner_id = (select auth.uid()) or requester_id = (select auth.uid()));

alter policy pursuit_access_update_owner on public.pursuit_access_requests
    using (owner_id = (select auth.uid()))
    with check (owner_id = (select auth.uid()));
