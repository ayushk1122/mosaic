-- Fixes from the 2026-10-22 review.

-- A save that expects an existing revision but finds no row means another device deleted the
-- board. Saving it as new brought the board back without the other device's deletion ever being
-- shown, and its parent no longer pointed to it, so the next sync removed it and the edits with it.
-- The client now treats this like a deletion it pulled: shown, with its own copy kept as a conflict.
create or replace function public.save_document(p_id uuid, p_parent_id uuid, p_role text, p_title text, p_body jsonb, p_expected_revision bigint)
 returns table(revision bigint)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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

    if p_expected_revision > 0 then
        raise exception 'document deleted' using errcode = 'MS404';
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

-- A shared Mosaic's preview is a picture of its Pursuits as visitors saw them. When one of them
-- changes visibility the picture may show a Pursuit that is now hidden or private, so it is
-- dropped, and the Mosaic stays out of Explore until the owner's phone draws a new one.
create or replace function public.leave_explore_when_not_public()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
    if new.visibility is distinct from 'public' then
        update public.documents
           set explore_shared = false,
               explore_shared_at = null,
               explore_preview = null,
               explore_preview_at = null
         where explore_shared
           and (id = new.id or (new.role = 'mosaic' and owner_id = new.owner_id));
    end if;
    if new.role = 'pursuit' then
        update public.documents
           set explore_preview = null,
               explore_preview_at = null
         where owner_id = new.owner_id
           and role = 'mosaic'
           and explore_shared
           and explore_preview is not null;
    end if;
    return null;
end;
$function$;

-- Only the preview image itself is readable through a board's Explore sharing, never other files
-- that happen to sit in the same folder.
create or replace function public.viewer_can_read_media(p_object_name text)
 returns boolean
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
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

    if storage.filename(p_object_name) = 'display' and exists (
        select 1
        from public.documents doc
        where doc.owner_id = owner
          and doc.explore_shared
          and lower(doc.explore_preview::text) = asset
          and public.explore_eligible(doc.id)
    ) then
        return true;
    end if;

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

-- Reads today's date, so it isn't immutable; and like every function here, a fixed search path.
alter function public.validate_birthday(date) stable;
alter function public.validate_birthday(date) set search_path = public;
