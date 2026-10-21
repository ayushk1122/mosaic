-- Blurred previews go to visitors only for files their copy of the board still uses, and a
-- preview never makes a file count as used.
begin;
select plan(4);

select is(
    public.viewer_board_body(
        '{"blocks": [{"kind": "media", "mediaFileName": "shown.jpg"}],
          "mediaAssets": {"shown.jpg": "11111111-1111-1111-1111-111111111111"},
          "mediaPreviews": {"shown.jpg": "1.5|8x5|AAAA"}}'::jsonb,
        gen_random_uuid()
    ) -> 'mediaPreviews',
    '{"shown.jpg": "1.5|8x5|AAAA"}'::jsonb,
    'a photo on the board keeps its preview'
);

select is(
    public.viewer_board_body(
        '{"blocks": [], "stickerLibrary": [{"fileName": "saved.png", "width": 200, "height": 180}],
          "mediaAssets": {"saved.png": "22222222-2222-2222-2222-222222222222"},
          "mediaPreviews": {"saved.png": "1|8x8|AAAA"}}'::jsonb,
        gen_random_uuid()
    ) ? 'mediaPreviews',
    false,
    'a saved sticker''s preview is not sent'
);

select is(
    public.viewer_board_body(
        '{"blocks": [],
          "mediaAssets": {"hidden.jpg": "33333333-3333-3333-3333-333333333333"},
          "mediaPreviews": {"hidden.jpg": "1|8x8|AAAA"}}'::jsonb,
        gen_random_uuid()
    ) ? 'mediaAssets',
    false,
    'a preview alone does not make its file readable'
);

select is(
    public.viewer_board_body('{"blocks": []}'::jsonb, gen_random_uuid()),
    '{"blocks": []}'::jsonb,
    'boards without previews are unchanged'
);

select * from finish();
rollback;
