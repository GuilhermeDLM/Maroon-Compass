-- Shared fixtures for the schedule pgTAP suites. Included with \ir by each *.test.sql file.
-- Everything runs inside the caller's transaction and is rolled back.

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values
 ('10000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'maroon-test-a@example.invalid', '', now(), now(), now()),
 ('10000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'maroon-test-b@example.invalid', '', now(), now(), now());

-- Switch to the Data API role PostgREST uses for a signed-in user.
create function pg_temp.act_as(p_user uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims',
        json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end;
$$;

create function pg_temp.act_as_anon() returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
    perform set_config('role', 'anon', true);
end;
$$;

create function pg_temp.act_as_admin() returns void language plpgsql as $$
begin
    perform set_config('role', 'postgres', true);
    perform set_config('request.jwt.claims', '', true);
end;
$$;

-- Runs as the current role, so privileges and RLS apply. Returns the number of deleted rows.
create function pg_temp.delete_semester(p_id uuid, p_version integer) returns integer
language plpgsql as $$
declare deleted integer;
begin
    delete from public.semesters where id = p_id and (p_version is null or sync_version = p_version);
    get diagnostics deleted = row_count;
    return deleted;
end;
$$;

-- A representative schedule in the exact format get_schedule_snapshot returns, so a
-- round trip can be compared with jsonb equality.
create function pg_temp.snapshot(p_first date default '2027-01-19',
                                 p_math_title text default 'Engineering Mathematics III')
returns jsonb language sql immutable as $$
    select jsonb_build_object(
        'format', 1,
        'semester', jsonb_build_object(
            'name', 'Spring 2027',
            'institution', 'Texas A&M University',
            'campus', 'College Station',
            'first_class_date', p_first,
            'last_class_date', p_first + 100,
            'finals_start_date', p_first + 105,
            'finals_end_date', p_first + 110,
            'time_zone', 'America/Chicago',
            'source_name', 'pgTAP fixture',
            'source_imported_at', '2026-09-01T12:00:00.123Z'),
        'courses', jsonb_build_array(
            jsonb_build_object(
                'client_id', 'MATH-251-502', 'code', 'MATH 251', 'section', '502',
                'title', p_math_title, 'credits', 3, 'catalog_summary', 'Multivariable calculus.',
                'color_hex', '2B67B2', 'symbol', 'function', 'status', 'Enrolled', 'crn', '11953',
                'instruction_mode', 'Traditional Face-to-Face (F2F)', 'instructor', 'Yang, Yuxuan'),
            jsonb_build_object(
                'client_id', '6F1C3A55-2B7E-4B0C-9F7A-6A3D1E2C4B5A', 'code', 'CHEM 107',
                'section', '', 'title', 'General Chemistry', 'credits', 0, 'catalog_summary', '',
                'color_hex', '5E2E42', 'symbol', 'book.closed.fill', 'status', null, 'crn', null,
                'instruction_mode', null, 'instructor', null)),
        'meetings', jsonb_build_array(
            jsonb_build_object(
                'client_id', 'howdy-11953-weekly', 'course_client_id', 'MATH-251-502',
                'meeting_type', 'lecture', 'weekdays', jsonb_build_array(2, 4),
                'start_time', '17:30', 'end_time', '18:45', 'building_code', 'BLOC', 'room', '169',
                'source_until_utc', '2027-05-01T00:45:00Z',
                'excluded_dates', jsonb_build_array(p_first + 49, p_first + 51),
                'additional_dates', jsonb_build_array(p_first + 90),
                'source_location_text', 'BLOC · 169', 'source_notes', 'Instructor: Yang, Yuxuan'),
            jsonb_build_object(
                'client_id', '0B7D4C1E-9A2F-4E3B-8C6D-5F4A3B2C1D0E',
                'course_client_id', '6F1C3A55-2B7E-4B0C-9F7A-6A3D1E2C4B5A',
                'meeting_type', 'lab', 'weekdays', jsonb_build_array(2),
                'start_time', '11:10', 'end_time', '14:00', 'building_code', null, 'room', null,
                'source_until_utc', '', 'excluded_dates', '[]'::jsonb,
                'additional_dates', '[]'::jsonb, 'source_location_text', null,
                'source_notes', null)),
        'events', jsonb_build_array(
            jsonb_build_object(
                'client_id', 'special-review-1', 'course_client_id', 'MATH-251-502',
                'event_date', p_first + 30, 'start_time', '08:00', 'end_time', '09:00',
                'title', 'Special MATH 251 meeting', 'source_location_text', 'BLOC · 102',
                'source_notes', null)))
$$;
