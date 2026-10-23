-- More ways to browse Explore: newest to Explore, recently updated, and trending (most new
-- followers in the last week), and leaving out boards the caller already follows.
drop function if exists public.explore_feed(text, text, integer, integer, text, text);

create or replace function public.explore_feed(
    p_kind text default 'all',
    p_seed text default '',
    p_offset integer default 0,
    p_limit integer default 30,
    p_query text default '',
    p_sort text default 'shuffle',
    p_hide_followed boolean default false
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
    mosaic_id uuid,
    follower_count bigint
 )
 language sql
 stable security definer
 set search_path to 'public'
as $function$
    with wanted as (
        select lower(left(btrim(coalesce(p_query, '')), 60)) as text
    ),
    shared as (
        select doc.id,
               doc.role,
               doc.title,
               doc.owner_id,
               person.username,
               person.display_name,
               person.avatar_path,
               doc.owner_id::text || '/' || doc.explore_preview::text || '/display' as preview_path,
               mosaic.id as mosaic_id,
               (select count(*) from public.follows follow
                 where follow.target_id = doc.id and follow.target_type = doc.role) as follower_count,
               (select count(*) from public.follows follow
                 where follow.target_id = doc.id and follow.target_type = doc.role
                   and follow.created_at > now() - interval '7 days') as recent_followers,
               doc.explore_shared_at,
               doc.updated_at,
               md5(doc.id::text || coalesce(p_seed, '')) as shuffle
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
          and not (
              coalesce(p_hide_followed, false)
              and exists (
                  select 1 from public.follows mine
                  where mine.follower_id = auth.uid() and mine.target_id = doc.id
              )
          )
    )
    select id, role, title, owner_id, username, display_name, avatar_path, preview_path, mosaic_id, follower_count
    from shared
    order by
        case when p_sort = 'popular' then follower_count end desc nulls last,
        case when p_sort = 'least_popular' then follower_count end asc nulls last,
        case when p_sort = 'trending' then recent_followers end desc nulls last,
        case when p_sort = 'trending' then follower_count end desc nulls last,
        case when p_sort = 'newest' then explore_shared_at end desc nulls last,
        case when p_sort = 'updated' then updated_at end desc nulls last,
        shuffle,
        id
    limit least(greatest(coalesce(p_limit, 30), 1), 60)
    offset greatest(coalesce(p_offset, 0), 0);
$function$;

revoke all on function public.explore_feed(text, text, integer, integer, text, text, boolean) from public, anon;
grant execute on function public.explore_feed(text, text, integer, integer, text, text, boolean) to authenticated;
