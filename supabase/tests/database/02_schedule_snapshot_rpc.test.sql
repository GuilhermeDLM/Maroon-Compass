-- Snapshot RPC contract: lossless round trip, optimistic versioning, atomic rollback,
-- validation, and attempts to use the RPC against another account's data.
begin;
\ir 00_helpers.sql.inc

select plan(39);

\set user_a '''10000000-0000-0000-0000-00000000000a'''
\set user_b '''10000000-0000-0000-0000-00000000000b'''
\set semester_a '''20000000-0000-0000-0000-00000000000a'''
\set semester_b '''20000000-0000-0000-0000-00000000000b'''

create function pg_temp.write(p_semester uuid, p_expected integer, p_snapshot jsonb) returns integer
language sql as $$
    select (public.replace_schedule_snapshot(p_semester, p_expected, p_snapshot) ->> 'sync_version')::integer
$$;

create function pg_temp.version_a() returns integer language sql as $$
    select sync_version from public.semesters where id = '20000000-0000-0000-0000-00000000000a'
$$;

-- ---------------------------------------------------------------- create and lossless read
select pg_temp.act_as(:user_a);
select is(pg_temp.write(:semester_a, null, pg_temp.snapshot()), 1, 'first write creates version 1');

select is(public.get_schedule_snapshot(:semester_a) -> 'semester', pg_temp.snapshot() -> 'semester',
          'semester fields round-trip exactly');
select is(public.get_schedule_snapshot(:semester_a) -> 'courses', pg_temp.snapshot() -> 'courses',
          'courses round-trip exactly, in order, with Howdy metadata and nulls');
select is(public.get_schedule_snapshot(:semester_a) -> 'meetings', pg_temp.snapshot() -> 'meetings',
          'meetings round-trip exactly with EXDATE/RDATE, UNTIL, notes, and string IDs');
select is(public.get_schedule_snapshot(:semester_a) -> 'events', pg_temp.snapshot() -> 'events',
          'one-time events round-trip exactly');
select is((public.get_schedule_snapshot(:semester_a) ->> 'sync_version')::int, 1, 'read reports version 1');
select is((public.list_schedule_semesters() -> 0 ->> 'course_count')::int, 2, 'listing reports two courses');

-- ---------------------------------------------------------------- optimistic versioning
select throws_ok(format($$ select pg_temp.write(%L, null, %L) $$, :semester_a, pg_temp.snapshot()),
                 'PT409', 'schedule_version_conflict', 'a replayed create is a version conflict (HTTP 409)');
select throws_ok(format($$ select pg_temp.write(%L, 5, %L) $$, :semester_a, pg_temp.snapshot()),
                 'PT409', 'schedule_version_conflict', 'a wrong expected version is rejected');
select is(pg_temp.version_a(), 1, 'rejected writes leave the version unchanged');

select is(pg_temp.write(:semester_a, 1, pg_temp.snapshot(p_math_title => 'Calculus III')), 2,
          'a write at the current version succeeds and increments the version');
select is(public.get_schedule_snapshot(:semester_a) #>> '{courses,0,title}', 'Calculus III',
          'the new content replaced the old content');
select is((select count(*)::int from public.courses where semester_id = :semester_a), 2,
          'replacement did not duplicate courses');
select throws_ok(format($$ select pg_temp.write(%L, 1, %L) $$, :semester_a, pg_temp.snapshot()),
                 'PT409', 'schedule_version_conflict', 'the device that last saw version 1 now gets a conflict');

-- ---------------------------------------------------------------- atomic rollback on invalid input
select throws_ok(format($$ select pg_temp.write(%L, 2, %L) $$, :semester_a,
                        jsonb_set(pg_temp.snapshot(p_math_title => 'Partial'), '{events,0,end_time}', '"07:00"')),
                 '22023', 'invalid_snapshot', 'an invalid last event rejects the whole snapshot');
select is(pg_temp.version_a(), 2, 'the failed write did not bump the version');
select is(public.get_schedule_snapshot(:semester_a) #>> '{courses,0,title}', 'Calculus III',
          'courses written before the failure were rolled back');
select is((select count(*)::int from public.course_meetings where semester_id = :semester_a), 2,
          'meetings were not deleted by the failed write');

-- ---------------------------------------------------------------- validation (all HTTP 400, never 409)
select throws_ok(format($$ select pg_temp.write(%L, 2, %L) $$, :semester_a,
                        jsonb_set(pg_temp.snapshot(), '{courses,1,client_id}', '"MATH-251-502"')),
                 '22023', 'invalid_snapshot', 'duplicate course IDs are invalid input, not a conflict');
select throws_ok(format($$ select pg_temp.write(%L, 2, %L) $$, :semester_a,
                        jsonb_set(pg_temp.snapshot(), '{meetings,0,weekdays}', '[2,2]')),
                 '22023', 'invalid_snapshot', 'duplicate weekdays are rejected');
