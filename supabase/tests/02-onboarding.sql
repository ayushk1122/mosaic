-- Onboarding schema, grants, and birthday validation.
begin;
select plan(10);

select hasnt_function('public', 'email_for_login', array['text'], 'usernames cannot be resolved to emails over the API');

select has_function('public', 'onboarding_status', 'onboarding_status exists');
select has_function('public', 'complete_onboarding', 'complete_onboarding exists');
select has_function('public', 'update_private_birthday', 'update_private_birthday exists');
select has_table('public', 'profile_private', 'profile_private exists');

select ok(
    not has_table_privilege('authenticated', 'public.profile_private', 'INSERT'),
    'authenticated cannot insert profile_private directly'
);
select ok(
    not has_table_privilege('authenticated', 'public.profile_private', 'UPDATE'),
    'authenticated cannot update profile_private directly'
);

select ok(
    (select column_default is null
       from information_schema.columns
      where table_schema = 'public'
        and table_name = 'profiles'
        and column_name = 'onboarded_at'),
    'new profiles start without onboarded_at'
);

do $$
begin
    perform public.validate_birthday('1990-06-15'::date);
    begin
        perform public.validate_birthday(current_date + 1);
        raise exception 'future birthday should fail';
    exception
        when others then
            if sqlerrm not ilike '%past%' and sqlerrm not ilike '%22023%' then
                raise;
            end if;
    end;
end $$;

select pass('validate_birthday rejects future dates');

select ok(
    (select count(*) = 1
       from information_schema.columns
      where table_schema = 'public'
        and table_name = 'profiles'
        and column_name = 'onboarded_at'),
    'profiles.onboarded_at column exists'
);

select * from finish();
rollback;
