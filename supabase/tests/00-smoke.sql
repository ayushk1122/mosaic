-- Minimal local smoke checks that the baseline migration applied.
begin;
select plan(4);

select has_table('public', 'documents', 'documents exists');
select has_table('public', 'profiles', 'profiles exists');
select has_function('public', 'save_document', 'save_document exists');
select has_function('public', 'viewer_can_open_pursuit', 'viewer_can_open_pursuit exists');

select * from finish();
rollback;
