-- Saved stickers stay private: visitors' copy of a board drops the list and its files.
begin;
select plan(4);

select is(
    public.viewer_board_body(
        '{"blocks": [], "stickerLibrary": [{"fileName": "saved.png", "width": 200, "height": 180}],
          "mediaAssets": {"saved.png": "11111111-1111-1111-1111-111111111111"}}'::jsonb,
        gen_random_uuid()
    ) ? 'stickerLibrary',
    false,
    'visitors never see the saved sticker list'
);

select is(
    public.viewer_board_body(
        '{"blocks": [], "stickerLibrary": [{"fileName": "saved.png", "width": 200, "height": 180}],
          "mediaAssets": {"saved.png": "11111111-1111-1111-1111-111111111111"}}'::jsonb,
        gen_random_uuid()
    ) ? 'mediaAssets',
    false,
    'a file only the saved list mentions is not readable by visitors'
);

select is(
    public.viewer_board_body(
        '{"blocks": [{"kind": "sticker", "mediaFileName": "placed.png"}],
          "stickerLibrary": [{"fileName": "placed.png", "width": 200, "height": 180},
                             {"fileName": "saved.png", "width": 200, "height": 180}],
          "mediaAssets": {"placed.png": "22222222-2222-2222-2222-222222222222",
                          "saved.png": "11111111-1111-1111-1111-111111111111"}}'::jsonb,
        gen_random_uuid()
    ) -> 'mediaAssets',
    '{"placed.png": "22222222-2222-2222-2222-222222222222"}'::jsonb,
    'a sticker placed on the board stays visible; one only in the saved list does not'
);

select is(
    public.viewer_board_body('{"blocks": []}'::jsonb, gen_random_uuid()),
    '{"blocks": []}'::jsonb,
    'boards without saved stickers are unchanged'
);

select * from finish();
rollback;
