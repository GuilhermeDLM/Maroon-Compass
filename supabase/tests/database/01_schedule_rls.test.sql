-- Row-level security, privileges, ownership integrity, and deletion cascades.
-- Run: supabase test db   (or psql -v ON_ERROR_STOP=1 -f this file against a disposable database)
begin;
\ir 00_helpers.sql.inc

select plan(47);

\set user_a '''10000000-0000-0000-0000-00000000000a'''
\set user_b '''10000000-0000-0000-0000-00000000000b'''
\set semester_a '''20000000-0000-0000-0000-00000000000a'''
\set semester_b '''20000000-0000-0000-0000-00000000000b'''

-- ---------------------------------------------------------------- structure and privileges
select ok((select bool_and(relrowsecurity) from pg_class
            where oid in ('public.semesters'::regclass, 'public.courses'::regclass,
                          'public.course_meetings'::regclass, 'public.course_events'::regclass)),
          'RLS is enabled on every schedule table');

select table_privs_are('public', 'semesters', 'anon', array[]::text[], 'anon has no semester privileges');
select table_privs_are('public', 'courses', 'anon', array[]::text[], 'anon has no course privileges');
select table_privs_are('public', 'course_meetings', 'anon', array[]::text[], 'anon has no meeting privileges');
select table_privs_are('public', 'course_events', 'anon', array[]::text[], 'anon has no event privileges');
select table_privs_are('public', 'semesters', 'authenticated', array['SELECT', 'DELETE'],
                       'signed-in users may only read and delete semesters directly');
select table_privs_are('public', 'courses', 'authenticated', array['SELECT'], 'courses are read-only');
select table_privs_are('public', 'course_meetings', 'authenticated', array['SELECT'], 'meetings are read-only');
select table_privs_are('public', 'course_events', 'authenticated', array['SELECT'], 'events are read-only');

select function_privs_are('public', 'replace_schedule_snapshot', array['uuid', 'integer', 'jsonb'],
                          'anon', array[]::text[], 'anon cannot write snapshots');
select function_privs_are('public', 'get_schedule_snapshot', array['uuid'],
                          'anon', array[]::text[], 'anon cannot read snapshots');
select function_privs_are('public', 'list_schedule_semesters', array[]::text[],
                          'anon', array[]::text[], 'anon cannot list semesters');
select function_privs_are('public', 'replace_schedule_snapshot', array['uuid', 'integer', 'jsonb'],
                          'authenticated', array['EXECUTE'], 'signed-in users can write snapshots');

select ok((select prosecdef and proconfig @> array['search_path=""'] from pg_proc
            where oid = 'public.replace_schedule_snapshot(uuid, integer, jsonb)'::regprocedure),
          'snapshot writer is SECURITY DEFINER with an empty search_path');
select ok((select not prosecdef from pg_proc
            where oid = 'public.get_schedule_snapshot(uuid)'::regprocedure),
          'snapshot reader runs as the caller under RLS');
select hasnt_function('public', 'replace_schedule_snapshot',
                      array['uuid', 'integer', 'text', 'date', 'date', 'jsonb'],
                      'the invoker-rights v1 writer was removed');

-- ---------------------------------------------------------------- fixtures through the RPC
select pg_temp.act_as(:user_a);
select is((public.replace_schedule_snapshot(:semester_a, null, pg_temp.snapshot()) ->> 'sync_version')::int,
          1, 'user A creates a cloud schedule');
select pg_temp.act_as(:user_b);
select is((public.replace_schedule_snapshot(:semester_b, null, pg_temp.snapshot('2027-08-30')) ->> 'sync_version')::int,
          1, 'user B creates a cloud schedule');

-- ---------------------------------------------------------------- SELECT isolation (as B)
select results_eq('select id from public.semesters', array[:semester_b::uuid],
                  'B sees only B''s semester');
select is((select count(*)::int from public.courses where semester_id = :semester_a), 0,
          'B cannot read A''s courses');
select is((select count(*)::int from public.course_meetings where semester_id = :semester_a), 0,
          'B cannot read A''s meetings');
select is((select count(*)::int from public.course_events where semester_id = :semester_a), 0,
          'B cannot read A''s events');
select is(public.get_schedule_snapshot(:semester_a), null, 'B cannot read A''s snapshot through the RPC');
select is(jsonb_array_length(public.list_schedule_semesters()), 1, 'B lists only B''s semester');

-- ---------------------------------------------------------------- INSERT / UPDATE / DELETE (as B)
select throws_ok($$ insert into public.semesters (name, first_class_date, last_class_date)
                    values ('Direct', '2028-01-10', '2028-05-01') $$,
                 '42501', null, 'B cannot insert semesters directly, even as the owner');
