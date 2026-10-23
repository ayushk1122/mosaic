-- Explore search: the feed takes an optional query matched, ignoring case, against the board's
-- title and its owner's display name and username. Matched as plain text, so % and _ mean
-- themselves. Everything else about the feed (sharing, eligibility, never the caller's own) holds.
drop function if exists public.explore_feed(text, text, integer, integer);

create or replace function public.explore_feed(
    p_kind text default 'all',
    p_seed text default '',
    p_offset integer default 0,
    p_limit integer default 30,
    p_query text default ''
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
    with wanted as (
        select lower(left(btrim(coalesce(p_query, '')), 60)) as text
    )
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
    cross join wanted
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
      and (
          wanted.text = ''
          or strpos(lower(doc.title), wanted.text) > 0
          or strpos(lower(coalesce(person.display_name, '')), wanted.text) > 0
          or strpos(lower(person.username), wanted.text) > 0
      )
    order by md5(doc.id::text || coalesce(p_seed, '')), doc.id
    limit least(greatest(coalesce(p_limit, 30), 1), 60)
    offset greatest(coalesce(p_offset, 0), 0);
$function$;

revoke all on function public.explore_feed(text, text, integer, integer, text) from public, anon;
grant execute on function public.explore_feed(text, text, integer, integer, text) to authenticated;
