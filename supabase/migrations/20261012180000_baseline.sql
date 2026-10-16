-- Mosaic schema baseline captured from Mosaic-dev on 2026-10-16.
-- Squashes earlier unversioned live migrations into one replayable migration.
-- Includes save_document role-move behavior and missing FK indexes from the beta-readiness review.

-- Tables
CREATE TABLE public.profiles (
  id uuid NOT NULL,
  username text NOT NULL,
  display_name text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  avatar_path text
);
CREATE TABLE public.documents (
  id uuid NOT NULL,
  owner_id uuid NOT NULL,
  parent_id uuid,
  role text NOT NULL,
  title text NOT NULL DEFAULT ''::text,
  visibility text NOT NULL DEFAULT 'hidden'::text,
  body jsonb NOT NULL DEFAULT '{"blocks": []}'::jsonb,
  revision bigint NOT NULL DEFAULT 1,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);
CREATE TABLE public.activity_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  actor_id uuid NOT NULL,
  document_id uuid NOT NULL,
  kind text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);
CREATE TABLE public.circle_seen (
  owner_id uuid NOT NULL,
  document_id uuid NOT NULL,
  seen_at timestamp with time zone NOT NULL DEFAULT now()
);
CREATE TABLE public.follows (
  follower_id uuid NOT NULL,
  target_owner_id uuid NOT NULL,
  target_type text NOT NULL,
  target_id uuid NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);
CREATE TABLE public.media_assets (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL,
  document_id uuid,
  kind text NOT NULL,
  status text NOT NULL DEFAULT 'uploading'::text,
  original_path text,
  display_path text,
  thumb_path text,
  width integer,
  height integer,
  duration_ms integer,
  byte_size bigint,
  content_type text,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);
CREATE TABLE public.media_jobs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  asset_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'queued'::text,
  error text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);
CREATE TABLE public.mosaic_access_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL,
  requester_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'pending'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  responded_at timestamp with time zone
);
CREATE TABLE public.pursuit_access_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL,
  requester_id uuid NOT NULL,
  pursuit_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'pending'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  responded_at timestamp with time zone
);
CREATE TABLE public.visits (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  document_id uuid NOT NULL,
  owner_id uuid NOT NULL,
  visitor_id uuid NOT NULL,
  visited_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Primary / unique keys
ALTER TABLE public.profiles ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);
ALTER TABLE public.profiles ADD CONSTRAINT profiles_username_key UNIQUE (username);
ALTER TABLE public.documents ADD CONSTRAINT documents_pkey PRIMARY KEY (id);
ALTER TABLE public.activity_events ADD CONSTRAINT activity_events_pkey PRIMARY KEY (id);
ALTER TABLE public.circle_seen ADD CONSTRAINT circle_seen_pkey PRIMARY KEY (owner_id, document_id);
ALTER TABLE public.follows ADD CONSTRAINT follows_pkey PRIMARY KEY (follower_id, target_type, target_id);
ALTER TABLE public.media_assets ADD CONSTRAINT media_assets_pkey PRIMARY KEY (id);
ALTER TABLE public.media_jobs ADD CONSTRAINT media_jobs_pkey PRIMARY KEY (id);
ALTER TABLE public.mosaic_access_requests ADD CONSTRAINT mosaic_access_requests_pkey PRIMARY KEY (id);
ALTER TABLE public.mosaic_access_requests ADD CONSTRAINT mosaic_access_pair UNIQUE (owner_id, requester_id);
ALTER TABLE public.pursuit_access_requests ADD CONSTRAINT pursuit_access_requests_pkey PRIMARY KEY (id);
ALTER TABLE public.pursuit_access_requests ADD CONSTRAINT pursuit_access_pair UNIQUE (requester_id, pursuit_id);

