-- Profile and Pursuit cards' follower counts: shown to people who may see the board, never otherwise.
begin;
select plan(6);

insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
)
select '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated', email,
       crypt('x', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(),
       '', '', '', ''
from (values
    ('aaaaaaaa-0000-0000-0000-00000000000a'::uuid, 'card-a@example.com'),
    ('bbbbbbbb-0000-0000-0000-00000000000b'::uuid, 'card-b@example.com'),
    ('cccccccc-0000-0000-0000-00000000000c'::uuid, 'card-c@example.com')
) as people(id, email);

-- A's Mosaic is public with two followers; C's is private.
insert into public.documents (id, owner_id, parent_id, role, title, visibility, body, revision) values
    ('a0000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'mosaic', 'A', 'public', '{"blocks":[]}', 1),
    ('a0000000-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'pursuit', 'Golf', 'public', '{"blocks":[]}', 1),
    ('a0000000-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'pursuit', 'Diary', 'private', '{"blocks":[]}', 1),
    ('c0000000-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-00000000000c', null, 'mosaic', 'C', 'private', '{"blocks":[]}', 1);
insert into public.follows (follower_id, target_owner_id, target_type, target_id) values
    ('bbbbbbbb-0000-0000-0000-00000000000b', 'aaaaaaaa-0000-0000-0000-00000000000a', 'mosaic', 'a0000000-0000-0000-0000-000000000001'),
    ('cccccccc-0000-0000-0000-00000000000c', 'aaaaaaaa-0000-0000-0000-00000000000a', 'mosaic', 'a0000000-0000-0000-0000-000000000001'),
    ('cccccccc-0000-0000-0000-00000000000c', 'aaaaaaaa-0000-0000-0000-00000000000a', 'pursuit', 'a0000000-0000-0000-0000-000000000002'),
    ('cccccccc-0000-0000-0000-00000000000c', 'aaaaaaaa-0000-0000-0000-00000000000a', 'pursuit', 'a0000000-0000-0000-0000-000000000003');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b","role":"authenticated"}', true);

select is((select follower_count from public.profile_view('aaaaaaaa-0000-0000-0000-00000000000a')), 2::bigint,
    'a Mosaic the viewer may see shows its follower count');
select is((select follows_mosaic from public.profile_view('aaaaaaaa-0000-0000-0000-00000000000a')), true,
    'and whether the viewer follows it');
select is((select follower_count from public.profile_view('cccccccc-0000-0000-0000-00000000000c')), null::bigint,
    'a private Mosaic keeps its count to itself');
select is((select can_view from public.profile_view('cccccccc-0000-0000-0000-00000000000c')), false,
    'and stays closed');

select is((select follower_count from public.viewer_pursuits('aaaaaaaa-0000-0000-0000-00000000000a') where title = 'Golf'),
    1::bigint, 'a Pursuit the viewer may open shows its follower count');
select is((select follower_count from public.viewer_pursuits('aaaaaaaa-0000-0000-0000-00000000000a') where title = 'Diary'),
    null::bigint, 'a private Pursuit the viewer cannot open keeps its count to itself');

select * from finish();
rollback;
