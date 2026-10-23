-- Data API grants are explicit. From 2026-10-30 Supabase no longer grants new "public" tables
-- automatically, so a table created without grants fails here instead of failing in the app.
begin;
select plan(4);

select is(
    (select coalesce(string_agg(c.relname, ', ' order by c.relname), '')
       from pg_class c
       join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relkind in ('r', 'p', 'v', 'm')
        and not (
            has_table_privilege('service_role', c.oid, 'SELECT')
            and has_table_privilege('service_role', c.oid, 'INSERT')
            and has_table_privilege('service_role', c.oid, 'UPDATE')
            and has_table_privilege('service_role', c.oid, 'DELETE')
        )),
    '',
    'every public table is fully granted to service_role'
);

-- Every table except the service-only ones is readable by signed-in people (RLS decides which rows).
select is(
    (select coalesce(string_agg(c.relname, ', ' order by c.relname), '')
       from pg_class c
       join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relkind in ('r', 'p', 'v', 'm')
        and c.relname not in ('visits', 'board_reads', 'board_additions', 'orbit_seen')
        and not has_table_privilege('authenticated', c.oid, 'SELECT')),
    '',
    'every public table that the app reads is granted to authenticated'
);

select ok(
    not has_table_privilege('anon', 'public.profile_private', 'SELECT')
    and not has_table_privilege('authenticated', 'public.profile_private', 'INSERT'),
    'profile_private is readable only by signed-in owners and written only through functions'
);

select ok(
    not has_table_privilege('anon', 'public.visits', 'SELECT')
    and not has_table_privilege('authenticated', 'public.visits', 'SELECT'),
    'visits stay service-only'
);

select * from finish();
rollback;
