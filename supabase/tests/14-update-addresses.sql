-- Updates found from the saved data itself: addresses for nested things, a component the server
-- has never heard of, content arriving later, and look and layout never counting.
begin;
select plan(15);

select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"G"},"kind":"group","groupMembers":[
            {"id":{"rawValue":"C"},"kind":"carousel","carouselItems":[{"id":"one","kind":"media","fileName":"a.jpg"}]}]}]}',
        '{"blocks":[{"id":{"rawValue":"G"},"kind":"group","groupMembers":[
            {"id":{"rawValue":"C"},"kind":"carousel","carouselItems":[{"id":"one","kind":"media","fileName":"a.jpg"},{"id":"Two","kind":"media","fileName":"b.jpg"}]}]}]}'
    ),
    '[{"id":"c/carouselitems/two","kind":"media","piece":"c"}]'::jsonb,
    'a card in a carousel in a group is addressed under the carousel, which is the piece to mark'
);

select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"K"},"kind":"calendar","calendarEntries":[{"year":2026,"month":3,"day":5,"media":[],"note":""}]}]}',
        '{"blocks":[{"id":{"rawValue":"K"},"kind":"calendar","calendarEntries":[{"year":2026,"month":3,"day":5,"media":[{"id":"P","fileName":"p.jpg"}],"note":""}]}]}'
    ),
    '[{"id":"k/calendarentries/2026-03-05/media/p","kind":"media","piece":"k"}]'::jsonb,
    'a calendar day is addressed by its date, and its photo under it'
);

select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"S"},"kind":"scoreboard","rounds":[{"id":"r1","score":82}]}]}',
        '{"blocks":[{"id":{"rawValue":"S"},"kind":"scoreboard","rounds":[{"id":"r1","score":82},{"id":"r2","score":79,"course":"Pebble Creek"}]}]}'
    ),
    '[{"id":"s/rounds/r2","kind":"rounds","piece":"s"}]'::jsonb,
    'a component the server has never heard of gets addresses with no code'
);

select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"L"},"kind":"list","listItems":[{"id":"w3","text":"","isChecked":false}]}]}',
        '{"blocks":[{"id":{"rawValue":"L"},"kind":"list","listItems":[{"id":"w3","text":"Week 3","isChecked":false}]}]}'
    ),
    '[{"id":"l/listitems/w3","kind":"listitems","piece":"l"}]'::jsonb,
    'a list item saved empty counts once it has words'
);

select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"T"},"kind":"text","text":""}]}',
        '{"blocks":[{"id":{"rawValue":"T"},"kind":"text","text":"Hi"}]}'
    ),
    '[{"id":"t","kind":"text","piece":"t"}]'::jsonb,
    'and so does a text piece'
);

select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"M"},"kind":"media","mediaFileName":"a.jpg","rotation":0,"mediaZoom":1,"mediaPanX":0,"tabID":"x","isLocked":false,"opacity":1}]}',
        '{"blocks":[{"id":{"rawValue":"M"},"kind":"media","mediaFileName":"a.jpg","rotation":0.4,"mediaZoom":2,"mediaPanX":0.3,"tabID":"y","isLocked":true,"opacity":0.4}]}'
    ),
    '[]'::jsonb,
    'rotating, zooming, panning, moving to another tab, locking, and fading don''t count'
);

select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"D"},"kind":"drawing","drawingData":"AAAA"}]}',
        '{"blocks":[{"id":{"rawValue":"D"},"kind":"drawing","drawingData":"AAAABBBBCCCCDDDDEEEEFFFF"}]}'
    ),
    '[]'::jsonb,
    'redrawing a drawing isn''t writing'
);

select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"M"},"kind":"media","mediaFileName":"a.jpg"}]}',
        '{"blocks":[{"id":{"rawValue":"M"},"kind":"media","mediaFileName":"b.jpg"}]}'
    ),
    '[{"id":"m#file:mediaFileName","kind":"photo","piece":"m"}]'::jsonb,
    'a different photo names the field it went into'
);

select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"TB"},"kind":"table","tableEntries":[]}]}',
        '{"blocks":[{"id":{"rawValue":"TB"},"kind":"table","tableEntries":[{"id":"E1","stampedAt":800000000,"rows":[{"id":"R1","cells":["82",""]}]}]}]}'
    ),
    '[{"id":"tb/tableentries/e1/rows/r1","kind":"rows","piece":"tb"}]'::jsonb,
    'a table entry counts by the row with something in it, not the empty entry around it'
);

select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"TB"},"kind":"table","tableEntries":[{"id":"E1","rows":[{"id":"R1","cells":["82",""]}]}]}]}',
        '{"blocks":[{"id":{"rawValue":"TB"},"kind":"table","tableEntries":[{"id":"E1","rows":[{"id":"R1","cells":["82","Windy, played the back nine"]}]}]}]}'
    ),
    '[{"id":"tb/tableentries/e1/rows/r1#text:cells.2","kind":"writing","piece":"tb"}]'::jsonb,
    'writing in a cell names the cell'
);

select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"K"},"kind":"calendar","calendarEntries":[{"year":2026,"month":10,"day":22,"media":[],"note":"Range"}]}]}',
        '{"blocks":[{"id":{"rawValue":"K"},"kind":"calendar","calendarEntries":[{"year":2026,"month":10,"day":22,"media":[],"note":"Range, then nine holes with Sam"}]}]}'
    ),
    '[{"id":"k/calendarentries/2026-10-22#text:note","kind":"writing","piece":"k"}]'::jsonb,
    'writing more in a day''s note is writing on that day'
);

select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"P"},"kind":"media","mediaFileName":"p.jpg"},{"id":{"rawValue":"G"},"kind":"group","groupMembers":[]}]}',
        '{"blocks":[{"id":{"rawValue":"G"},"kind":"group","groupMembers":[{"id":{"rawValue":"P"},"kind":"media","mediaFileName":"p.jpg"}]}]}'
    ),
    '[]'::jsonb,
    'moving a piece into a group isn''t new'
);

select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"A"},"kind":"text","text":"Unchanged"},{"id":{"rawValue":"L"},"kind":"list","listItems":[]}]}',
        '{"blocks":[{"id":{"rawValue":"A"},"kind":"text","text":"Unchanged"},{"id":{"rawValue":"L"},"kind":"list","listItems":[{"id":"x","text":"Book a lesson","isChecked":false}]}]}'
    ),
    '[{"id":"l/listitems/x","kind":"listitems","piece":"l"}]'::jsonb,
    'pieces saved as they were add nothing; the one that changed is still read'
);

select is(
    public.board_changes(
        '{"blocks":[{"id":{"rawValue":"TB"},"kind":"table","tableRows":[{"id":"R1","cells":["",""]}],"tableEntries":[{"id":"E1","rows":[{"id":"R1","cells":["",""]}]}]}]}',
        '{"blocks":[{"id":{"rawValue":"TB"},"kind":"table","tableRows":[{"id":"R1","cells":["79",""]}],"tableEntries":[{"id":"E1","rows":[{"id":"R1","cells":["79",""]}]}]}]}'
    ),
    '[{"id":"tb/tableentries/e1/rows/r1","kind":"rows","piece":"tb"}]'::jsonb,
    'a row edited on screen counts once, under its entry, not again in the copy on screen'
);

select ok(not has_function_privilege('authenticated', 'public.board_addressed(jsonb)', 'EXECUTE'),
    'the walk runs only inside the server');

select * from finish();
rollback;