select throws_ok(format($$ select pg_temp.write(%L, 2, %L) $$, :semester_a,
                        jsonb_set(pg_temp.snapshot(), '{meetings,0,weekdays}', '[4,2]')),
                 '22023', 'invalid_snapshot', 'unsorted weekdays are rejected');
select throws_ok(format($$ select pg_temp.write(%L, 2, %L) $$, :semester_a,
                        jsonb_set(pg_temp.snapshot(), '{meetings,0,weekdays}', '[8]')),
                 '22023', 'invalid_snapshot', 'weekday 8 is rejected');
select throws_ok(format($$ select pg_temp.write(%L, 2, %L) $$, :semester_a,
                        jsonb_set(pg_temp.snapshot(), '{meetings,0,excluded_dates}', '["2027-03-11","2027-03-09"]')),
                 '22023', 'invalid_snapshot', 'unsorted exclusion dates are rejected');
select throws_ok(format($$ select pg_temp.write(%L, 2, %L) $$, :semester_a,
                        jsonb_set(pg_temp.snapshot(), '{meetings,0,course_client_id}', '"NOT-A-COURSE"')),
                 '22023', 'invalid_snapshot', 'a meeting must reference a course in the snapshot');
select throws_ok(format($$ select pg_temp.write(%L, 2, %L) $$, :semester_a,
                        jsonb_set(pg_temp.snapshot(), '{meetings,0,start_time}', '"17:30:30"')),
                 '22023', 'invalid_snapshot', 'times with seconds are rejected instead of truncated');
select throws_ok(format($$ select pg_temp.write(%L, 2, %L) $$, :semester_a,
                        jsonb_set(pg_temp.snapshot(), '{semester,time_zone}', '"Mars/Olympus"')),
                 '22023', 'invalid_snapshot', 'an unknown time zone is rejected');
select throws_ok(format($$ select pg_temp.write(%L, 2, %L) $$, :semester_a,
                        jsonb_set(pg_temp.snapshot(), '{courses,0,credits}', '3.5')),
                 '22023', 'invalid_snapshot', 'fractional credits are rejected (the app stores whole credits)');
select throws_ok(format($$ select pg_temp.write(%L, 2, %L) $$, :semester_a,
                        pg_temp.snapshot() - 'format'),
                 '22023', 'invalid_snapshot', 'a snapshot without a format version is rejected');
select throws_ok(format($$ select pg_temp.write(%L, 2, %L) $$, :semester_a,
                        jsonb_set(pg_temp.snapshot(), '{courses}',
                                  (select jsonb_agg(jsonb_set(pg_temp.snapshot() #> '{courses,0}', '{client_id}', to_jsonb('C' || n)))
                                     from generate_series(1, 101) n))),
                 '22023', 'invalid_snapshot', 'more than 100 courses is rejected');
select is(pg_temp.version_a(), 2, 'no invalid write changed the version');

-- ---------------------------------------------------------------- duplicate terms and missing rows
select throws_ok(format($$ select pg_temp.write(%L, null, %L) $$,
                        '20000000-0000-0000-0000-0000000000a2', pg_temp.snapshot()),
                 'PT409', 'schedule_exists', 'a second device cannot create a duplicate copy of the same term');
select throws_ok(format($$ select pg_temp.write(%L, 3, %L) $$,
                        '20000000-0000-0000-0000-0000000000a3', pg_temp.snapshot('2031-01-13')),
                 'PT409', 'schedule_missing', 'an expected version for a missing semester is a conflict');

-- ---------------------------------------------------------------- the RPC cannot reach another account
select pg_temp.act_as(:user_b);
select throws_ok(format($$ select pg_temp.write(%L, null, %L) $$, :semester_a, pg_temp.snapshot('2032-01-12')),
                 'PT409', 'schedule_exists', 'B cannot create a semester with A''s semester ID');
select throws_ok(format($$ select pg_temp.write(%L, 2, %L) $$, :semester_a, pg_temp.snapshot('2032-01-12')),
                 'PT409', 'schedule_missing', 'B cannot overwrite A''s semester with A''s current version');
select is(pg_temp.write(:semester_b, null, pg_temp.snapshot()), 1,
          'B can store the same term and client IDs independently of A');

select pg_temp.act_as(:user_a);
select is(pg_temp.version_a(), 2, 'A''s version is unchanged after B''s attempts');
select is(public.get_schedule_snapshot(:semester_a) #>> '{courses,0,title}', 'Calculus III',
          'A''s content is unchanged after B''s attempts');

-- ---------------------------------------------------------------- per-account semester limit
select lives_ok($$ select pg_temp.write(gen_random_uuid(), null, pg_temp.snapshot(('2040-01-01'::date + n * 7))) from generate_series(1, 19) n $$,
                'A can store up to twenty semesters');
select throws_ok($$ select pg_temp.write(gen_random_uuid(), null, pg_temp.snapshot('2050-01-03')) $$,
                 'P0001', 'semester_limit_reached', 'a twenty-first semester is rejected');

select * from finish();
rollback;