select throws_ok(format($$ insert into public.courses (semester_id, client_id, position, code, title)
                           values (%L, 'X', 9, 'CHEM 107', 'Chemistry') $$, :semester_a),
                 '42501', null, 'B cannot attach a course to A''s semester');
select throws_ok(format($$ update public.semesters set name = 'Stolen' where id = %L $$, :semester_a),
                 '42501', null, 'B cannot update A''s semester');
select throws_ok($$ update public.course_meetings set room = '999' $$,
                 '42501', null, 'B cannot update meetings directly, even B''s own');
select throws_ok($$ delete from public.courses $$, '42501', null, 'B cannot delete courses directly');
select throws_ok($$ delete from public.course_events $$, '42501', null, 'B cannot delete events directly');
select is(pg_temp.delete_semester(:semester_a, null), 0, 'B''s DELETE of A''s semester matches no rows');

-- ---------------------------------------------------------------- A is unaffected
select pg_temp.act_as(:user_a);
select is((select count(*)::int from public.semesters), 1, 'A still has one semester');
select is((select count(*)::int from public.courses), 2, 'A still has two courses');
select is((select count(*)::int from public.course_meetings), 2, 'A still has two meetings');
select is((select count(*)::int from public.course_events), 1, 'A still has one event');
select is((select name from public.semesters), 'Spring 2027', 'A''s semester name is unchanged');

-- ---------------------------------------------------------------- anon and missing identity
select pg_temp.act_as_anon();
select throws_ok($$ select count(*) from public.semesters $$, '42501', null, 'anon cannot read schedules');
select throws_ok(format($$ select public.replace_schedule_snapshot(%L, null, '{}'::jsonb) $$, :semester_a),
                 '42501', null, 'anon cannot call the snapshot writer');

select pg_temp.act_as_admin();
select set_config('request.jwt.claims', json_build_object('role', 'authenticated')::text, true);
set local role authenticated;
select throws_ok(format($$ select public.replace_schedule_snapshot(%L, null, %L::jsonb) $$,
                        '20000000-0000-0000-0000-0000000000ff', pg_temp.snapshot('2029-01-15')),
                 '28000', 'authentication_required', 'a token without a subject cannot write');

-- ---------------------------------------------------------------- composite ownership keys (as table owner)
select pg_temp.act_as_admin();
select throws_ok(format($$ insert into public.courses (user_id, semester_id, client_id, position, code, title)
                           values (%L, %L, 'X', 9, 'CHEM 107', 'Chemistry') $$, :user_b, :semester_a),
                 '23503', null, 'a course cannot reference another owner''s semester');
select throws_ok(format($$ insert into public.course_meetings
                              (user_id, semester_id, course_id, client_id, position, weekdays, start_time, end_time)
                           select %L, %L, id, 'X', 9, array[1]::smallint[], '08:00', '09:00'
                             from public.courses where semester_id = %L limit 1 $$,
                        :user_a, :semester_b, :semester_a),
                 '23503', null, 'a meeting cannot claim a different semester than its course');
select throws_ok(format($$ insert into public.course_events
                              (user_id, semester_id, course_id, client_id, position, event_date, start_time, end_time, title)
                           select %L, %L, id, 'X', 9, '2027-02-01', '08:00', '09:00', 'Moved'
                             from public.courses where semester_id = %L limit 1 $$,
                        :user_b, :semester_a, :semester_a),
                 '23503', null, 'an event cannot be owned by someone other than its course owner');

-- ---------------------------------------------------------------- versioned semester deletion (as A)
select pg_temp.act_as(:user_a);
select is(pg_temp.delete_semester(:semester_a, 7), 0, 'a DELETE with a stale version matches no rows');
select is(pg_temp.delete_semester(:semester_a, 1), 1, 'A deletes A''s semester at the current version');
select is((select count(*)::int from public.courses) + (select count(*)::int from public.course_meetings)
          + (select count(*)::int from public.course_events), 0,
          'deleting a semester removes its courses, meetings, and events');

-- ---------------------------------------------------------------- account deletion cascade
select pg_temp.act_as_admin();
delete from auth.users where id = :user_b;
select is((select count(*)::int from public.semesters where user_id = :user_b)
          + (select count(*)::int from public.courses where user_id = :user_b)
          + (select count(*)::int from public.course_meetings where user_id = :user_b)
          + (select count(*)::int from public.course_events where user_id = :user_b), 0,
          'deleting an Auth user removes every schedule row it owned');

select pg_temp.act_as(:user_b);
select throws_ok(format($$ select public.replace_schedule_snapshot(%L, null, %L::jsonb) $$,
                        :semester_b, pg_temp.snapshot('2027-08-30')),
                 '28000', 'authentication_required',
                 'a deleted account''s unexpired token cannot write (HTTP 403, not invalid input)');

select * from finish();
rollback;
