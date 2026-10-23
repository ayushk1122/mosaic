-- Orbit: boards the viewer follows that gained pieces they can see in the last 24 hours.
begin;
select plan(12);

insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
)
select '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated', email,
       crypt('x', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(),
       '', '', '', ''
from (values
    ('aaaaaaaa-0000-0000-0000-00000000000a'::uuid, 'today-a@example.com'),
    ('bbbbbbbb-0000-0000-0000-00000000000b'::uuid, 'today-b@example.com'),
    ('cccccccc-0000-0000-0000-00000000000c'::uuid, 'today-c@example.com')
) as people(id, email);

-- A's public Mosaic with a public Golf, a private Diary, and a hidden Secret. B follows the
-- Mosaic; C follows only Golf.
insert into public.documents (id, owner_id, parent_id, role, title, visibility, body, revision) values
    ('a0000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'mosaic', 'A', 'public', '{"blocks":[]}', 1),
    ('a0000000-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'pursuit', 'Golf', 'public', '{"blocks":[]}', 1),
    ('a0000000-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'pursuit', 'Diary', 'private', '{"blocks":[]}', 1),
    ('a0000000-0000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'pursuit', 'Secret', 'hidden', '{"blocks":[]}', 1);
insert into public.follows (follower_id, target_owner_id, target_type, target_id, created_at) values
    ('bbbbbbbb-0000-0000-0000-00000000000b', 'aaaaaaaa-0000-0000-0000-00000000000a', 'mosaic', 'a0000000-0000-0000-0000-000000000001', now() - interval '2 days'),
    ('cccccccc-0000-0000-0000-00000000000c', 'aaaaaaaa-0000-0000-0000-00000000000a', 'pursuit', 'a0000000-0000-0000-0000-000000000002', now() - interval '2 days');

create temporary view feed as
    select title, pieces, seen from public.today_feed();
grant select on feed to authenticated;

-- A adds two photos to Golf an hour ago, a note to the private Diary, and a widget for the hidden
-- Secret to the Mosaic.
update public.documents set body = '{"blocks":[
    {"id":{"rawValue":"33333333-0000-0000-0000-000000000001"},"kind":"media"},
    {"id":{"rawValue":"33333333-0000-0000-0000-000000000002"},"kind":"media"}]}'
where id = 'a0000000-0000-0000-0000-000000000002';
update public.documents set body = '{"blocks":[{"id":{"rawValue":"33333333-0000-0000-0000-000000000003"},"kind":"text","text":"Dear diary, today was long"}]}'
where id = 'a0000000-0000-0000-0000-000000000003';
update public.documents set body = '{"blocks":[{"id":{"rawValue":"33333333-0000-0000-0000-000000000004"},"kind":"pursuit",
    "pursuitID":{"rawValue":"A0000000-0000-0000-0000-000000000004"}}]}'
where id = 'a0000000-0000-0000-0000-000000000001';
update public.board_additions set added_at = now() - interval '1 hour';

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select is((select count(*)::int from feed), 0,
    'following a Mosaic doesn''t bring in Pursuits that aren''t followed themselves, nor a hidden Pursuit''s widget');

select set_config('request.jwt.claims', '{"sub":"cccccccc-0000-0000-0000-00000000000c","role":"authenticated"}', true);
select is((select array_agg(title) from feed), array['Golf'], 'a followed Pursuit shows');
select is((select jsonb_array_length(pieces) from feed where title = 'Golf'), 2, 'with the pieces added');
select is((select pieces->0->>'kind' from feed where title = 'Golf'), 'media', 'and what kind they are');
select is((select seen from feed where title = 'Golf'), false, 'not opened yet');

-- A adds a note to the Mosaic itself, just now.
reset role;
update public.documents set body = '{"blocks":[
    {"id":{"rawValue":"33333333-0000-0000-0000-000000000004"},"kind":"pursuit","pursuitID":{"rawValue":"A0000000-0000-0000-0000-000000000004"}},
    {"id":{"rawValue":"33333333-0000-0000-0000-000000000005"},"kind":"text","text":"A note for everyone today"}]}'
where id = 'a0000000-0000-0000-0000-000000000001';
set local role authenticated;

select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select is((select array_agg(title) from feed), array['A'], 'a followed Mosaic shows when pieces are added to it');
select set_config('request.jwt.claims', '{"sub":"cccccccc-0000-0000-0000-00000000000c","role":"authenticated"}', true);
select is((select array_agg(title) from feed), array['Golf'], 'a Mosaic shows only to its followers');

select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select public.record_visit('a0000000-0000-0000-0000-000000000001');
select is((select seen from feed where title = 'A'), true, 'opening it is noted');

-- A takes the note off the Mosaic again, and Golf's photos are from yesterday.
reset role;
update public.documents set body = '{"blocks":[{"id":{"rawValue":"33333333-0000-0000-0000-000000000004"},"kind":"pursuit",
    "pursuitID":{"rawValue":"A0000000-0000-0000-0000-000000000004"}}]}'
where id = 'a0000000-0000-0000-0000-000000000001';
update public.board_additions set added_at = now() - interval '25 hours' where board_id = 'a0000000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select is((select count(*)::int from feed), 0, 'a piece taken off again, and anything older than a day, are gone');

-- A's own boards never show to A.
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a","role":"authenticated"}', true);
select is((select count(*)::int from feed), 0, 'nobody sees their own boards here');

reset role;
select ok(not has_table_privilege('authenticated', 'public.board_additions', 'SELECT'),
    'what was added when stays out of the Data API');
select ok(not has_function_privilege('anon', 'public.today_feed()', 'EXECUTE'),
    'signed-out callers can''t read the feed');

select * from finish();
rollback;
