-- Explore: owners can share a public Mosaic, or a public Pursuit on a public Mosaic, to a feed
-- other signed-in people browse. Sharing is opt-in and separate from being public. Each shared
-- board carries a preview image its owner's device renders as visitors see the board; the feed
-- only lists shared boards with a preview, and never the caller's own.

alter table public.documents
    add column explore_shared boolean not null default false,
    add column explore_shared_at timestamptz,
    add column explore_preview uuid,
    add column explore_preview_at timestamptz;

create index documents_explore_shared_idx on public.documents (role) where explore_shared;

-- What visitors could actually open: a public Mosaic, or a public Pursuit whose Mosaic is public
-- (a private Mosaic keeps strangers out of its Pursuits).
create or replace function public.explore_eligible(p_id uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    select exists (
        select 1
        from public.documents doc
        join public.documents mosaic
          on mosaic.owner_id = doc.owner_id and mosaic.role = 'mosaic'
        where doc.id = p_id
          and doc.role in ('mosaic', 'pursuit')
          and doc.visibility = 'public'
          and mosaic.visibility = 'public'
    );
$function$;

create or replace function public.set_explore_sharing(p_id uuid, p_shared boolean)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
    if auth.uid() is null then
        raise exception 'sign in required' using errcode = '28000';
    end if;
    if not exists (select 1 from public.documents where id = p_id and owner_id = auth.uid()) then
        raise exception 'not your board' using errcode = '42501';
    end if;
    if p_shared and not public.explore_eligible(p_id) then
        raise exception 'only public boards on a public Mosaic can be shared to Explore' using errcode = '22023';
    end if;
    update public.documents
       set explore_shared = p_shared,
           explore_shared_at = case when p_shared then coalesce(explore_shared_at, now()) else null end,
           explore_preview = case when p_shared then explore_preview else null end,
           explore_preview_at = case when p_shared then explore_preview_at else null end
     where id = p_id and owner_id = auth.uid();
end;
$function$;

-- The preview is an image the owner uploaded to their own media folder as {asset}/display.
create or replace function public.set_explore_preview(p_id uuid, p_asset uuid)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
    if auth.uid() is null then
        raise exception 'sign in required' using errcode = '28000';
    end if;
    update public.documents
       set explore_preview = p_asset,
           explore_preview_at = now()
     where id = p_id and owner_id = auth.uid() and explore_shared;
    if not found then
        raise exception 'board is not shared to Explore' using errcode = '42501';
    end if;
end;
$function$;

-- Pages of shared boards in an order shuffled by p_seed: the same seed pages without repeats,
-- a new seed reshuffles. p_kind is 'all', 'mosaics', or 'pursuits'.
create or replace function public.explore_feed(
    p_kind text default 'all',
    p_seed text default '',
    p_offset integer default 0,
    p_limit integer default 30
)
 returns table(
    document_id uuid,
    role text,
    title text,
    owner_id uuid,
    username text,
    display_name text,
    avatar_path text,
    preview_path text,
    mosaic_id uuid
 )
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    select doc.id,
           doc.role,
           doc.title,
           doc.owner_id,
           person.username,
           person.display_name,
           person.avatar_path,
           doc.owner_id::text || '/' || doc.explore_preview::text || '/display',
           mosaic.id
    from public.documents doc
    join public.profiles person on person.id = doc.owner_id
    join public.documents mosaic on mosaic.owner_id = doc.owner_id and mosaic.role = 'mosaic'
    where auth.uid() is not null
      and doc.owner_id <> auth.uid()
      and doc.explore_shared
      and doc.explore_preview is not null
      and doc.role in ('mosaic', 'pursuit')
      and doc.visibility = 'public'
      and mosaic.visibility = 'public'
      and (
          coalesce(p_kind, 'all') = 'all'
          or (p_kind = 'mosaics' and doc.role = 'mosaic')
          or (p_kind = 'pursuits' and doc.role = 'pursuit')
      )
    order by md5(doc.id::text || coalesce(p_seed, '')), doc.id
    limit least(greatest(coalesce(p_limit, 30), 1), 60)
    offset greatest(coalesce(p_offset, 0), 0);
$function$;

-- A board that stops being public leaves Explore, and a Mosaic that does takes every shared board
-- of its owner with it. Making it public again asks again.
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
    return null;
end;
$function$;

create trigger documents_leave_explore
    after update of visibility on public.documents
    for each row
    when (old.visibility is distinct from new.visibility)
    execute function public.leave_explore_when_not_public();

-- Previews of shared boards are readable by anyone signed in; everything else as before.
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

    if exists (
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

revoke all on function public.explore_eligible(uuid) from public, anon, authenticated;
revoke all on function public.leave_explore_when_not_public() from public, anon, authenticated;
revoke all on function public.set_explore_sharing(uuid, boolean) from public, anon;
revoke all on function public.set_explore_preview(uuid, uuid) from public, anon;
revoke all on function public.explore_feed(text, text, integer, integer) from public, anon;
grant execute on function public.set_explore_sharing(uuid, boolean) to authenticated;
grant execute on function public.set_explore_preview(uuid, uuid) to authenticated;
grant execute on function public.explore_feed(text, text, integer, integer) to authenticated;