-- Check constraints
ALTER TABLE public.profiles ADD CONSTRAINT profiles_username_shape CHECK ((username ~ '^[a-z0-9_]{3,20}$'::text));
ALTER TABLE public.documents ADD CONSTRAINT documents_mosaic_levels CHECK (((role <> 'mosaic'::text) OR (visibility = ANY (ARRAY['public'::text, 'private'::text]))));
ALTER TABLE public.documents ADD CONSTRAINT documents_revision_positive CHECK ((revision > 0));
ALTER TABLE public.documents ADD CONSTRAINT documents_role CHECK ((role = ANY (ARRAY['mosaic'::text, 'pursuit'::text, 'node'::text, 'page'::text])));
ALTER TABLE public.documents ADD CONSTRAINT documents_visibility CHECK ((visibility = ANY (ARRAY['public'::text, 'private'::text, 'hidden'::text])));
ALTER TABLE public.activity_events ADD CONSTRAINT activity_kind CHECK ((kind = ANY (ARRAY['document_updated'::text, 'media_added'::text])));
ALTER TABLE public.follows ADD CONSTRAINT follows_not_self CHECK ((follower_id <> target_owner_id));
ALTER TABLE public.follows ADD CONSTRAINT follows_target_type CHECK ((target_type = ANY (ARRAY['mosaic'::text, 'pursuit'::text])));
ALTER TABLE public.media_assets ADD CONSTRAINT media_kind CHECK ((kind = ANY (ARRAY['photo'::text, 'video'::text])));
ALTER TABLE public.media_assets ADD CONSTRAINT media_status CHECK ((status = ANY (ARRAY['uploading'::text, 'processing'::text, 'ready'::text, 'failed'::text])));
ALTER TABLE public.media_assets ADD CONSTRAINT media_video_length CHECK (((duration_ms IS NULL) OR ((duration_ms > 0) AND (duration_ms <= 10000))));
ALTER TABLE public.media_jobs ADD CONSTRAINT media_job_status CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'ready'::text, 'failed'::text])));
ALTER TABLE public.mosaic_access_requests ADD CONSTRAINT mosaic_access_not_self CHECK ((owner_id <> requester_id));
ALTER TABLE public.mosaic_access_requests ADD CONSTRAINT mosaic_access_status CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'declined'::text, 'revoked'::text])));
ALTER TABLE public.pursuit_access_requests ADD CONSTRAINT pursuit_access_not_self CHECK ((owner_id <> requester_id));
ALTER TABLE public.pursuit_access_requests ADD CONSTRAINT pursuit_access_status CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'declined'::text, 'revoked'::text])));

