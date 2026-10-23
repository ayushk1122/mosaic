-- Orbit's seen state on the server: each change's time, what the follower saw, and covers.
begin;
select plan(14);

insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
)
select '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated', email,
       crypt('x', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(),
       '', '', '', ''
from (values
    ('aaaaaaaa-0000-0000-0000-00000000000a'::uuid, 'seen-a@example.com'),
    ('bbbbbbbb-0000-0000-0000-00000000000b'::uuid, 'seen-b@example.com')
) as people(id, email);

-- A's public Mosaic shows Golf with a cover; Diary is private. B follows Golf.
insert into public.documents (id, owner_id, parent_id, role, title, visibility, body, revision) values
    ('a0000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'mosaic', 'A', 'public',
     '{"blocks":[{"id":{"rawValue":"W"},"kind":"pursuit","pursuitID":{"rawValue":"A0000000-0000-0000-0000-000000000002"},"pursuitImageFileName":"cover.jpg"}],
       "mediaAssets":{"cover.jpg":"ASSET-1"}}', 1),
    ('a0000000-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'pursuit', 'Golf', 'public',
     '{"blocks":[{"id":{"rawValue":"T"},"kind":"text","text":"Range day"}]}', 1),
    ('a0000000-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'pursuit', 'Diary', 'private', '{"blocks":[]}', 1);
insert into public.follows (follower_id, target_owner_id, target_type, target_id, created_at) values
    ('bbbbbbbb-0000-0000-0000-00000000000b', 'aaaaaaaa-0000-0000-0000-00000000000a', 'pursuit', 'a0000000-0000-0000-0000-000000000002', now() - interval '2 days');
-- What was there when the boards were made counts from an hour ago.
update public.board_additions set added_at = now() - interval '1 hour';

create temporary view feed as
    select board_id, pieces, cover_file, cover_asset, seen_keys from public.today_feed();
grant select on feed to authenticated;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b","role":"authenticated"}', true);

select is((select (pieces->0->>'at')::timestamptz from feed), now() - interval '1 hour', 'each change carries its time');
select is((select cover_file || ' ' || cover_asset from feed), 'cover.jpg ASSET-1', 'a Pursuit comes with its cover');
select is((select seen_keys from feed), '{}'::jsonb, 'nothing seen yet');

-- B sees the note.
select public.mark_orbit_seen('a0000000-0000-0000-0000-000000000002',
    jsonb_build_object('t', (select pieces->0->>'at' from feed)));
select is((select (seen_keys->>'t')::timestamptz from feed), now() - interval '1 hour', 'what was seen comes back with the feed');

select public.mark_orbit_seen('a0000000-0000-0000-0000-000000000002',
    jsonb_build_object('t', (now() - interval '3 hours')::text));
select is((select (seen_keys->>'t')::timestamptz from feed), now() - interval '1 hour', 'an older report never lowers it');

select public.mark_orbit_seen('a0000000-0000-0000-0000-000000000002',
    jsonb_build_object('later', (now() + interval '1 day')::text));
select is((select (seen_keys->>'later')::timestamptz from feed), now(), 'a time in the future counts as now');

select throws_ok(
    $$select public.mark_orbit_seen('a0000000-0000-0000-0000-000000000002', '["t"]'::jsonb)$$,
    '22023', null, 'only a key-to-time object is accepted');

-- A board B can't read stores nothing.
select public.mark_orbit_seen('a0000000-0000-0000-0000-000000000003', jsonb_build_object('x', now()::text));
reset role;
select is((select count(*)::int from public.orbit_seen where board_id = 'a0000000-0000-0000-0000-000000000003'), 0,
    'nothing is kept for a board the follower can''t read');

-- A writes more in the same note: the same change, at a later time, so it's new again.
update public.documents set body = '{"blocks":[{"id":{"rawValue":"T"},"kind":"text","text":"Range day: worked on the driver"}]}'
 where id = 'a0000000-0000-0000-0000-000000000002';
update public.documents set body = '{"blocks":[{"id":{"rawValue":"T"},"kind":"text","text":"Range day: worked on the driver, then putting for an hour"}]}'
 where id = 'a0000000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select is((select count(*)::int from feed, jsonb_array_elements(pieces) piece where piece->>'id' = 't#text:text'), 1,
    'more writing in the same note is one change');
select ok((select (piece->>'at')::timestamptz > (seen_keys->>'t')::timestamptz
             from feed, jsonb_array_elements(pieces) piece where piece->>'id' = 't#text:text'),
    'whose time is after what was seen, so it counts as new');

select ok(not has_table_privilege('authenticated', 'public.orbit_seen', 'SELECT'), 'followers can''t read the table directly');
reset role;
select ok(not has_function_privilege('anon', 'public.mark_orbit_seen(uuid, jsonb)', 'EXECUTE'), 'signed-out callers can''t record anything');

-- A deletes the note: its changes leave Orbit.
update public.documents set body = '{"blocks":[]}' where id = 'a0000000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select is((select count(*)::int from feed), 0, 'a deleted piece''s changes leave Orbit');

-- Deleting the account removes what it saw.
reset role;
delete from auth.users where id = 'bbbbbbbb-0000-0000-0000-00000000000b';
select is((select count(*)::int from public.orbit_seen), 0, 'and a deleted account''s record goes with it');

select * from finish();
rollback;
