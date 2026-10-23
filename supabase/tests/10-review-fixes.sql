-- Fixes from the 2026-10-22 review.
begin;
select plan(7);

insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
)
select '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated', email,
       crypt('x', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(),
       '', '', '', ''
from (values
    ('aaaaaaaa-0000-0000-0000-00000000000a'::uuid, 'review-a@example.com'),
    ('bbbbbbbb-0000-0000-0000-00000000000b'::uuid, 'review-b@example.com')
) as people(id, email);

-- A's public Mosaic, shared to Explore with a preview, and a public Pursuit.
insert into public.documents (id, owner_id, parent_id, role, title, visibility, body, revision,
                              explore_shared, explore_shared_at, explore_preview, explore_preview_at) values
    ('a0000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'mosaic', 'A', 'public', '{"blocks":[]}', 1,
     true, now(), '11111111-0000-0000-0000-000000000001', now()),
    ('a0000000-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'pursuit', 'Golf', 'public', '{"blocks":[]}', 1,
     false, null, null, null);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a","role":"authenticated"}', true);

-- Saving a board this device knew at revision 3 that is gone from the server.
select throws_ok(
    $$ select * from public.save_document('a0000000-0000-0000-0000-0000000000ff', 'a0000000-0000-0000-0000-000000000002', 'page', 'Gone', '{"blocks":[]}', 3) $$,
    'MS404', 'document deleted',
    'a board deleted elsewhere is not brought back by a stale save'
);
select is((select count(*)::int from public.documents where id = 'a0000000-0000-0000-0000-0000000000ff'), 0,
    'and no row is created');
select is((select revision from public.save_document('a0000000-0000-0000-0000-0000000000fe', 'a0000000-0000-0000-0000-000000000002', 'page', 'New', '{"blocks":[]}', 0)),
    1::bigint, 'a new board still saves');

-- B can read the Mosaic's preview image, but nothing else in its folder.
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select ok(public.viewer_can_read_media('aaaaaaaa-0000-0000-0000-00000000000a/11111111-0000-0000-0000-000000000001/display'),
    'a shared preview is readable');
select ok(not public.viewer_can_read_media('aaaaaaaa-0000-0000-0000-00000000000a/11111111-0000-0000-0000-000000000001/original'),
    'another file in the preview''s folder is not');

-- A makes Golf private: the Mosaic's picture may show it, so it goes until it is redrawn.
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a","role":"authenticated"}', true);
select public.set_document_visibility('a0000000-0000-0000-0000-000000000002', 'private');
reset role;
select is((select explore_preview from public.documents where id = 'a0000000-0000-0000-0000-000000000001'), null::uuid,
    'a Pursuit changing visibility drops its Mosaic''s preview');
select is((select explore_shared from public.documents where id = 'a0000000-0000-0000-0000-000000000001'), true,
    'while the Mosaic stays shared, to come back once redrawn');

select * from finish();
rollback;
