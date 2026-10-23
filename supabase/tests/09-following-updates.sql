-- Discover marks followed boards that gained new pieces since the follower last opened them.
begin;
select plan(10);

insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
)
select '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated', email,
       crypt('x', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(),
       '', '', '', ''
from (values
    ('aaaaaaaa-0000-0000-0000-00000000000a'::uuid, 'updates-a@example.com'),
    ('bbbbbbbb-0000-0000-0000-00000000000b'::uuid, 'updates-b@example.com')
) as people(id, email);

-- A's public Mosaic has Golf (with a page inside), Travel, and a hidden Secret. B followed the
-- Mosaic and Golf two days ago.
insert into public.documents (id, owner_id, parent_id, role, title, visibility, body, revision) values
    ('a0000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'mosaic', 'A', 'public', '{"blocks":[]}', 1),
    ('a0000000-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'pursuit', 'Golf', 'public', '{"blocks":[]}', 1),
    ('a0000000-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'pursuit', 'Travel', 'public', '{"blocks":[]}', 1),
    ('a0000000-0000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'pursuit', 'Secret', 'hidden', '{"blocks":[]}', 1),
    ('a0000000-0000-0000-0000-000000000005', 'aaaaaaaa-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-000000000002', 'page', 'Range day', 'hidden', '{"blocks":[]}', 1);
-- Creating the page counted as adding it; that was before B followed.
update public.board_additions set added_at = now() - interval '3 days';
insert into public.follows (follower_id, target_owner_id, target_type, target_id, created_at) values
    ('bbbbbbbb-0000-0000-0000-00000000000b', 'aaaaaaaa-0000-0000-0000-00000000000a', 'mosaic', 'a0000000-0000-0000-0000-000000000001', now() - interval '2 days'),
    ('bbbbbbbb-0000-0000-0000-00000000000b', 'aaaaaaaa-0000-0000-0000-00000000000a', 'pursuit', 'a0000000-0000-0000-0000-000000000002', now() - interval '2 days');

create temporary view b_updates as
    select target_type, has_update from public.my_follows();
grant select on b_updates to authenticated;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select is((select bool_or(has_update) from b_updates), false,
    'nothing added since following is not an update');

-- A adds a photo on a page inside Golf, yesterday.
reset role;
update public.documents set body = '{"blocks":[{"id":{"rawValue":"22222222-0000-0000-0000-000000000001"},"kind":"media"}]}'
where id = 'a0000000-0000-0000-0000-000000000005';
update public.board_additions set added_at = now() - interval '1 day' where added_at > now() - interval '1 minute';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b","role":"authenticated"}', true);

select is((select has_update from b_updates where target_type = 'pursuit'), true,
    'a piece added inside a followed Pursuit marks it');
select is((select has_update from b_updates where target_type = 'mosaic'), true,
    'and marks its Mosaic');

select public.record_visit('a0000000-0000-0000-0000-000000000002');
select is((select has_update from b_updates where target_type = 'pursuit'), false,
    'opening the Pursuit clears its mark');
select is((select has_update from b_updates where target_type = 'mosaic'), false,
    'and its part of the Mosaic''s mark');

-- A moves that photo: same piece, so nothing new.
reset role;
update public.documents set body = '{"blocks":[{"id":{"rawValue":"22222222-0000-0000-0000-000000000001"},"kind":"media","position":{"x":0.5,"y":0.5}}]}'
where id = 'a0000000-0000-0000-0000-000000000005';
select is((select count(*)::int from public.board_additions where added_at > now() - interval '1 minute'), 0,
    'moving a piece adds nothing');

-- A adds to Travel, which B doesn't follow, and to the hidden Secret.
update public.documents set body = '{"blocks":[{"id":{"rawValue":"22222222-0000-0000-0000-000000000002"},"kind":"text","text":"Packing list for Lisbon"}]}'
where id in ('a0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000004');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b","role":"authenticated"}', true);

select is((select has_update from b_updates where target_type = 'mosaic'), true,
    'a piece added to any Pursuit the follower can open marks the Mosaic');
select public.record_visit('a0000000-0000-0000-0000-000000000001');
select is((select has_update from b_updates where target_type = 'mosaic'), false,
    'opening the Mosaic clears it; the hidden Pursuit''s piece never showed');

reset role;
select is((select count(*)::int from public.board_reads where viewer_id = 'aaaaaaaa-0000-0000-0000-00000000000a'), 0,
    'nobody reads their own boards here');
select ok(not has_table_privilege('authenticated', 'public.board_reads', 'SELECT'),
    'when people last opened boards stays out of the Data API');

select * from finish();
rollback;
