-- What counts as an update inside pieces, and where Orbit marks it.
begin;
select plan(15);

-- Unit level: what one save to the other counts.
select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"C"},"kind":"carousel","carouselItems":[{"id":"one","kind":"media","fileName":"a.jpg"}]}]}',
        '{"blocks":[{"id":{"rawValue":"C"},"kind":"carousel","carouselItems":[{"id":"one","kind":"media","fileName":"a.jpg"},{"id":"two","kind":"media","fileName":"b.jpg"}]}]}'
    ),
    '[{"id":"c/carouselitems/two","kind":"media","piece":"c"}]'::jsonb,
    'a card added to a carousel marks the carousel'
);
select is(
    jsonb_array_length(public.board_changes(
        '{"blocks":[{"id":{"rawValue":"K"},"kind":"calendar","calendarEntries":[{"year":2026,"month":10,"day":22,"media":[],"note":""}]}]}',
        '{"blocks":[{"id":{"rawValue":"K"},"kind":"calendar","calendarEntries":[{"year":2026,"month":10,"day":22,"media":[{"id":"p","fileName":"p.jpg"}],"note":"Shot 82 at Pebble Creek"}]}]}'
    )),
    2,
    'a photo and a note on a calendar day both count'
);
select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"T"},"kind":"text","text":"Range day"}]}',
        '{"blocks":[{"id":{"rawValue":"T"},"kind":"text","text":"Range day!"}]}'
    ),
    '[]'::jsonb,
    'fixing a typo doesn''t count'
);
select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"T"},"kind":"text","text":"Range day"}]}',
        '{"blocks":[{"id":{"rawValue":"T"},"kind":"text","text":"Range day: worked on the driver"}]}'
    )->0->>'kind',
    'writing',
    'writing a few words does'
);
select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"L"},"kind":"list","listItems":[{"id":"w3","text":"Week 3","isChecked":false}]}]}',
        '{"blocks":[{"id":{"rawValue":"L"},"kind":"list","listItems":[{"id":"w3","text":"Week 3","isChecked":true}]}]}'
    )->0->>'kind',
    'checked',
    'checking off an item counts'
);
select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"B"},"kind":"banner","mediaFileName":"old.jpg"}]}',
        '{"blocks":[{"id":{"rawValue":"B"},"kind":"banner","mediaFileName":"new.jpg"}]}'
    )->0->>'kind',
    'banner',
    'a new banner photo counts'
);
select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"M"},"kind":"media","mediaFileName":"a.jpg","position":{"x":0.1,"y":0.1},"style":{"opacity":1}}],"background":{"kind":"color"}}',
        '{"blocks":[{"id":{"rawValue":"M"},"kind":"media","mediaFileName":"a.jpg","position":{"x":0.6,"y":0.4},"style":{"opacity":0.5}}],"background":{"kind":"photo"}}'
    ),
    '[]'::jsonb,
    'moving, restyling, and a new background don''t'
);
select is(
    public.board_changes(
        '{"blocks":[]}',
        '{"blocks":[{"id":{"rawValue":"E"},"kind":"text","text":""}]}'
    ),
    '[]'::jsonb,
    'an empty text piece waits for words'
);
select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"G"},"kind":"graph","graphPoints":[{"id":"1","x":1,"y":80}]}]}',
        '{"blocks":[{"id":{"rawValue":"G"},"kind":"graph","graphPoints":[{"id":"1","x":1,"y":80},{"id":"2","x":2,"y":78}]}]}'
    ),
    '[{"id":"g/graphpoints/2","kind":"graphpoints","piece":"g"}]'::jsonb,
    'a point added to a graph counts'
);

-- Board level: a change inside a node shows on the Pursuit, with the way there.
insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
)
select '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated', email,
       crypt('x', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(),
       '', '', '', ''
from (values
    ('aaaaaaaa-0000-0000-0000-00000000000a'::uuid, 'changes-a@example.com'),
    ('bbbbbbbb-0000-0000-0000-00000000000b'::uuid, 'changes-b@example.com')
) as people(id, email);

-- A's Golf holds a node with a carousel; B follows Golf.
insert into public.documents (id, owner_id, parent_id, role, title, visibility, body, revision) values
    ('a0000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'mosaic', 'A', 'public', '{"blocks":[]}', 1),
    ('a0000000-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-00000000000a', null, 'pursuit', 'Golf', 'public',
     '{"blocks":[{"id":{"rawValue":"N-WIDGET"},"kind":"node","pursuitID":{"rawValue":"A0000000-0000-0000-0000-000000000003"}}]}', 1),
    ('a0000000-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-000000000002', 'node', 'Lessons', 'hidden',
     '{"blocks":[{"id":{"rawValue":"CAROUSEL"},"kind":"carousel","carouselItems":[{"id":"one","kind":"media","fileName":"a.jpg"}]}]}', 1);
delete from public.board_additions;
insert into public.follows (follower_id, target_owner_id, target_type, target_id, created_at) values
    ('bbbbbbbb-0000-0000-0000-00000000000b', 'aaaaaaaa-0000-0000-0000-00000000000a', 'pursuit', 'a0000000-0000-0000-0000-000000000002', now() - interval '2 days');

update public.documents
   set body = '{"blocks":[{"id":{"rawValue":"CAROUSEL"},"kind":"carousel","carouselItems":[{"id":"one","kind":"media","fileName":"a.jpg"},{"id":"two","kind":"media","fileName":"b.jpg"}]}]}'
 where id = 'a0000000-0000-0000-0000-000000000003';

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b","role":"authenticated"}', true);

create temporary view changes as
    select title, pieces from public.today_feed();
grant select on changes to authenticated;

select is((select title from changes), 'Golf', 'a card added inside a node puts its Pursuit in Today');
select is((select pieces->0->>'piece' from changes), 'carousel', 'marking the carousel');
select is((select pieces->0->'in' from changes), '["a0000000-0000-0000-0000-000000000003"]'::jsonb,
    'and the node it sits in, so the node''s widget on the Pursuit is marked too');
select is((select pieces->0->>'kind' from changes), 'media', 'as a photo card');
select is((select has_update from public.my_follows() where target_type = 'pursuit'), true,
    'Discover marks it the same way');

reset role;
select ok(not has_function_privilege('authenticated', 'public.board_changes(jsonb, jsonb)', 'EXECUTE'),
    'the comparison runs only inside the server');

select * from finish();
rollback;