-- Foreign keys
ALTER TABLE public.profiles ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.documents ADD CONSTRAINT documents_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.documents ADD CONSTRAINT documents_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.documents(id) ON DELETE CASCADE;
ALTER TABLE public.activity_events ADD CONSTRAINT activity_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.activity_events ADD CONSTRAINT activity_events_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.documents(id) ON DELETE CASCADE;
ALTER TABLE public.circle_seen ADD CONSTRAINT circle_seen_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.documents(id) ON DELETE CASCADE;
ALTER TABLE public.circle_seen ADD CONSTRAINT circle_seen_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.follows ADD CONSTRAINT follows_follower_id_fkey FOREIGN KEY (follower_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.follows ADD CONSTRAINT follows_target_owner_id_fkey FOREIGN KEY (target_owner_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.media_assets ADD CONSTRAINT media_assets_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.documents(id) ON DELETE SET NULL;
ALTER TABLE public.media_assets ADD CONSTRAINT media_assets_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.media_jobs ADD CONSTRAINT media_jobs_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES public.media_assets(id) ON DELETE CASCADE;
ALTER TABLE public.mosaic_access_requests ADD CONSTRAINT mosaic_access_requests_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.mosaic_access_requests ADD CONSTRAINT mosaic_access_requests_requester_id_fkey FOREIGN KEY (requester_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.pursuit_access_requests ADD CONSTRAINT pursuit_access_requests_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.pursuit_access_requests ADD CONSTRAINT pursuit_access_requests_pursuit_id_fkey FOREIGN KEY (pursuit_id) REFERENCES public.documents(id) ON DELETE CASCADE;
ALTER TABLE public.pursuit_access_requests ADD CONSTRAINT pursuit_access_requests_requester_id_fkey FOREIGN KEY (requester_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.visits ADD CONSTRAINT visits_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.documents(id) ON DELETE CASCADE;
ALTER TABLE public.visits ADD CONSTRAINT visits_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.visits ADD CONSTRAINT visits_visitor_id_fkey FOREIGN KEY (visitor_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Indexes
CREATE INDEX activity_events_actor_time ON public.activity_events USING btree (actor_id, created_at DESC);
CREATE INDEX activity_events_document_time ON public.activity_events USING btree (document_id, created_at DESC);
CREATE UNIQUE INDEX documents_one_mosaic_per_owner ON public.documents USING btree (owner_id) WHERE (role = 'mosaic'::text);
CREATE INDEX documents_owner_role ON public.documents USING btree (owner_id, role);
CREATE INDEX documents_parent ON public.documents USING btree (parent_id);
CREATE INDEX follows_target ON public.follows USING btree (target_type, target_id);
CREATE INDEX media_assets_document ON public.media_assets USING btree (document_id);
CREATE INDEX media_assets_owner ON public.media_assets USING btree (owner_id);
CREATE INDEX media_jobs_asset ON public.media_jobs USING btree (asset_id, status);
CREATE INDEX mosaic_access_owner_status ON public.mosaic_access_requests USING btree (owner_id, status);
CREATE INDEX profiles_username_prefix ON public.profiles USING btree (username);
CREATE INDEX pursuit_access_owner_status ON public.pursuit_access_requests USING btree (owner_id, status);
CREATE INDEX pursuit_access_pursuit_status ON public.pursuit_access_requests USING btree (pursuit_id, status);
CREATE INDEX visits_document ON public.visits USING btree (document_id);
CREATE INDEX visits_owner_visited_at ON public.visits USING btree (owner_id, visited_at);
CREATE INDEX visits_visited_at ON public.visits USING btree (visited_at);
CREATE INDEX visits_visitor_document_visited_at ON public.visits USING btree (visitor_id, document_id, visited_at DESC);
CREATE INDEX circle_seen_document_id_idx ON public.circle_seen USING btree (document_id);
CREATE INDEX follows_target_owner_id_idx ON public.follows USING btree (target_owner_id);
CREATE INDEX mosaic_access_requests_requester_id_idx ON public.mosaic_access_requests USING btree (requester_id);

-- Functions
CREATE OR REPLACE FUNCTION public.touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
    new.updated_at = now();
    return new;
end;
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

CREATE OR REPLACE FUNCTION public.unfollow_mosaic(p_owner uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    delete from public.follows
    where follower_id = auth.uid()
      and target_owner_id = p_owner;
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;

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
$function$;


-- Triggers
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
CREATE TRIGGER follows_revoke_pursuit_access AFTER DELETE ON public.follows FOR EACH ROW EXECUTE FUNCTION public.revoke_pursuit_access_on_unfollow();
CREATE TRIGGER media_assets_enqueue_job AFTER INSERT ON public.media_assets FOR EACH ROW EXECUTE FUNCTION public.enqueue_media_job();
CREATE TRIGGER profiles_touch_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Row level security
ALTER TABLE public.activity_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_seen ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.media_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.media_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mosaic_access_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pursuit_access_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visits ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY activity_insert_owner ON public.activity_events AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((actor_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM documents doc
  WHERE ((doc.id = activity_events.document_id) AND (doc.owner_id = ( SELECT auth.uid() AS uid)))))));
CREATE POLICY activity_select_owner_or_follower ON public.activity_events AS PERMISSIVE FOR SELECT TO authenticated USING (((actor_id = ( SELECT auth.uid() AS uid)) OR (viewer_can_read_document(document_id) AND (EXISTS ( SELECT 1
   FROM (follows follow
     JOIN documents doc ON ((doc.id = activity_events.document_id)))
  WHERE ((follow.follower_id = ( SELECT auth.uid() AS uid)) AND (((follow.target_type = 'pursuit'::text) AND (follow.target_id = doc.id)) OR ((follow.target_type = 'mosaic'::text) AND (follow.target_owner_id = doc.owner_id) AND (doc.role = ANY (ARRAY['mosaic'::text, 'pursuit'::text]))))))))));
CREATE POLICY circle_seen_owner_all ON public.circle_seen AS PERMISSIVE FOR ALL TO authenticated USING ((owner_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((owner_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY documents_owner_all ON public.documents AS PERMISSIVE FOR ALL TO authenticated USING ((owner_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((owner_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY follows_delete_follower ON public.follows AS PERMISSIVE FOR DELETE TO authenticated USING ((follower_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY follows_insert_follower ON public.follows AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((follower_id = ( SELECT auth.uid() AS uid)) AND (((target_type = 'mosaic'::text) AND viewer_passes_mosaic_gate(target_owner_id) AND (EXISTS ( SELECT 1
   FROM documents mosaic
  WHERE ((mosaic.id = follows.target_id) AND (mosaic.owner_id = follows.target_owner_id) AND (mosaic.role = 'mosaic'::text))))) OR ((target_type = 'pursuit'::text) AND viewer_can_read_document(target_id) AND (EXISTS ( SELECT 1
   FROM documents pursuit
  WHERE ((pursuit.id = follows.target_id) AND (pursuit.owner_id = follows.target_owner_id) AND (pursuit.role = 'pursuit'::text))))))));
CREATE POLICY follows_select_follower ON public.follows AS PERMISSIVE FOR SELECT TO authenticated USING (((follower_id = ( SELECT auth.uid() AS uid)) OR (target_owner_id = ( SELECT auth.uid() AS uid))));
CREATE POLICY media_owner_all ON public.media_assets AS PERMISSIVE FOR ALL TO authenticated USING ((owner_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((owner_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY media_jobs_owner_select ON public.media_jobs AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM media_assets asset
  WHERE ((asset.id = media_jobs.asset_id) AND (asset.owner_id = ( SELECT auth.uid() AS uid))))));
CREATE POLICY access_insert_requester ON public.mosaic_access_requests AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((requester_id = ( SELECT auth.uid() AS uid)) AND (owner_id <> ( SELECT auth.uid() AS uid)) AND (status = 'pending'::text)));
CREATE POLICY access_select_parties ON public.mosaic_access_requests AS PERMISSIVE FOR SELECT TO authenticated USING (((owner_id = ( SELECT auth.uid() AS uid)) OR (requester_id = ( SELECT auth.uid() AS uid))));
CREATE POLICY access_update_owner ON public.mosaic_access_requests AS PERMISSIVE FOR UPDATE TO authenticated USING ((owner_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((owner_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY profiles_select_signed_in ON public.profiles AS PERMISSIVE FOR SELECT TO authenticated USING (true);
CREATE POLICY profiles_update_self ON public.profiles AS PERMISSIVE FOR UPDATE TO authenticated USING ((id = ( SELECT auth.uid() AS uid))) WITH CHECK (((id = ( SELECT auth.uid() AS uid)) AND (username ~ '^[a-z0-9_]{3,20}$'::text) AND ((avatar_path IS NULL) OR (split_part(avatar_path, '/'::text, 1) = (( SELECT auth.uid() AS uid))::text))));
CREATE POLICY pursuit_access_delete_requester ON public.pursuit_access_requests AS PERMISSIVE FOR DELETE TO authenticated USING ((requester_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY pursuit_access_insert_requester ON public.pursuit_access_requests AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((requester_id = ( SELECT auth.uid() AS uid)) AND (owner_id <> ( SELECT auth.uid() AS uid)) AND (status = 'pending'::text) AND pursuit_is_requestable(pursuit_id, owner_id)));
CREATE POLICY pursuit_access_select_parties ON public.pursuit_access_requests AS PERMISSIVE FOR SELECT TO authenticated USING (((owner_id = ( SELECT auth.uid() AS uid)) OR (requester_id = ( SELECT auth.uid() AS uid))));
CREATE POLICY pursuit_access_update_owner ON public.pursuit_access_requests AS PERMISSIVE FOR UPDATE TO authenticated USING ((owner_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((owner_id = ( SELECT auth.uid() AS uid)));


-- Storage
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('avatars', 'avatars', false, 5242880, ARRAY['image/jpeg']::text[])
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public, file_size_limit = EXCLUDED.file_size_limit, allowed_mime_types = EXCLUDED.allowed_mime_types;
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('media', 'media', false, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public, file_size_limit = EXCLUDED.file_size_limit, allowed_mime_types = EXCLUDED.allowed_mime_types;
DROP POLICY IF EXISTS avatars_owner_delete ON storage.objects;
DROP POLICY IF EXISTS avatars_owner_insert ON storage.objects;
DROP POLICY IF EXISTS avatars_owner_update ON storage.objects;
DROP POLICY IF EXISTS avatars_read_signed_in ON storage.objects;
DROP POLICY IF EXISTS media_storage_owner_all ON storage.objects;
DROP POLICY IF EXISTS media_storage_viewer_read ON storage.objects;
CREATE POLICY avatars_owner_delete ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated USING (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY avatars_owner_insert ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY avatars_owner_update ON storage.objects AS PERMISSIVE FOR UPDATE TO authenticated USING (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))) WITH CHECK (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY avatars_read_signed_in ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated USING ((bucket_id = 'avatars'::text));
CREATE POLICY media_storage_owner_all ON storage.objects AS PERMISSIVE FOR ALL TO authenticated USING (((bucket_id = 'media'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))) WITH CHECK (((bucket_id = 'media'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY media_storage_viewer_read ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated USING (((bucket_id = 'media'::text) AND public.viewer_can_read_media(name)));

-- Grants
GRANT ALL ON TABLE public.activity_events TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.circle_seen TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.documents TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.follows TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.media_assets TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.media_jobs TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.mosaic_access_requests TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.profiles TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.pursuit_access_requests TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.visits TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.touch_updated_at() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.touch_updated_at() FROM anon;
GRANT EXECUTE ON FUNCTION public.touch_updated_at() TO service_role;
REVOKE ALL ON FUNCTION public.enqueue_media_job() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.enqueue_media_job() FROM anon;
GRANT EXECUTE ON FUNCTION public.enqueue_media_job() TO service_role;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM anon;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO service_role;
REVOKE ALL ON FUNCTION public.revoke_pursuit_access_on_unfollow() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.revoke_pursuit_access_on_unfollow() FROM anon;
GRANT EXECUTE ON FUNCTION public.revoke_pursuit_access_on_unfollow() TO service_role;
REVOKE ALL ON FUNCTION public.board_pursuit_widgets(p_body jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.board_pursuit_widgets(p_body jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.board_pursuit_widgets(p_body jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.ancestor_pursuit_id(p_id uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ancestor_pursuit_id(p_id uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.ancestor_pursuit_id(p_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public.ancestor_pursuit_is_public(p_id uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ancestor_pursuit_is_public(p_id uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.ancestor_pursuit_is_public(p_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public.viewer_passes_mosaic_gate(p_owner uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.viewer_passes_mosaic_gate(p_owner uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.viewer_passes_mosaic_gate(p_owner uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.viewer_passes_mosaic_gate(p_owner uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.viewer_can_open_pursuit(p_pursuit_id uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.viewer_can_open_pursuit(p_pursuit_id uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.viewer_can_open_pursuit(p_pursuit_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public.viewer_can_read_document(p_id uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.viewer_can_read_document(p_id uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.viewer_can_read_document(p_id uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.viewer_can_read_document(p_id uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.viewer_pursuit_block(p_block jsonb, p_owner uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.viewer_pursuit_block(p_block jsonb, p_owner uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.viewer_pursuit_block(p_block jsonb, p_owner uuid) TO service_role;
REVOKE ALL ON FUNCTION public.filter_pursuit_blocks(p_blocks jsonb, p_owner uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.filter_pursuit_blocks(p_blocks jsonb, p_owner uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.filter_pursuit_blocks(p_blocks jsonb, p_owner uuid) TO service_role;
REVOKE ALL ON FUNCTION public.viewer_board_body(p_body jsonb, p_owner uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.viewer_board_body(p_body jsonb, p_owner uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.viewer_board_body(p_body jsonb, p_owner uuid) TO service_role;
REVOKE ALL ON FUNCTION public.viewer_can_read_media(p_object_name text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.viewer_can_read_media(p_object_name text) FROM anon;
GRANT EXECUTE ON FUNCTION public.viewer_can_read_media(p_object_name text) TO service_role;
GRANT EXECUTE ON FUNCTION public.viewer_can_read_media(p_object_name text) TO authenticated;
REVOKE ALL ON FUNCTION public.pursuit_is_requestable(p_pursuit_id uuid, p_owner uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pursuit_is_requestable(p_pursuit_id uuid, p_owner uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.pursuit_is_requestable(p_pursuit_id uuid, p_owner uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.pursuit_is_requestable(p_pursuit_id uuid, p_owner uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.own_mosaic_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.own_mosaic_id() FROM anon;
GRANT EXECUTE ON FUNCTION public.own_mosaic_id() TO service_role;
GRANT EXECUTE ON FUNCTION public.own_mosaic_id() TO authenticated;
REVOKE ALL ON FUNCTION public.save_document(p_id uuid, p_parent_id uuid, p_role text, p_title text, p_body jsonb, p_expected_revision bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.save_document(p_id uuid, p_parent_id uuid, p_role text, p_title text, p_body jsonb, p_expected_revision bigint) FROM anon;
GRANT EXECUTE ON FUNCTION public.save_document(p_id uuid, p_parent_id uuid, p_role text, p_title text, p_body jsonb, p_expected_revision bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.save_document(p_id uuid, p_parent_id uuid, p_role text, p_title text, p_body jsonb, p_expected_revision bigint) TO authenticated;
REVOKE ALL ON FUNCTION public.set_document_visibility(p_id uuid, p_visibility text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_document_visibility(p_id uuid, p_visibility text) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_document_visibility(p_id uuid, p_visibility text) TO service_role;
GRANT EXECUTE ON FUNCTION public.set_document_visibility(p_id uuid, p_visibility text) TO authenticated;
REVOKE ALL ON FUNCTION public.read_document(p_id uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.read_document(p_id uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.read_document(p_id uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.read_document(p_id uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.request_mosaic_access(p_owner uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.request_mosaic_access(p_owner uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.request_mosaic_access(p_owner uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.request_mosaic_access(p_owner uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.request_pursuit_access(p_pursuit_id uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.request_pursuit_access(p_pursuit_id uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.request_pursuit_access(p_pursuit_id uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.request_pursuit_access(p_pursuit_id uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.respond_to_request(p_request_id uuid, p_accept boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.respond_to_request(p_request_id uuid, p_accept boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.respond_to_request(p_request_id uuid, p_accept boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.respond_to_request(p_request_id uuid, p_accept boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.follow_mosaic(p_owner uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.follow_mosaic(p_owner uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.follow_mosaic(p_owner uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.follow_mosaic(p_owner uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.follow_pursuit(p_pursuit_id uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.follow_pursuit(p_pursuit_id uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.follow_pursuit(p_pursuit_id uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.follow_pursuit(p_pursuit_id uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.unfollow(p_target_type text, p_target_id uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.unfollow(p_target_type text, p_target_id uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.unfollow(p_target_type text, p_target_id uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.unfollow(p_target_type text, p_target_id uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.unfollow_mosaic(p_owner uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.unfollow_mosaic(p_owner uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.unfollow_mosaic(p_owner uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.unfollow_mosaic(p_owner uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.remove_follower(p_document_id uuid, p_follower_id uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.remove_follower(p_document_id uuid, p_follower_id uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.remove_follower(p_document_id uuid, p_follower_id uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.remove_follower(p_document_id uuid, p_follower_id uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.mark_circle_seen(p_document_id uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_circle_seen(p_document_id uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.mark_circle_seen(p_document_id uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_circle_seen(p_document_id uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.circle_counts() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.circle_counts() FROM anon;
GRANT EXECUTE ON FUNCTION public.circle_counts() TO service_role;
REVOKE ALL ON FUNCTION public.circle_overview() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.circle_overview() FROM anon;
GRANT EXECUTE ON FUNCTION public.circle_overview() TO service_role;
GRANT EXECUTE ON FUNCTION public.circle_overview() TO authenticated;
REVOKE ALL ON FUNCTION public.circle_people(p_document_id uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.circle_people(p_document_id uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.circle_people(p_document_id uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.circle_people(p_document_id uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.circle_visits(p_time_zone text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.circle_visits(p_time_zone text) FROM anon;
GRANT EXECUTE ON FUNCTION public.circle_visits(p_time_zone text) TO service_role;
GRANT EXECUTE ON FUNCTION public.circle_visits(p_time_zone text) TO authenticated;
REVOKE ALL ON FUNCTION public.profile_view(p_user_id uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.profile_view(p_user_id uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.profile_view(p_user_id uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.profile_view(p_user_id uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.search_profiles(p_query text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.search_profiles(p_query text) FROM anon;
GRANT EXECUTE ON FUNCTION public.search_profiles(p_query text) TO service_role;
GRANT EXECUTE ON FUNCTION public.search_profiles(p_query text) TO authenticated;
REVOKE ALL ON FUNCTION public.my_follows() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.my_follows() FROM anon;
GRANT EXECUTE ON FUNCTION public.my_follows() TO service_role;
GRANT EXECUTE ON FUNCTION public.my_follows() TO authenticated;
REVOKE ALL ON FUNCTION public.viewer_boards(p_owner uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.viewer_boards(p_owner uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.viewer_boards(p_owner uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.viewer_boards(p_owner uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.viewer_pursuits(p_owner uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.viewer_pursuits(p_owner uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.viewer_pursuits(p_owner uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.viewer_pursuits(p_owner uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.record_visit(p_document_id uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_visit(p_document_id uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.record_visit(p_document_id uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_visit(p_document_id uuid) TO authenticated;
