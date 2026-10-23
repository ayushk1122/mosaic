-- Explore lists only boards their owners chose to share, that visitors could open, with a preview,
-- and never the caller's own. Leaving Public takes a board out at once.
begin;
select plan(30);

-- Setup as the database owner: A has a public Mosaic with a public and a hidden Pursuit,
-- C has a private Mosaic with a public Pursuit, and B browses.
insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
)
select '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated', email,
       crypt('x', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(),
       '', '', '', ''
from (values
    ('aaaaaaaa-0000-0000-0000-00000000000a'::uuid, 'explore-a@example.com'),
    ('bbbbbbbb-0000-0000-0000-00000000000b'::uuid, 'explore-b@example.com'),
    ('cccccccc-0000-0000-0000-00000000000c'::uuid, 'explore-c@example.com')
) as people(id, email);

update public.profiles set display_name = 'Ada' where id = 'aaaaaaaa-0000-0000-0000-00000000000a';

insert into public.documents (id, owner_id, parent_id, role, title, visibility, body, revision) values
    ('a0000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'mosaic', 'A', 'public', '{"blocks":[]}', 1),
    ('a0000000-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'pursuit', 'Golf', 'public', '{"blocks":[]}', 1),
    ('a0000000-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'pursuit', 'Secret', 'hidden', '{"blocks":[]}', 1),
    ('c0000000-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-00000000000c', null, 'mosaic', 'C', 'private', '{"blocks":[]}', 1),
    ('c0000000-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-00000000000c', null, 'pursuit', 'Running', 'public', '{"blocks":[]}', 1);

set local role authenticated;

-- As A, the owner.
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a","role":"authenticated"}', true);
select lives_ok($$ select public.set_explore_sharing('a0000000-0000-0000-0000-000000000001', true) $$,
    'a public Mosaic can be shared');
select lives_ok($$ select public.set_explore_sharing('a0000000-0000-0000-0000-000000000002', true) $$,
    'a public Pursuit on a public Mosaic can be shared');
select throws_ok($$ select public.set_explore_sharing('a0000000-0000-0000-0000-000000000003', true) $$,
    '22023', null, 'a hidden Pursuit cannot be shared');
select throws_ok($$ select public.set_explore_preview('a0000000-0000-0000-0000-000000000003', gen_random_uuid()) $$,
    '42501', null, 'an unshared board takes no preview');
select lives_ok($$ select public.set_explore_preview('a0000000-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000001') $$,
    'the owner sets the Mosaic preview');
select is((select count(*)::int from public.explore_feed('all', 'seed', 0, 30)), 0,
    'nobody sees their own boards in Explore');

-- As C, whose Mosaic is private.
select set_config('request.jwt.claims', '{"sub":"cccccccc-0000-0000-0000-00000000000c","role":"authenticated"}', true);
select throws_ok($$ select public.set_explore_sharing('c0000000-0000-0000-0000-000000000002', true) $$,
    '22023', null, 'a public Pursuit on a private Mosaic cannot be shared');
select throws_ok($$ select public.set_explore_sharing('a0000000-0000-0000-0000-000000000001', false) $$,
    '42501', null, 'someone else''s board cannot be changed');

-- As B, browsing.
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select is(
    (select array_agg(title order by title) from public.explore_feed('all', 'seed', 0, 30)),
    array['A'],
    'only shared boards with a preview are listed'
);
select is(
    (select display_name || ' / ' || preview_path from public.explore_feed('mosaics', 'seed', 0, 30)),
    'Ada / aaaaaaaa-0000-0000-0000-00000000000a/11111111-0000-0000-0000-000000000001/display',
    'tiles carry the owner''s name and the preview''s path'
);
select ok(public.viewer_can_read_media('aaaaaaaa-0000-0000-0000-00000000000a/11111111-0000-0000-0000-000000000001/display'),
    'a shared preview is readable');
select ok(not public.viewer_can_read_media('aaaaaaaa-0000-0000-0000-00000000000a/22222222-0000-0000-0000-000000000002/display'),
    'other files in the owner''s folder are not');

-- A adds the Pursuit's preview: the filter and paging see both.
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a","role":"authenticated"}', true);
select public.set_explore_preview('a0000000-0000-0000-0000-000000000002', '11111111-0000-0000-0000-000000000002');
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select is((select array_agg(title) from public.explore_feed('pursuits', 'seed', 0, 30)), array['Golf'],
    'the Pursuits filter lists only Pursuits');
select ok(
    (select title from public.explore_feed('all', 'seed', 0, 1)) is distinct from
    (select title from public.explore_feed('all', 'seed', 1, 1)),
    'the same seed pages without repeating'
);
-- Sorting by followers: B follows A's Golf Pursuit, nobody follows A's Mosaic.
reset role;
insert into public.follows (follower_id, target_owner_id, target_type, target_id)
values ('bbbbbbbb-0000-0000-0000-00000000000b', 'aaaaaaaa-0000-0000-0000-00000000000a', 'pursuit', 'a0000000-0000-0000-0000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select is((select array_agg(title) from public.explore_feed('all', 'seed', 0, 30, '', 'popular')), array['Golf', 'A'],
    'most followed first');
select is((select array_agg(title) from public.explore_feed('all', 'seed', 0, 30, '', 'least_popular')), array['A', 'Golf'],
    'fewest followed first');
select is((select follower_count from public.explore_feed('pursuits', 'seed', 0, 30)), 1::bigint,
    'tiles carry their follower count');

-- Golf was shared a day after the Mosaic but last changed two days before it; C followed the
-- Mosaic a month ago, so only Golf has a follower from this week.
reset role;
update public.documents set explore_shared_at = now() - interval '1 day', updated_at = now() - interval '3 days'
where id = 'a0000000-0000-0000-0000-000000000001';
update public.documents set explore_shared_at = now(), updated_at = now() - interval '5 days'
where id = 'a0000000-0000-0000-0000-000000000002';
insert into public.follows (follower_id, target_owner_id, target_type, target_id, created_at)
values ('cccccccc-0000-0000-0000-00000000000c', 'aaaaaaaa-0000-0000-0000-00000000000a', 'mosaic', 'a0000000-0000-0000-0000-000000000001', now() - interval '30 days');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select is((select array_agg(title) from public.explore_feed('all', 'seed', 0, 30, '', 'newest')), array['Golf', 'A'],
    'newest to Explore first');
select is((select array_agg(title) from public.explore_feed('all', 'seed', 0, 30, '', 'updated')), array['A', 'Golf'],
    'most recently changed first');
select is((select array_agg(title) from public.explore_feed('all', 'seed', 0, 30, '', 'trending')), array['Golf', 'A'],
    'most new followers this week first, though both have one in all');
select is((select array_agg(title) from public.explore_feed('all', 'seed', 0, 30, '', 'shuffle', true)), array['A'],
    'boards the caller follows can be left out');
select is((select count(*)::int from public.explore_feed('all', 'seed', 0, 30, '', 'shuffle', false)), 2,
    'and are listed otherwise');
select is((select array_agg(title order by title) from public.explore_feed('all', 'seed', 0, 30, 'GOL')), array['Golf'],
    'search matches a board title, ignoring case');
select is((select array_agg(title order by title) from public.explore_feed('all', 'seed', 0, 30, 'ada')), array['A', 'Golf'],
    'search matches the owner''s display name');
select is((select count(*)::int from public.explore_feed('all', 'seed', 0, 30, '%')), 0,
    'a percent sign is matched as itself, not as a wildcard');
select is((select array_agg(title) from public.explore_feed('mosaics', 'seed', 0, 30, 'ada')), array['A'],
    'search and the filter work together');

-- A makes the Pursuit private, then the Mosaic: each leaves Explore at once.
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a","role":"authenticated"}', true);
select public.set_document_visibility('a0000000-0000-0000-0000-000000000002', 'private');
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select is((select array_agg(title) from public.explore_feed('all', 'seed', 0, 30)), null::text[],
    'a Pursuit made private leaves Explore, and its Mosaic waits for a new picture without it');
select ok(not public.viewer_can_read_media('aaaaaaaa-0000-0000-0000-00000000000a/11111111-0000-0000-0000-000000000002/display'),
    'and its preview is no longer readable');

select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a","role":"authenticated"}', true);
select public.set_document_visibility('a0000000-0000-0000-0000-000000000001', 'private');
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select is((select count(*)::int from public.explore_feed('all', 'seed', 0, 30)), 0,
    'a Mosaic made private leaves Explore');

reset role;
select is(
    (select count(*)::int from public.documents where owner_id = 'aaaaaaaa-0000-0000-0000-00000000000a' and explore_shared),
    0,
    'leaving Public turns sharing off, so publishing again asks again'
);

select * from finish();
rollback;
