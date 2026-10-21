-- A Pursuit visitors can't see stays out of their copy at any group depth.
begin;
select plan(3);

select is(
    public.filter_pursuit_blocks(
        '[{"kind": "group", "groupMembers": [
            {"kind": "group", "groupMembers": [
                {"kind": "pursuit", "pursuitID": {"rawValue": "6c1f7a4e-0b39-4a52-9d6e-0f9b1c2d3e4f"},
                 "pursuitImageFileName": "secret-cover.jpg"},
                {"kind": "text", "text": "kept"}
            ]}
        ]}]'::jsonb,
        gen_random_uuid()
    ) #> '{0,groupMembers,0,groupMembers}',
    '[{"kind": "text", "text": "kept"}]'::jsonb,
    'a hidden Pursuit inside a group inside a group is removed; other pieces stay'
);

select is(
    public.filter_pursuit_blocks(
        '[{"kind": "group", "groupMembers": [
            {"kind": "pursuit", "pursuitID": {"rawValue": "6c1f7a4e-0b39-4a52-9d6e-0f9b1c2d3e4f"}}
        ]}]'::jsonb,
        gen_random_uuid()
    ) #> '{0,groupMembers}',
    '[]'::jsonb,
    'one group level deep still works'
);

select is(
    (select count(*)::int from public.board_pursuit_widgets(
        '{"blocks": [{"kind": "group", "groupMembers": [
            {"kind": "group", "groupMembers": [{"kind": "pursuit", "pursuitID": {"rawValue": "a"}}]},
            {"kind": "pursuit", "pursuitID": {"rawValue": "b"}}
        ]}, {"kind": "pursuit", "pursuitID": {"rawValue": "c"}}]}'::jsonb
    )),
    3,
    'the Pursuit widget list finds widgets at every group depth'
);

select * from finish();
rollback;
