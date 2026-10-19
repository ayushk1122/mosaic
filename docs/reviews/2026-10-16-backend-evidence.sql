-- Read-only evidence snapshot, Mosaic-dev, October 16, 2026.
-- Historical evidence only. Do NOT apply this file as a migration.
-- Contains schema/function definitions, no account rows, tokens, or user media.

-- Function ancestor_pursuit_id; SECURITY DEFINER=true; ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.ancestor_pursuit_id(p_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    with recursive chain as (
        select id, parent_id, role, 0 as depth
        from public.documents
        where id = p_id
        union all
        select parent.id, parent.parent_id, parent.role, chain.depth + 1
        from public.documents parent
        join chain on parent.id = chain.parent_id
    )
    select id
    from chain
    where role = 'pursuit'
    order by depth
    limit 1;
$function$


-- Function ancestor_pursuit_is_public; SECURITY DEFINER=true; ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.ancestor_pursuit_is_public(p_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    with recursive chain as (
        select id, parent_id, role, visibility
        from public.documents
        where id = p_id
        union all
        select child.id, child.parent_id, child.role, child.visibility
        from public.documents child
        join chain on child.id = chain.parent_id
    )
    select coalesce(bool_or(role = 'pursuit' and visibility = 'public'), false)
    from chain;
$function$


-- Function board_pursuit_widgets; SECURITY DEFINER=false; ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.board_pursuit_widgets(p_body jsonb)
 RETURNS SETOF jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
    with top as (
        select value
        from jsonb_array_elements(
            case jsonb_typeof(p_body->'blocks') when 'array' then p_body->'blocks' else '[]'::jsonb end
        )
    )
    select value from top where value ? 'pursuitID'
    union all
    select member.value
    from top
    cross join lateral jsonb_array_elements(
        case jsonb_typeof(top.value->'groupMembers') when 'array' then top.value->'groupMembers' else '[]'::jsonb end
    ) member
    where member.value ? 'pursuitID';
$function$


-- Function circle_counts; SECURITY DEFINER=true; ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.circle_counts()
 RETURNS TABLE(document_id uuid, role text, follower_count bigint, update_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    select
        doc.id,
        doc.role,
        (
            select count(*)
            from public.follows follow
            where (doc.role = 'mosaic' and follow.target_type = 'mosaic' and follow.target_id = doc.id)
               or (doc.role = 'pursuit' and follow.target_type = 'pursuit' and follow.target_id = doc.id)
        ),
        (
            select count(*)
            from public.activity_events event
            where event.document_id = doc.id
        )
    from public.documents doc
    where doc.owner_id = auth.uid()
      and doc.role in ('mosaic', 'pursuit');
$function$


-- Function circle_overview; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.circle_overview()
 RETURNS TABLE(document_id uuid, role text, title text, visibility text, follower_count bigint, pending_count bigint, badge_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    with bubbles as (
        select doc.id, doc.role, doc.title, doc.visibility, doc.created_at,
               coalesce(seen.seen_at, '-infinity'::timestamptz) as seen_at
        from public.documents doc
        left join public.circle_seen seen
            on seen.owner_id = auth.uid() and seen.document_id = doc.id
        where doc.owner_id = auth.uid()
          and (doc.role = 'mosaic' or (doc.role = 'pursuit' and doc.visibility <> 'hidden'))
    ),
    follows_by as (
        select bubble.id,
               count(follow.*) as followers,
               count(follow.*) filter (where follow.created_at > bubble.seen_at) as fresh
        from bubbles bubble
        left join public.follows follow
            on follow.target_id = bubble.id
           and follow.target_type = bubble.role
        group by bubble.id
    ),
    requests_by as (
        select bubble.id,
               count(request.*) filter (where request.status = 'pending') as pending
        from bubbles bubble
        left join lateral (
            select mosaic_request.status
            from public.mosaic_access_requests mosaic_request
            where bubble.role = 'mosaic' and mosaic_request.owner_id = auth.uid()
            union all
            select pursuit_request.status
            from public.pursuit_access_requests pursuit_request
            where bubble.role = 'pursuit' and pursuit_request.pursuit_id = bubble.id
        ) request on true
        group by bubble.id
    )
    select bubble.id, bubble.role, bubble.title, bubble.visibility,
           follows_by.followers, requests_by.pending, requests_by.pending + follows_by.fresh
    from bubbles bubble
    join follows_by on follows_by.id = bubble.id
    join requests_by on requests_by.id = bubble.id
    where auth.uid() is not null
    order by (bubble.role = 'mosaic') desc, bubble.created_at;
$function$


-- Function circle_people; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.circle_people(p_document_id uuid)
 RETURNS TABLE(kind text, request_id uuid, person_id uuid, username text, display_name text, avatar_path text, created_at timestamp with time zone, follows_me boolean, i_follow boolean, i_requested boolean, has_mosaic boolean, can_follow boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


-- Function circle_visits; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.circle_visits(p_time_zone text)
 RETURNS TABLE(document_id uuid, visit_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


-- Function enqueue_media_job; SECURITY DEFINER=true; ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.enqueue_media_job()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
    insert into public.media_jobs (asset_id, status)
    values (new.id, 'queued');
    return new;
end;
$function$


-- Function filter_pursuit_blocks; SECURITY DEFINER=true; ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.filter_pursuit_blocks(p_blocks jsonb, p_owner uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    result jsonb := '[]'::jsonb;
    block jsonb;
    shown jsonb;
    members jsonb;
    member jsonb;
begin
    if p_blocks is null or jsonb_typeof(p_blocks) <> 'array' then
        return '[]'::jsonb;
    end if;

    for block in select value from jsonb_array_elements(p_blocks)
    loop
        if block->>'kind' = 'pursuit' then
            shown := public.viewer_pursuit_block(block, p_owner);
            if shown is not null then
                result := result || jsonb_build_array(shown);
            end if;
        elsif block->>'kind' = 'group' then
            members := '[]'::jsonb;
            for member in select value from jsonb_array_elements(coalesce(block->'groupMembers', '[]'::jsonb))
            loop
                if member->>'kind' = 'pursuit' then
                    shown := public.viewer_pursuit_block(member, p_owner);
                    if shown is not null then
                        members := members || jsonb_build_array(shown);
                    end if;
                else
                    members := members || jsonb_build_array(member);
                end if;
            end loop;
            result := result || jsonb_build_array(jsonb_set(block, '{groupMembers}', members, true));
        else
            result := result || jsonb_build_array(block);
        end if;
    end loop;

    return result;
end;
$function$


-- Function follow_mosaic; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.follow_mosaic(p_owner uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


-- Function follow_pursuit; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.follow_pursuit(p_pursuit_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    owner uuid;
begin
    select owner_id into owner from public.documents where id = p_pursuit_id and role = 'pursuit';
    if auth.uid() is null or owner is null or owner = auth.uid()
       or not public.viewer_can_open_pursuit(p_pursuit_id) then
        raise exception 'pursuit not followable' using errcode = '42501';
    end if;

    insert into public.follows (follower_id, target_owner_id, target_type, target_id)
    values (auth.uid(), owner, 'pursuit', p_pursuit_id)
    on conflict do nothing;
end;
$function$


-- Function handle_new_user; SECURITY DEFINER=true; ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
    insert into public.profiles (id, username)
    values (
        new.id,
        'user_' || substr(replace(new.id::text, '-', ''), 1, 12)
    );
    return new;
end;
$function$


-- Function mark_circle_seen; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.mark_circle_seen(p_document_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
    if not exists (
        select 1 from public.documents doc
        where doc.id = p_document_id and doc.owner_id = auth.uid()
    ) then
        raise exception 'not your bubble' using errcode = '42501';
    end if;

    insert into public.circle_seen (owner_id, document_id, seen_at)
    values (auth.uid(), p_document_id, now())
    on conflict (owner_id, document_id) do update set seen_at = excluded.seen_at;
end;
$function$


-- Function my_follows; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.my_follows()
 RETURNS TABLE(target_type text, target_id uuid, owner_id uuid, username text, display_name text, avatar_path text, title text, cover_file text, cover_asset text, followed_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    select follow.target_type,
           follow.target_id,
           person.id,
           person.username,
           person.display_name,
           person.avatar_path,
           case when follow.target_type = 'pursuit' then doc.title end,
           cover.file,
           cover.asset,
           follow.created_at
    from public.follows follow
    join public.profiles person on person.id = follow.target_owner_id
    join public.documents doc on doc.id = follow.target_id
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
$function$


-- Function own_mosaic_id; SECURITY DEFINER=false; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.own_mosaic_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
    select id
    from public.documents
    where owner_id = auth.uid()
      and role = 'mosaic'
    limit 1;
$function$


-- Function profile_view; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.profile_view(p_user_id uuid)
 RETURNS TABLE(user_id uuid, username text, display_name text, avatar_path text, mosaic_id uuid, mosaic_visibility text, can_view boolean, request_status text, follows_mosaic boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    select person.id,
           person.username,
           person.display_name,
           person.avatar_path,
           mosaic.id,
           mosaic.visibility,
           mosaic.id is not null and public.viewer_passes_mosaic_gate(person.id),
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
           )
    from public.profiles person
    left join public.documents mosaic
        on mosaic.owner_id = person.id and mosaic.role = 'mosaic'
    where person.id = p_user_id
      and auth.uid() is not null;
$function$


-- Function pursuit_is_requestable; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.pursuit_is_requestable(p_pursuit_id uuid, p_owner uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    select exists (
        select 1
        from public.documents pursuit
        where pursuit.id = p_pursuit_id
          and pursuit.owner_id = p_owner
          and pursuit.role = 'pursuit'
          and pursuit.visibility = 'private'
    )
    and public.viewer_passes_mosaic_gate(p_owner);
$function$


-- Function read_document; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.read_document(p_id uuid)
 RETURNS TABLE(id uuid, parent_id uuid, role text, title text, visibility text, body jsonb, revision bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    doc public.documents%rowtype;
begin
    if not public.viewer_can_read_document(p_id) then
        return;
    end if;

    select * into doc from public.documents where documents.id = p_id;

    id := doc.id;
    parent_id := doc.parent_id;
    role := doc.role;
    title := doc.title;
    visibility := doc.visibility;
    revision := doc.revision;
    if doc.owner_id = auth.uid() then
        body := doc.body;
    else
        body := public.viewer_board_body(doc.body, doc.owner_id);
    end if;
    return next;
end;
$function$


-- Function record_visit; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.record_visit(p_document_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


-- Function remove_follower; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.remove_follower(p_document_id uuid, p_follower_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


-- Function request_mosaic_access; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.request_mosaic_access(p_owner uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    result text;
begin
    if auth.uid() is null or p_owner = auth.uid()
       or not exists (select 1 from public.documents where owner_id = p_owner and role = 'mosaic') then
        raise exception 'mosaic not requestable' using errcode = '42501';
    end if;

    insert into public.mosaic_access_requests (owner_id, requester_id)
    values (p_owner, auth.uid())
    on conflict (owner_id, requester_id) do update
        set status = 'pending', created_at = now(), responded_at = null
        where public.mosaic_access_requests.status in ('declined', 'revoked');

    select status into result
    from public.mosaic_access_requests
    where owner_id = p_owner and requester_id = auth.uid();
    return result;
end;
$function$


-- Function request_pursuit_access; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.request_pursuit_access(p_pursuit_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    owner uuid;
    result text;
begin
    select owner_id into owner from public.documents where id = p_pursuit_id and role = 'pursuit';
    if auth.uid() is null or owner is null or owner = auth.uid()
       or not public.pursuit_is_requestable(p_pursuit_id, owner) then
        raise exception 'pursuit not requestable' using errcode = '42501';
    end if;

    insert into public.pursuit_access_requests (owner_id, requester_id, pursuit_id)
    values (owner, auth.uid(), p_pursuit_id)
    on conflict (requester_id, pursuit_id) do update
        set status = 'pending', created_at = now(), responded_at = null
        where public.pursuit_access_requests.status in ('declined', 'revoked');

    select status into result
    from public.pursuit_access_requests
    where pursuit_id = p_pursuit_id and requester_id = auth.uid();
    return result;
end;
$function$


-- Function respond_to_request; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.respond_to_request(p_request_id uuid, p_accept boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


-- Function revoke_pursuit_access_on_unfollow; SECURITY DEFINER=true; ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.revoke_pursuit_access_on_unfollow()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
    if old.target_type = 'pursuit' then
        update public.pursuit_access_requests
        set status = 'revoked', responded_at = now()
        where requester_id = old.follower_id
          and pursuit_id = old.target_id
          and status = 'accepted';
    end if;
    return old;
end;
$function$


-- Function save_document; SECURITY DEFINER=false; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.save_document(p_id uuid, p_parent_id uuid, p_role text, p_title text, p_body jsonb, p_expected_revision bigint)
 RETURNS TABLE(revision bigint)
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
    next_revision bigint;
    previous_role text;
begin
    if auth.uid() is null then
        raise exception 'sign in required' using errcode = '28000';
    end if;

    if p_role not in ('mosaic', 'pursuit', 'node', 'page') then
        raise exception 'invalid role' using errcode = '22023';
    end if;

    if p_parent_id is not null and not exists (
        select 1
        from public.documents parent
        where parent.id = p_parent_id
          and parent.owner_id = auth.uid()
    ) then
        raise exception 'parent not owned' using errcode = '42501';
    end if;

    select documents.role
      into previous_role
      from public.documents
     where documents.id = p_id
       and documents.owner_id = auth.uid();

    if previous_role is not null
       and previous_role is distinct from p_role
       and not (
           (previous_role = 'pursuit' and p_role = 'node')
           or (previous_role = 'node' and p_role = 'pursuit')
       ) then
        raise exception 'invalid role change' using errcode = '22023';
    end if;

    update public.documents
    set parent_id = p_parent_id,
        role = p_role,
        title = p_title,
        body = p_body,
        visibility = case
            when previous_role is distinct from p_role
                 and p_role in ('pursuit', 'node')
            then 'hidden'
            else documents.visibility
        end,
        revision = documents.revision + 1,
        updated_at = now()
    where documents.id = p_id
      and documents.owner_id = auth.uid()
      and documents.revision = p_expected_revision
    returning documents.revision into next_revision;

    if next_revision is not null then
        revision := next_revision;
        return next;
        return;
    end if;

    if exists (select 1 from public.documents existing where existing.id = p_id) then
        raise exception 'revision conflict' using errcode = 'P0001';
    end if;

    if p_role = 'mosaic' and exists (
        select 1
        from public.documents existing
        where existing.owner_id = auth.uid()
          and existing.role = 'mosaic'
    ) then
        raise exception 'mosaic exists' using errcode = '23505';
    end if;

    insert into public.documents (id, owner_id, parent_id, role, title, visibility, body, revision)
    values (
        p_id,
        auth.uid(),
        p_parent_id,
        p_role,
        coalesce(p_title, ''),
        case when p_role = 'mosaic' then 'private' else 'hidden' end,
        p_body,
        1
    );

    revision := 1;
    return next;
end;
$function$


-- Function search_profiles; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.search_profiles(p_query text)
 RETURNS TABLE(id uuid, username text, display_name text, avatar_path text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    with search as (
        select replace(replace(replace(
                   lower(ltrim(trim(p_query), '@')),
                   '\', '\\'), '%', '\%'), '_', '\_') as text
    )
    select profile.id, profile.username, profile.display_name, profile.avatar_path
    from public.profiles profile, search
    where auth.uid() is not null
      and search.text <> ''
      and profile.username is not null
      and (profile.username like search.text || '%'
           or lower(profile.display_name) like search.text || '%'
           or lower(profile.display_name) like '% ' || search.text || '%')
    order by (profile.username like search.text || '%') desc, profile.username
    limit 20;
$function$


-- Function set_document_visibility; SECURITY DEFINER=false; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.set_document_visibility(p_id uuid, p_visibility text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
    if p_visibility not in ('public', 'private', 'hidden') then
        raise exception 'invalid visibility' using errcode = '22023';
    end if;

    update public.documents
    set visibility = p_visibility,
        updated_at = now()
    where id = p_id
      and owner_id = auth.uid()
      and (
          (role = 'pursuit')
          or (role = 'mosaic' and p_visibility in ('public', 'private'))
      );

    if not found then
        raise exception 'visibility not updated' using errcode = '42501';
    end if;
end;
$function$


-- Function touch_updated_at; SECURITY DEFINER=false; ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
    new.updated_at = now();
    return new;
end;
$function$


-- Function unfollow; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.unfollow(p_target_type text, p_target_id uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    delete from public.follows
    where follower_id = auth.uid()
      and target_type = p_target_type
      and target_id = p_target_id;
$function$


-- Function unfollow_mosaic; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.unfollow_mosaic(p_owner uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    delete from public.follows
    where follower_id = auth.uid()
      and target_owner_id = p_owner;
$function$


-- Function viewer_board_body; SECURITY DEFINER=true; ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.viewer_board_body(p_body jsonb, p_owner uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    filtered jsonb;
    used_text text;
    assets jsonb := '{}'::jsonb;
    file_name text;
    asset jsonb;
begin
    filtered := jsonb_set(
        coalesce(p_body, '{}'::jsonb),
        '{blocks}',
        public.filter_pursuit_blocks(coalesce(p_body->'blocks', '[]'::jsonb), p_owner),
        true
    );
    used_text := (filtered - 'mediaAssets')::text;
    for file_name, asset in
        select key, value from jsonb_each(coalesce(p_body->'mediaAssets', '{}'::jsonb))
    loop
        if position(to_jsonb(file_name)::text in used_text) > 0 then
            assets := assets || jsonb_build_object(file_name, asset);
        end if;
    end loop;
    if assets = '{}'::jsonb then
        return filtered - 'mediaAssets';
    end if;
    return jsonb_set(filtered, '{mediaAssets}', assets, true);
end;
$function$


-- Function viewer_boards; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.viewer_boards(p_owner uuid)
 RETURNS TABLE(id uuid, parent_id uuid, role text, title text, body jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    select doc.id, doc.parent_id, doc.role, doc.title, public.viewer_board_body(doc.body, doc.owner_id)
    from public.documents doc
    where doc.owner_id = p_owner
      and auth.uid() is not null
      and public.viewer_can_read_document(doc.id)
    order by doc.created_at;
$function$


-- Function viewer_can_open_pursuit; SECURITY DEFINER=true; ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.viewer_can_open_pursuit(p_pursuit_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    select exists (
        select 1
        from public.documents pursuit
        where pursuit.id = p_pursuit_id
          and pursuit.role = 'pursuit'
          and auth.uid() is not null
          and (
              pursuit.owner_id = auth.uid()
              or (
                  public.viewer_passes_mosaic_gate(pursuit.owner_id)
                  and (
                      pursuit.visibility = 'public'
                      or (
                          pursuit.visibility = 'private'
                          and exists (
                              select 1
                              from public.pursuit_access_requests request
                              where request.pursuit_id = pursuit.id
                                and request.requester_id = auth.uid()
                                and request.status = 'accepted'
                          )
                      )
                  )
              )
          )
    );
$function$


-- Function viewer_can_read_document; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.viewer_can_read_document(p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    doc public.documents%rowtype;
begin
    if auth.uid() is null then
        return false;
    end if;

    select * into doc from public.documents where id = p_id;
    if not found then
        return false;
    end if;

    if doc.owner_id = auth.uid() then
        return true;
    end if;

    if not public.viewer_passes_mosaic_gate(doc.owner_id) then
        return false;
    end if;

    if doc.role = 'mosaic' then
        return true;
    end if;

    if doc.role = 'pursuit' then
        return public.viewer_can_open_pursuit(doc.id);
    end if;

    if doc.role in ('node', 'page') then
        return public.viewer_can_open_pursuit(public.ancestor_pursuit_id(doc.id));
    end if;

    return false;
end;
$function$


-- Function viewer_can_read_media; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.viewer_can_read_media(p_object_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    folders text[] := storage.foldername(p_object_name);
    owner uuid;
    asset text;
begin
    if auth.uid() is null or array_length(folders, 1) < 2
       or folders[1] !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        return false;
    end if;
    owner := folders[1]::uuid;
    asset := lower(folders[2]);

    return exists (
        select 1
        from public.documents doc
        where doc.owner_id = owner
          and exists (
              select 1 from jsonb_each_text(coalesce(doc.body->'mediaAssets', '{}'::jsonb)) stored
              where lower(stored.value) = asset
          )
          and public.viewer_can_read_document(doc.id)
          and exists (
              select 1
              from jsonb_each_text(coalesce(public.viewer_board_body(doc.body, doc.owner_id)->'mediaAssets', '{}'::jsonb)) shown
              where lower(shown.value) = asset
          )
    );
end;
$function$


-- Function viewer_passes_mosaic_gate; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.viewer_passes_mosaic_gate(p_owner uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    select
        auth.uid() is not null
        and (
            p_owner = auth.uid()
            or exists (
                select 1
                from public.documents mosaic
                where mosaic.owner_id = p_owner
                  and mosaic.role = 'mosaic'
                  and mosaic.visibility = 'public'
            )
            or exists (
                select 1
                from public.mosaic_access_requests request
                where request.owner_id = p_owner
                  and request.requester_id = auth.uid()
                  and request.status = 'accepted'
            )
        );
$function$


-- Function viewer_pursuit_block; SECURITY DEFINER=true; ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.viewer_pursuit_block(p_block jsonb, p_owner uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    pursuit_id text := p_block #>> '{pursuitID,rawValue}';
    level text;
begin
    if pursuit_id is null
       or pursuit_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        return null;
    end if;

    select pursuit.visibility into level
    from public.documents pursuit
    where pursuit.id = pursuit_id::uuid
      and pursuit.owner_id = p_owner
      and pursuit.role = 'pursuit';

    if level is null or level = 'hidden' then
        return null;
    end if;

    if public.viewer_can_open_pursuit(pursuit_id::uuid) then
        return p_block - 'locked';
    end if;

    if level = 'private' then
        return jsonb_set(p_block, '{locked}', 'true'::jsonb, true);
    end if;

    return null;
end;
$function$


-- Function viewer_pursuits; SECURITY DEFINER=true; ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.viewer_pursuits(p_owner uuid)
 RETURNS TABLE(pursuit_id uuid, title text, visibility text, can_open boolean, request_status text, following boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    select doc.id,
           doc.title,
           doc.visibility,
           public.viewer_can_open_pursuit(doc.id),
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
           )
    from public.documents doc
    where doc.owner_id = p_owner
      and doc.role = 'pursuit'
      and doc.visibility <> 'hidden'
      and auth.uid() is not null
      and public.viewer_passes_mosaic_gate(p_owner)
    order by doc.created_at;
$function$


-- Live policies snapshot (JSON comments, not executable SQL):
-- [
--   {
--     "schemaname": "public",
--     "tablename": "activity_events",
--     "policyname": "activity_insert_owner",
--     "roles": "{authenticated}",
--     "cmd": "INSERT",
--     "qual": null,
--     "with_check": "((actor_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1\n   FROM documents doc\n  WHERE ((doc.id = activity_events.document_id) AND (doc.owner_id = ( SELECT auth.uid() AS uid))))))"
--   },
--   {
--     "schemaname": "public",
--     "tablename": "activity_events",
--     "policyname": "activity_select_owner_or_follower",
--     "roles": "{authenticated}",
--     "cmd": "SELECT",
--     "qual": "((actor_id = ( SELECT auth.uid() AS uid)) OR (viewer_can_read_document(document_id) AND (EXISTS ( SELECT 1\n   FROM (follows follow\n     JOIN documents doc ON ((doc.id = activity_events.document_id)))\n  WHERE ((follow.follower_id = ( SELECT auth.uid() AS uid)) AND (((follow.target_type = 'pursuit'::text) AND (follow.target_id = doc.id)) OR ((follow.target_type = 'mosaic'::text) AND (follow.target_owner_id = doc.owner_id) AND (doc.role = ANY (ARRAY['mosaic'::text, 'pursuit'::text])))))))))",
--     "with_check": null
--   },
--   {
--     "schemaname": "public",
--     "tablename": "circle_seen",
--     "policyname": "circle_seen_owner_all",
--     "roles": "{authenticated}",
--     "cmd": "ALL",
--     "qual": "(owner_id = ( SELECT auth.uid() AS uid))",
--     "with_check": "(owner_id = ( SELECT auth.uid() AS uid))"
--   },
--   {
--     "schemaname": "public",
--     "tablename": "documents",
--     "policyname": "documents_owner_all",
--     "roles": "{authenticated}",
--     "cmd": "ALL",
--     "qual": "(owner_id = ( SELECT auth.uid() AS uid))",
--     "with_check": "(owner_id = ( SELECT auth.uid() AS uid))"
--   },
--   {
--     "schemaname": "public",
--     "tablename": "follows",
--     "policyname": "follows_delete_follower",
--     "roles": "{authenticated}",
--     "cmd": "DELETE",
--     "qual": "(follower_id = ( SELECT auth.uid() AS uid))",
--     "with_check": null
--   },
--   {
--     "schemaname": "public",
--     "tablename": "follows",
--     "policyname": "follows_insert_follower",
--     "roles": "{authenticated}",
--     "cmd": "INSERT",
--     "qual": null,
--     "with_check": "((follower_id = ( SELECT auth.uid() AS uid)) AND (((target_type = 'mosaic'::text) AND viewer_passes_mosaic_gate(target_owner_id) AND (EXISTS ( SELECT 1\n   FROM documents mosaic\n  WHERE ((mosaic.id = follows.target_id) AND (mosaic.owner_id = follows.target_owner_id) AND (mosaic.role = 'mosaic'::text))))) OR ((target_type = 'pursuit'::text) AND viewer_can_read_document(target_id) AND (EXISTS ( SELECT 1\n   FROM documents pursuit\n  WHERE ((pursuit.id = follows.target_id) AND (pursuit.owner_id = follows.target_owner_id) AND (pursuit.role = 'pursuit'::text)))))))"
--   },
--   {
--     "schemaname": "public",
--     "tablename": "follows",
--     "policyname": "follows_select_follower",
--     "roles": "{authenticated}",
--     "cmd": "SELECT",
--     "qual": "((follower_id = ( SELECT auth.uid() AS uid)) OR (target_owner_id = ( SELECT auth.uid() AS uid)))",
--     "with_check": null
--   },
--   {
--     "schemaname": "public",
--     "tablename": "media_assets",
--     "policyname": "media_owner_all",
--     "roles": "{authenticated}",
--     "cmd": "ALL",
--     "qual": "(owner_id = ( SELECT auth.uid() AS uid))",
--     "with_check": "(owner_id = ( SELECT auth.uid() AS uid))"
--   },
--   {
--     "schemaname": "public",
--     "tablename": "media_jobs",
--     "policyname": "media_jobs_owner_select",
--     "roles": "{authenticated}",
--     "cmd": "SELECT",
--     "qual": "(EXISTS ( SELECT 1\n   FROM media_assets asset\n  WHERE ((asset.id = media_jobs.asset_id) AND (asset.owner_id = ( SELECT auth.uid() AS uid)))))",
--     "with_check": null
--   },
--   {
--     "schemaname": "public",
--     "tablename": "mosaic_access_requests",
--     "policyname": "access_insert_requester",
--     "roles": "{authenticated}",
--     "cmd": "INSERT",
--     "qual": null,
--     "with_check": "((requester_id = ( SELECT auth.uid() AS uid)) AND (owner_id <> ( SELECT auth.uid() AS uid)) AND (status = 'pending'::text))"
--   },
--   {
--     "schemaname": "public",
--     "tablename": "mosaic_access_requests",
--     "policyname": "access_select_parties",
--     "roles": "{authenticated}",
--     "cmd": "SELECT",
--     "qual": "((owner_id = ( SELECT auth.uid() AS uid)) OR (requester_id = ( SELECT auth.uid() AS uid)))",
--     "with_check": null
--   },
--   {
--     "schemaname": "public",
--     "tablename": "mosaic_access_requests",
--     "policyname": "access_update_owner",
--     "roles": "{authenticated}",
--     "cmd": "UPDATE",
--     "qual": "(owner_id = ( SELECT auth.uid() AS uid))",
--     "with_check": "(owner_id = ( SELECT auth.uid() AS uid))"
--   },
--   {
--     "schemaname": "public",
--     "tablename": "profiles",
--     "policyname": "profiles_select_signed_in",
--     "roles": "{authenticated}",
--     "cmd": "SELECT",
--     "qual": "true",
--     "with_check": null
--   },
--   {
--     "schemaname": "public",
--     "tablename": "profiles",
--     "policyname": "profiles_update_self",
--     "roles": "{authenticated}",
--     "cmd": "UPDATE",
--     "qual": "(id = ( SELECT auth.uid() AS uid))",
--     "with_check": "((id = ( SELECT auth.uid() AS uid)) AND (username ~ '^[a-z0-9_]{3,20}$'::text) AND ((avatar_path IS NULL) OR (split_part(avatar_path, '/'::text, 1) = (( SELECT auth.uid() AS uid))::text)))"
--   },
--   {
--     "schemaname": "public",
--     "tablename": "pursuit_access_requests",
--     "policyname": "pursuit_access_delete_requester",
--     "roles": "{authenticated}",
--     "cmd": "DELETE",
--     "qual": "(requester_id = ( SELECT auth.uid() AS uid))",
--     "with_check": null
--   },
--   {
--     "schemaname": "public",
--     "tablename": "pursuit_access_requests",
--     "policyname": "pursuit_access_insert_requester",
--     "roles": "{authenticated}",
--     "cmd": "INSERT",
--     "qual": null,
--     "with_check": "((requester_id = ( SELECT auth.uid() AS uid)) AND (owner_id <> ( SELECT auth.uid() AS uid)) AND (status = 'pending'::text) AND pursuit_is_requestable(pursuit_id, owner_id))"
--   },
--   {
--     "schemaname": "public",
--     "tablename": "pursuit_access_requests",
--     "policyname": "pursuit_access_select_parties",
--     "roles": "{authenticated}",
--     "cmd": "SELECT",
--     "qual": "((owner_id = ( SELECT auth.uid() AS uid)) OR (requester_id = ( SELECT auth.uid() AS uid)))",
--     "with_check": null
--   },
--   {
--     "schemaname": "public",
--     "tablename": "pursuit_access_requests",
--     "policyname": "pursuit_access_update_owner",
--     "roles": "{authenticated}",
--     "cmd": "UPDATE",
--     "qual": "(owner_id = ( SELECT auth.uid() AS uid))",
--     "with_check": "(owner_id = ( SELECT auth.uid() AS uid))"
--   },
--   {
--     "schemaname": "storage",
--     "tablename": "objects",
--     "policyname": "avatars_owner_delete",
--     "roles": "{authenticated}",
--     "cmd": "DELETE",
--     "qual": "((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))",
--     "with_check": null
--   },
--   {
--     "schemaname": "storage",
--     "tablename": "objects",
--     "policyname": "avatars_owner_insert",
--     "roles": "{authenticated}",
--     "cmd": "INSERT",
--     "qual": null,
--     "with_check": "((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))"
--   },
--   {
--     "schemaname": "storage",
--     "tablename": "objects",
--     "policyname": "avatars_owner_update",
--     "roles": "{authenticated}",
--     "cmd": "UPDATE",
--     "qual": "((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))",
--     "with_check": "((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))"
--   },
--   {
--     "schemaname": "storage",
--     "tablename": "objects",
--     "policyname": "avatars_read_signed_in",
--     "roles": "{authenticated}",
--     "cmd": "SELECT",
--     "qual": "(bucket_id = 'avatars'::text)",
--     "with_check": null
--   },
--   {
--     "schemaname": "storage",
--     "tablename": "objects",
--     "policyname": "media_storage_owner_all",
--     "roles": "{authenticated}",
--     "cmd": "ALL",
--     "qual": "((bucket_id = 'media'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))",
--     "with_check": "((bucket_id = 'media'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))"
--   },
--   {
--     "schemaname": "storage",
--     "tablename": "objects",
--     "policyname": "media_storage_viewer_read",
--     "roles": "{authenticated}",
--     "cmd": "SELECT",
--     "qual": "((bucket_id = 'media'::text) AND viewer_can_read_media(name))",
--     "with_check": null
--   }
-- ]

-- Live integrity snapshot (JSON comments, not executable SQL):
-- [
--   {
--     "table_name": "activity_events",
--     "conname": "activity_events_actor_id_fkey",
--     "definition": "FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE CASCADE"
--   },
--   {
--     "table_name": "activity_events",
--     "conname": "activity_events_document_id_fkey",
--     "definition": "FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE"
--   },
--   {
--     "table_name": "activity_events",
--     "conname": "activity_events_pkey",
--     "definition": "PRIMARY KEY (id)"
--   },
--   {
--     "table_name": "activity_events",
--     "conname": "activity_kind",
--     "definition": "CHECK ((kind = ANY (ARRAY['document_updated'::text, 'media_added'::text])))"
--   },
--   {
--     "table_name": "circle_seen",
--     "conname": "circle_seen_document_id_fkey",
--     "definition": "FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE"
--   },
--   {
--     "table_name": "circle_seen",
--     "conname": "circle_seen_owner_id_fkey",
--     "definition": "FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE CASCADE"
--   },
--   {
--     "table_name": "circle_seen",
--     "conname": "circle_seen_pkey",
--     "definition": "PRIMARY KEY (owner_id, document_id)"
--   },
--   {
--     "table_name": "documents",
--     "conname": "documents_mosaic_levels",
--     "definition": "CHECK (((role <> 'mosaic'::text) OR (visibility = ANY (ARRAY['public'::text, 'private'::text]))))"
--   },
--   {
--     "table_name": "documents",
--     "conname": "documents_owner_id_fkey",
--     "definition": "FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE CASCADE"
--   },
--   {
--     "table_name": "documents",
--     "conname": "documents_parent_id_fkey",
--     "definition": "FOREIGN KEY (parent_id) REFERENCES documents(id) ON DELETE CASCADE"
--   },
--   {
--     "table_name": "documents",
--     "conname": "documents_pkey",
--     "definition": "PRIMARY KEY (id)"
--   },
--   {
--     "table_name": "documents",
--     "conname": "documents_revision_positive",
--     "definition": "CHECK ((revision > 0))"
--   },
--   {
--     "table_name": "documents",
--     "conname": "documents_role",
--     "definition": "CHECK ((role = ANY (ARRAY['mosaic'::text, 'pursuit'::text, 'node'::text, 'page'::text])))"
--   },
--   {
--     "table_name": "documents",
--     "conname": "documents_visibility",
--     "definition": "CHECK ((visibility = ANY (ARRAY['public'::text, 'private'::text, 'hidden'::text])))"
--   },
--   {
--     "table_name": "follows",
--     "conname": "follows_follower_id_fkey",
--     "definition": "FOREIGN KEY (follower_id) REFERENCES profiles(id) ON DELETE CASCADE"
--   },
--   {
--     "table_name": "follows",
--     "conname": "follows_not_self",
--     "definition": "CHECK ((follower_id <> target_owner_id))"
--   },
--   {
--     "table_name": "follows",
--     "conname": "follows_pkey",
--     "definition": "PRIMARY KEY (follower_id, target_type, target_id)"
--   },
--   {
--     "table_name": "follows",
--     "conname": "follows_target_owner_id_fkey",
--     "definition": "FOREIGN KEY (target_owner_id) REFERENCES profiles(id) ON DELETE CASCADE"
--   },
--   {
--     "table_name": "follows",
--     "conname": "follows_target_type",
--     "definition": "CHECK ((target_type = ANY (ARRAY['mosaic'::text, 'pursuit'::text])))"
--   },
--   {
--     "table_name": "media_assets",
--     "conname": "media_assets_document_id_fkey",
--     "definition": "FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE SET NULL"
--   },
--   {
--     "table_name": "media_assets",
--     "conname": "media_assets_owner_id_fkey",
--     "definition": "FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE CASCADE"
--   },
--   {
--     "table_name": "media_assets",
--     "conname": "media_assets_pkey",
--     "definition": "PRIMARY KEY (id)"
--   },
--   {
--     "table_name": "media_assets",
--     "conname": "media_kind",
--     "definition": "CHECK ((kind = ANY (ARRAY['photo'::text, 'video'::text])))"
--   },
--   {
--     "table_name": "media_assets",
--     "conname": "media_status",
--     "definition": "CHECK ((status = ANY (ARRAY['uploading'::text, 'processing'::text, 'ready'::text, 'failed'::text])))"
--   },
--   {
--     "table_name": "media_assets",
--     "conname": "media_video_length",
--     "definition": "CHECK (((duration_ms IS NULL) OR ((duration_ms > 0) AND (duration_ms <= 10000))))"
--   },
--   {
--     "table_name": "media_jobs",
--     "conname": "media_job_status",
--     "definition": "CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'ready'::text, 'failed'::text])))"
--   },
--   {
--     "table_name": "media_jobs",
--     "conname": "media_jobs_asset_id_fkey",
--     "definition": "FOREIGN KEY (asset_id) REFERENCES media_assets(id) ON DELETE CASCADE"
--   },
--   {
--     "table_name": "media_jobs",
--     "conname": "media_jobs_pkey",
--     "definition": "PRIMARY KEY (id)"
--   },
--   {
--     "table_name": "mosaic_access_requests",
--     "conname": "mosaic_access_not_self",
--     "definition": "CHECK ((owner_id <> requester_id))"
--   },
--   {
--     "table_name": "mosaic_access_requests",
--     "conname": "mosaic_access_pair",
--     "definition": "UNIQUE (owner_id, requester_id)"
--   },
--   {
--     "table_name": "mosaic_access_requests",
--     "conname": "mosaic_access_requests_owner_id_fkey",
--     "definition": "FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE CASCADE"
--   },
--   {
--     "table_name": "mosaic_access_requests",
--     "conname": "mosaic_access_requests_pkey",
--     "definition": "PRIMARY KEY (id)"
--   },
--   {
--     "table_name": "mosaic_access_requests",
--     "conname": "mosaic_access_requests_requester_id_fkey",
--     "definition": "FOREIGN KEY (requester_id) REFERENCES profiles(id) ON DELETE CASCADE"
--   },
--   {
--     "table_name": "mosaic_access_requests",
--     "conname": "mosaic_access_status",
--     "definition": "CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'declined'::text, 'revoked'::text])))"
--   },
--   {
--     "table_name": "profiles",
--     "conname": "profiles_id_fkey",
--     "definition": "FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE"
--   },
--   {
--     "table_name": "profiles",
--     "conname": "profiles_pkey",
--     "definition": "PRIMARY KEY (id)"
--   },
--   {
--     "table_name": "profiles",
--     "conname": "profiles_username_key",
--     "definition": "UNIQUE (username)"
--   },
--   {
--     "table_name": "profiles",
--     "conname": "profiles_username_shape",
--     "definition": "CHECK ((username ~ '^[a-z0-9_]{3,20}$'::text))"
--   },
--   {
--     "table_name": "pursuit_access_requests",
--     "conname": "pursuit_access_not_self",
--     "definition": "CHECK ((owner_id <> requester_id))"
--   },
--   {
--     "table_name": "pursuit_access_requests",
--     "conname": "pursuit_access_pair",
--     "definition": "UNIQUE (requester_id, pursuit_id)"
--   },
--   {
--     "table_name": "pursuit_access_requests",
--     "conname": "pursuit_access_requests_owner_id_fkey",
--     "definition": "FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE CASCADE"
--   },
--   {
--     "table_name": "pursuit_access_requests",
--     "conname": "pursuit_access_requests_pkey",
--     "definition": "PRIMARY KEY (id)"
--   },
--   {
--     "table_name": "pursuit_access_requests",
--     "conname": "pursuit_access_requests_pursuit_id_fkey",
--     "definition": "FOREIGN KEY (pursuit_id) REFERENCES documents(id) ON DELETE CASCADE"
--   },
--   {
--     "table_name": "pursuit_access_requests",
--     "conname": "pursuit_access_requests_requester_id_fkey",
--     "definition": "FOREIGN KEY (requester_id) REFERENCES profiles(id) ON DELETE CASCADE"
--   },
--   {
--     "table_name": "pursuit_access_requests",
--     "conname": "pursuit_access_status",
--     "definition": "CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'declined'::text, 'revoked'::text])))"
--   },
--   {
--     "table_name": "visits",
--     "conname": "visits_document_id_fkey",
--     "definition": "FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE"
--   },
--   {
--     "table_name": "visits",
--     "conname": "visits_owner_id_fkey",
--     "definition": "FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE CASCADE"
--   },
--   {
--     "table_name": "visits",
--     "conname": "visits_pkey",
--     "definition": "PRIMARY KEY (id)"
--   },
--   {
--     "table_name": "visits",
--     "conname": "visits_visitor_id_fkey",
--     "definition": "FOREIGN KEY (visitor_id) REFERENCES profiles(id) ON DELETE CASCADE"
--   }
-- ]

-- Live storage snapshot (JSON comments, not executable SQL):
-- [
--   {
--     "id": "media",
--     "public": false,
--     "file_size_limit": null,
--     "allowed_mime_types": null
--   },
--   {
--     "id": "avatars",
--     "public": false,
--     "file_size_limit": 5242880,
--     "allowed_mime_types": [
--       "image/jpeg"
--     ]
--   }
-- ]

-- Live jobs snapshot (JSON comments, not executable SQL):
-- [
--   {
--     "status": "queued",
--     "count": 196,
--     "oldest": "2026-10-12 23:53:02.498213+00"
--   }
-- ]