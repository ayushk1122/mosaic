-- Adversarial checks for SEC-01/02/03 write lockdown and ownership binds.
begin;
select plan(14);

select has_function('public', 'delete_documents', 'delete_documents RPC exists');
select has_function('public', 'finalize_media_asset', 'finalize_media_asset RPC exists');
select has_function('public', 'save_document', 'save_document still exists');

select ok(
    not has_table_privilege('authenticated', 'public.documents', 'INSERT'),
    'authenticated cannot insert documents directly'
);
select ok(
    not has_table_privilege('authenticated', 'public.documents', 'UPDATE'),
    'authenticated cannot update documents directly'
);
select ok(
    not has_table_privilege('authenticated', 'public.documents', 'DELETE'),
    'authenticated cannot delete documents directly'
);
select ok(
    has_table_privilege('authenticated', 'public.documents', 'SELECT'),
    'authenticated can still select documents'
);

select ok(
    not has_table_privilege('authenticated', 'public.media_assets', 'INSERT'),
    'authenticated cannot insert media_assets directly'
);
select ok(
    not has_table_privilege('authenticated', 'public.media_assets', 'UPDATE'),
    'authenticated cannot update media_assets directly'
);

select ok(
    not has_table_privilege('authenticated', 'public.pursuit_access_requests', 'INSERT'),
    'authenticated cannot insert pursuit access requests directly'
);
select ok(
    not has_table_privilege('authenticated', 'public.pursuit_access_requests', 'UPDATE'),
    'authenticated cannot update pursuit access requests directly'
);
select ok(
    not has_table_privilege('authenticated', 'public.mosaic_access_requests', 'UPDATE'),
    'authenticated cannot update mosaic access requests directly'
);

-- Three-account bind: forged owner_id on insert is rewritten to the Pursuit's real owner.
do $$
declare
    owner_a uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    requester_b uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    victim_c uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
    mosaic_a uuid := '11111111-1111-1111-1111-111111111111';
    pursuit_a uuid := '22222222-2222-2222-2222-222222222222';
    mosaic_c uuid := '33333333-3333-3333-3333-333333333333';
    pursuit_c uuid := '44444444-4444-4444-4444-444444444444';
    request_id uuid;
begin
    insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
        confirmation_token, recovery_token, email_change_token_new, email_change
    ) values
        ('00000000-0000-0000-0000-000000000000', owner_a, 'authenticated', 'authenticated',
         'owner-a@example.com', crypt('x', gen_salt('bf')), now(),
         '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
        ('00000000-0000-0000-0000-000000000000', requester_b, 'authenticated', 'authenticated',
         'requester-b@example.com', crypt('x', gen_salt('bf')), now(),
         '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
        ('00000000-0000-0000-0000-000000000000', victim_c, 'authenticated', 'authenticated',
         'victim-c@example.com', crypt('x', gen_salt('bf')), now(),
         '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');

    insert into public.documents (id, owner_id, parent_id, role, title, visibility, body, revision)
    values
        (mosaic_a, owner_a, null, 'mosaic', 'A', 'private', '{"blocks":[]}'::jsonb, 1),
        (pursuit_a, owner_a, mosaic_a, 'pursuit', 'A Pursuit', 'private', '{"blocks":[]}'::jsonb, 1),
        (mosaic_c, victim_c, null, 'mosaic', 'C', 'private', '{"blocks":[]}'::jsonb, 1),
        (pursuit_c, victim_c, mosaic_c, 'pursuit', 'C Pursuit', 'private', '{"blocks":[]}'::jsonb, 1);

    -- Insert names victim C as owner while targeting A's Pursuit; trigger must bind to A.
    insert into public.pursuit_access_requests (id, pursuit_id, owner_id, requester_id, status)
    values (gen_random_uuid(), pursuit_a, victim_c, requester_b, 'pending')
    returning id into request_id;

    if (select owner_id from public.pursuit_access_requests where id = request_id) is distinct from owner_a then
        raise exception 'owner bind failed';
    end if;

    -- Identity columns are immutable after insert.
    begin
        update public.pursuit_access_requests
           set pursuit_id = pursuit_c
         where id = request_id;
        raise exception 'pursuit_id rewrite should have failed';
    exception
        when others then
            if sqlerrm not ilike '%immutable%' and sqlerrm not ilike '%request identity%' then
                raise;
            end if;
    end;
end $$;

select pass('pursuit request owner bind + immutable identity');

select ok(
    (
        select file_size_limit = 26214400
          and allowed_mime_types @> array['image/jpeg', 'video/mp4']::text[]
        from storage.buckets
        where id = 'media'
    ),
    'media bucket enforces size and mime limits'
);

select * from finish();
rollback;
