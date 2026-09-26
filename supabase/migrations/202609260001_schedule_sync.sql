-- Schedule sync v2.
--
-- Goals
-- 1. Round-trip every confirmed local schedule shape without loss: the embedded Howdy schedule,
--    .ics imports (EXDATE/RDATE, one-time events, source notes, UNTIL values), and reviewed photo
--    imports. Rows carry the app's own identifiers (client_id) and array order (position) so a
--    restored schedule keeps local building assignments, calendar-export tracking, and ordering.
-- 2. Clients may read their own rows and delete a whole semester. Every other write goes through
--    replace_schedule_snapshot, which bumps sync_version in the same transaction, so a stale
--    device cannot change cloud data without receiving a conflict.
-- 3. Conflicts return HTTP 409 (SQLSTATE PT409) with a stable message; invalid input returns 400.
--
-- Photos, OCR text, and ICS diagnostic properties never enter this schema.
-- Forward-only: 202609250001 is altered here rather than rewritten.

-- ---------------------------------------------------------------------------------------------
-- Helpers outside the exposed API schema.
-- ---------------------------------------------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public;

-- True for a one-dimensional array without NULLs whose elements strictly increase
-- (a sorted set). Used for weekdays and date lists so duplicates cannot be stored.
create function private.is_canonical_set(items anyarray) returns boolean
language sql immutable parallel safe set search_path = '' as $$
    select items is not null
       and coalesce(pg_catalog.array_ndims(items), 1) = 1
       and pg_catalog.array_position(items, null) is null
       and not exists (
           select 1
             from unnest(items) with ordinality as a(item, ord)
             join unnest(items) with ordinality as b(item, ord) on b.ord = a.ord + 1
            where b.item <= a.item
       )
$$;
revoke all on function private.is_canonical_set(anyarray) from public;

-- ---------------------------------------------------------------------------------------------
-- Semesters
-- ---------------------------------------------------------------------------------------------
alter table public.semesters
    add column institution text not null default 'Texas A&M University',
    add column finals_start_date date,
    add column finals_end_date date,
    add column source_name text not null default '',
    add column source_imported_at timestamptz,
    add constraint semester_institution_valid check (length(btrim(institution)) between 1 and 120),
    add constraint semester_campus_valid check (length(btrim(campus)) between 1 and 120),
    add constraint semester_time_zone_valid check (length(time_zone) between 1 and 64),
    add constraint semester_span_valid check (last_class_date - first_class_date <= 400),
    add constraint semester_finals_valid check (
        finals_start_date is null or finals_end_date is null or finals_end_date >= finals_start_date),
    add constraint semester_source_name_valid check (length(source_name) <= 200),
    -- One cloud schedule per term start date per account: a second device cannot silently
    -- create a duplicate copy of the same term under a new ID.
    add constraint semester_owner_term_unique unique (user_id, first_class_date);

-- ---------------------------------------------------------------------------------------------
-- Courses
-- ---------------------------------------------------------------------------------------------
update public.courses set section = '' where section is null;
update public.courses set credits = 0 where credits is null;
update public.courses set color_hex = '5E2E42' where color_hex is null;

alter table public.courses
    add column client_id text,
    add column position integer,
    add column catalog_summary text not null default '',
    add column symbol text not null default 'book.closed.fill',
    add column status text,
    add column crn text,
    add column instruction_mode text,
    add column instructor text;

update public.courses set client_id = id::text where client_id is null;
update public.courses c
   set position = ordered.position
  from (select id, (row_number() over (partition by semester_id order by created_at, id) - 1)::integer as position
          from public.courses) ordered
 where ordered.id = c.id;

alter table public.courses
    alter column client_id set not null,
    alter column position set not null,
    alter column section set default '',
    alter column section set not null,
    alter column credits set default 0,
    alter column credits set not null,
    alter column color_hex set default '5E2E42',
    alter column color_hex set not null,
    add constraint course_client_id_valid check (length(client_id) between 1 and 255),
    add constraint course_position_valid check (position >= 0),
    add constraint course_section_valid check (length(section) <= 40),
    add constraint course_credits_whole check (credits = trunc(credits)),
    add constraint course_color_valid check (color_hex ~ '^[0-9A-Fa-f]{6}$'),
    add constraint course_summary_valid check (length(catalog_summary) <= 2000),
    add constraint course_symbol_valid check (symbol ~ '^[A-Za-z0-9._-]{1,100}$'),
    add constraint course_status_valid check (length(status) <= 80),
    add constraint course_crn_valid check (length(crn) <= 20),
    add constraint course_mode_valid check (length(instruction_mode) <= 120),
    add constraint course_instructor_valid check (length(instructor) <= 200),
    add constraint course_client_unique unique (semester_id, client_id),
    add constraint course_position_unique unique (semester_id, position),
    add constraint course_semester_owner_key unique (id, semester_id, user_id);

-- ---------------------------------------------------------------------------------------------
-- Course meetings (recurring patterns)
-- ---------------------------------------------------------------------------------------------
do $$
begin
    if exists (select 1 from public.course_meetings where start_date is not null or end_date is not null) then
        raise exception 'course_meetings.start_date/end_date contain data; migrate it before applying 202609260001';
    end if;
end;
$$;

alter table public.course_meetings
    drop constraint meeting_dates_valid,
    drop column start_date,
    drop column end_date,
    add column semester_id uuid,
    add column client_id text,
    add column position integer,
    add column source_until_utc text not null default '',
    add column excluded_dates date[] not null default '{}',
    add column additional_dates date[] not null default '{}',
    add column source_location_text text,
    add column source_notes text;

update public.course_meetings m set semester_id = c.semester_id from public.courses c where c.id = m.course_id;
update public.course_meetings set client_id = id::text where client_id is null;
update public.course_meetings m
   set position = ordered.position
  from (select id, (row_number() over (partition by semester_id order by created_at, id) - 1)::integer as position
          from public.course_meetings) ordered
 where ordered.id = m.id;

alter table public.course_meetings
    alter column semester_id set not null,
    alter column client_id set not null,
    alter column position set not null,
    drop constraint meeting_course_owner,
    -- The meeting's semester must be its course's semester, for the same owner.
    add constraint meeting_course_owner foreign key (course_id, semester_id, user_id)
        references public.courses (id, semester_id, user_id) on delete cascade,
    add constraint meeting_client_id_valid check (length(client_id) between 1 and 255),
    add constraint meeting_position_valid check (position >= 0),
    add constraint meeting_weekdays_canonical check (private.is_canonical_set(weekdays)),
    add constraint meeting_whole_minutes check (
        extract(second from start_time) = 0 and extract(second from end_time) = 0
        and end_time < time '24:00'),
    add constraint meeting_until_valid check (length(source_until_utc) <= 64),
    add constraint meeting_excluded_dates_valid check (
        cardinality(excluded_dates) <= 366 and private.is_canonical_set(excluded_dates)),
    add constraint meeting_additional_dates_valid check (
        cardinality(additional_dates) <= 366 and private.is_canonical_set(additional_dates)),
    add constraint meeting_location_text_valid check (length(source_location_text) <= 200),
    add constraint meeting_notes_valid check (length(source_notes) <= 2000),
    add constraint meeting_building_valid check (length(building_code) <= 20),
    add constraint meeting_room_valid check (length(room) <= 40),
    add constraint meeting_client_unique unique (semester_id, client_id),
    add constraint meeting_position_unique unique (semester_id, position);

create index meetings_by_course on public.course_meetings (course_id);

-- ---------------------------------------------------------------------------------------------
-- One-time course events (for example an .ics special session)
-- ---------------------------------------------------------------------------------------------
create table public.course_events (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
    semester_id uuid not null,
    course_id uuid not null,
    client_id text not null check (length(client_id) between 1 and 255),
    position integer not null check (position >= 0),
    event_date date not null,
    start_time time without time zone not null,
    end_time time without time zone not null,
    title text not null check (length(btrim(title)) between 1 and 200),
    source_location_text text check (length(source_location_text) <= 200),
    source_notes text check (length(source_notes) <= 2000),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint event_time_valid check (end_time > start_time),
    constraint event_whole_minutes check (
        extract(second from start_time) = 0 and extract(second from end_time) = 0
        and end_time < time '24:00'),
    constraint event_course_owner foreign key (course_id, semester_id, user_id)
        references public.courses (id, semester_id, user_id) on delete cascade,
    constraint event_client_unique unique (semester_id, client_id),
    constraint event_position_unique unique (semester_id, position)
);

create index events_by_owner_course on public.course_events (user_id, course_id);
create index events_by_course on public.course_events (course_id);

create trigger events_updated_at before update on public.course_events
    for each row execute function public.set_schedule_updated_at();

alter table public.course_events enable row level security;

-- Same owner-only policies as the other schedule tables. INSERT/UPDATE policies are kept as
-- defense in depth even though clients hold no INSERT/UPDATE privilege.
create policy events_select on public.course_events for select to authenticated
    using ((select auth.uid()) = user_id);
create policy events_insert on public.course_events for insert to authenticated
    with check ((select auth.uid()) = user_id);
create policy events_update on public.course_events for update to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy events_delete on public.course_events for delete to authenticated
    using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------------------------
-- Privileges: read own rows, delete a whole semester; all other writes use the RPC.
-- ---------------------------------------------------------------------------------------------
revoke all on public.semesters, public.courses, public.course_meetings, public.course_events
    from anon, authenticated;
grant select on public.semesters, public.courses, public.course_meetings, public.course_events
    to authenticated;
grant delete on public.semesters to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Snapshot write
-- ---------------------------------------------------------------------------------------------
drop function public.replace_schedule_snapshot(uuid, integer, text, date, date, jsonb);

-- SECURITY DEFINER so clients need no INSERT/UPDATE privilege and cannot bypass the version
-- check with direct table writes. The owner is taken only from auth.uid(), never from input, and
-- every statement is scoped to that owner. search_path is empty and all names are qualified.
create function public.replace_schedule_snapshot(
    p_semester_id uuid,
    p_expected_version integer,
    p_snapshot jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_owner uuid := auth.uid();
    v_semester jsonb;
    v_current integer;
    v_next integer;
    v_updated_at timestamptz;
    v_detail text;
begin
    -- A deleted account's access token stays cryptographically valid until it expires.
    -- Report it as an authentication failure (HTTP 403), not as invalid input.
    if v_owner is null or not exists (select 1 from auth.users u where u.id = v_owner) then
        raise exception using errcode = '28000', message = 'authentication_required';
    end if;

    if p_semester_id is null
       or p_expected_version < 1
       or jsonb_typeof(p_snapshot) is distinct from 'object'
       or (p_snapshot ->> 'format') is distinct from '1'
       or jsonb_typeof(p_snapshot -> 'semester') is distinct from 'object'
       or jsonb_typeof(p_snapshot -> 'courses') is distinct from 'array'
       or jsonb_typeof(p_snapshot -> 'meetings') is distinct from 'array'
       or jsonb_typeof(p_snapshot -> 'events') is distinct from 'array' then
        raise exception using errcode = '22023', message = 'invalid_snapshot', detail = 'shape';
    end if;
    if octet_length(p_snapshot::text) > 1000000
       or jsonb_array_length(p_snapshot -> 'courses') not between 1 and 100
       or jsonb_array_length(p_snapshot -> 'meetings') > 500
       or jsonb_array_length(p_snapshot -> 'events') > 1000
       or jsonb_array_length(p_snapshot -> 'meetings') + jsonb_array_length(p_snapshot -> 'events') = 0 then
        raise exception using errcode = '22023', message = 'invalid_snapshot', detail = 'size';
    end if;

    v_semester := p_snapshot -> 'semester';
    if not exists (select 1 from pg_catalog.pg_timezone_names where name = v_semester ->> 'time_zone') then
        raise exception using errcode = '22023', message = 'invalid_snapshot', detail = 'time_zone';
    end if;

    begin
        select s.sync_version into v_current
          from public.semesters s
         where s.id = p_semester_id and s.user_id = v_owner
           for update;

        if not found then
            if p_expected_version is not null then
                raise exception using errcode = 'PT409', message = 'schedule_missing',
                    hint = 'The cloud schedule no longer exists for this account.';
            end if;
            if (select count(*) from public.semesters s where s.user_id = v_owner) >= 20 then
                raise exception using errcode = 'P0001', message = 'semester_limit_reached';
            end if;
            begin
                insert into public.semesters (
                    id, user_id, name, institution, campus, first_class_date, last_class_date,
                    finals_start_date, finals_end_date, time_zone, source_name, source_imported_at,
                    sync_version)
                values (
                    p_semester_id, v_owner, v_semester ->> 'name', v_semester ->> 'institution',
                    v_semester ->> 'campus', (v_semester ->> 'first_class_date')::date,
                    (v_semester ->> 'last_class_date')::date,
                    (v_semester ->> 'finals_start_date')::date, (v_semester ->> 'finals_end_date')::date,
                    v_semester ->> 'time_zone', v_semester ->> 'source_name',
                    (v_semester ->> 'source_imported_at')::timestamptz, 1);
            exception when unique_violation then
                raise exception using errcode = 'PT409', message = 'schedule_exists',
                    hint = 'A cloud schedule for this term already exists. Restore or replace it instead.';
            end;
            v_next := 1;
        else
            if p_expected_version is distinct from v_current then
                raise exception using errcode = 'PT409', message = 'schedule_version_conflict',
                    detail = format('current_version=%s', v_current),
                    hint = 'The cloud schedule changed on another device.';
            end if;
            v_next := v_current + 1;
            begin
                update public.semesters
                   set name = v_semester ->> 'name',
                       institution = v_semester ->> 'institution',
                       campus = v_semester ->> 'campus',
                       first_class_date = (v_semester ->> 'first_class_date')::date,
                       last_class_date = (v_semester ->> 'last_class_date')::date,
                       finals_start_date = (v_semester ->> 'finals_start_date')::date,
                       finals_end_date = (v_semester ->> 'finals_end_date')::date,
                       time_zone = v_semester ->> 'time_zone',
                       source_name = v_semester ->> 'source_name',
                       source_imported_at = (v_semester ->> 'source_imported_at')::timestamptz,
                       sync_version = v_next
                 where id = p_semester_id and user_id = v_owner;
            exception when unique_violation then
                raise exception using errcode = 'PT409', message = 'schedule_exists',
                    hint = 'Another cloud schedule already uses this term start date.';
            end;
            -- Cascades to course_meetings and course_events of this semester only.
            delete from public.courses where semester_id = p_semester_id and user_id = v_owner;
        end if;

        insert into public.courses (
            user_id, semester_id, client_id, position, code, section, title, credits,
            catalog_summary, color_hex, symbol, status, crn, instruction_mode, instructor)
        select v_owner, p_semester_id, c.client_id, (c.ord - 1)::integer, c.code, c.section, c.title,
               c.credits, c.catalog_summary, c.color_hex, c.symbol, c.status, c.crn,
               c.instruction_mode, c.instructor
          from rows from (jsonb_to_recordset(p_snapshot -> 'courses') as (
                   client_id text, code text, section text, title text, credits integer,
                   catalog_summary text, color_hex text, symbol text, status text, crn text,
                   instruction_mode text, instructor text))
               with ordinality as c(client_id, code, section, title, credits, catalog_summary,
                                    color_hex, symbol, status, crn, instruction_mode, instructor, ord);

        insert into public.course_meetings (
            user_id, semester_id, course_id, client_id, position, meeting_type, weekdays,
            start_time, end_time, building_code, room, source_until_utc, excluded_dates,
            additional_dates, source_location_text, source_notes)
        select v_owner, p_semester_id, c.id, m.client_id, (m.ord - 1)::integer, m.meeting_type,
               m.weekdays, m.start_time, m.end_time, m.building_code, m.room, m.source_until_utc,
               m.excluded_dates, m.additional_dates, m.source_location_text, m.source_notes
          from rows from (jsonb_to_recordset(p_snapshot -> 'meetings') as (
                   client_id text, course_client_id text, meeting_type text, weekdays smallint[],
                   start_time time, end_time time, building_code text, room text,
                   source_until_utc text, excluded_dates date[], additional_dates date[],
                   source_location_text text, source_notes text))
               with ordinality as m(client_id, course_client_id, meeting_type, weekdays, start_time,
                                    end_time, building_code, room, source_until_utc, excluded_dates,
                                    additional_dates, source_location_text, source_notes, ord)
          left join public.courses c
            on c.semester_id = p_semester_id and c.user_id = v_owner and c.client_id = m.course_client_id;

        insert into public.course_events (
            user_id, semester_id, course_id, client_id, position, event_date, start_time, end_time,
            title, source_location_text, source_notes)
        select v_owner, p_semester_id, c.id, e.client_id, (e.ord - 1)::integer, e.event_date,
               e.start_time, e.end_time, e.title, e.source_location_text, e.source_notes
          from rows from (jsonb_to_recordset(p_snapshot -> 'events') as (
                   client_id text, course_client_id text, event_date date, start_time time,
                   end_time time, title text, source_location_text text, source_notes text))
               with ordinality as e(client_id, course_client_id, event_date, start_time, end_time,
                                    title, source_location_text, source_notes, ord)
          left join public.courses c
            on c.semester_id = p_semester_id and c.user_id = v_owner and c.client_id = e.course_client_id;
    exception
        -- Constraint and conversion failures are the caller's input, not a conflict. Without this,
        -- PostgREST would report a duplicate client_id (23505) as HTTP 409.
        when integrity_constraint_violation or data_exception then
            get stacked diagnostics v_detail = constraint_name;
            raise exception using errcode = '22023', message = 'invalid_snapshot',
                detail = coalesce(nullif(v_detail, ''), sqlstate);
    end;

    select s.updated_at into v_updated_at
      from public.semesters s
     where s.id = p_semester_id and s.user_id = v_owner;

    return jsonb_build_object(
        'semester_id', p_semester_id,
        'sync_version', v_next,
        'updated_at', to_char(v_updated_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
end;
$$;

revoke all on function public.replace_schedule_snapshot(uuid, integer, jsonb) from public, anon, authenticated;
grant execute on function public.replace_schedule_snapshot(uuid, integer, jsonb) to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Snapshot read: one SQL statement, so the semester and all children come from one database
-- snapshot even while another device is replacing the schedule. Runs as the caller under RLS.
-- Returns NULL when the semester does not exist for the caller.
-- ---------------------------------------------------------------------------------------------
create function public.get_schedule_snapshot(p_semester_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
    select jsonb_build_object(
        'format', 1,
        'semester_id', s.id,
        'sync_version', s.sync_version,
        'updated_at', to_char(s.updated_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'semester', jsonb_build_object(
            'name', s.name,
            'institution', s.institution,
            'campus', s.campus,
            'first_class_date', s.first_class_date,
            'last_class_date', s.last_class_date,
            'finals_start_date', s.finals_start_date,
            'finals_end_date', s.finals_end_date,
            'time_zone', s.time_zone,
            'source_name', s.source_name,
            'source_imported_at',
                to_char(s.source_imported_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')),
        'courses', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'client_id', c.client_id,
                       'code', c.code,
                       'section', c.section,
                       'title', c.title,
                       'credits', c.credits::integer,
                       'catalog_summary', c.catalog_summary,
                       'color_hex', c.color_hex,
                       'symbol', c.symbol,
                       'status', c.status,
                       'crn', c.crn,
                       'instruction_mode', c.instruction_mode,
                       'instructor', c.instructor) order by c.position)
              from public.courses c
             where c.semester_id = s.id and c.user_id = s.user_id), '[]'::jsonb),
        'meetings', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'client_id', m.client_id,
                       'course_client_id', c.client_id,
                       'meeting_type', m.meeting_type,
                       'weekdays', to_jsonb(m.weekdays),
                       'start_time', to_char(m.start_time, 'HH24:MI'),
                       'end_time', to_char(m.end_time, 'HH24:MI'),
                       'building_code', m.building_code,
                       'room', m.room,
                       'source_until_utc', m.source_until_utc,
                       'excluded_dates', to_jsonb(m.excluded_dates),
                       'additional_dates', to_jsonb(m.additional_dates),
                       'source_location_text', m.source_location_text,
                       'source_notes', m.source_notes) order by m.position)
              from public.course_meetings m
              join public.courses c on c.id = m.course_id
             where m.semester_id = s.id and m.user_id = s.user_id), '[]'::jsonb),
        'events', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'client_id', e.client_id,
                       'course_client_id', c.client_id,
                       'event_date', e.event_date,
                       'start_time', to_char(e.start_time, 'HH24:MI'),
                       'end_time', to_char(e.end_time, 'HH24:MI'),
                       'title', e.title,
                       'source_location_text', e.source_location_text,
                       'source_notes', e.source_notes) order by e.position)
              from public.course_events e
              join public.courses c on c.id = e.course_id
             where e.semester_id = s.id and e.user_id = s.user_id), '[]'::jsonb))
      from public.semesters s
     where s.id = p_semester_id and s.user_id = (select auth.uid())
$$;

revoke all on function public.get_schedule_snapshot(uuid) from public, anon, authenticated;
grant execute on function public.get_schedule_snapshot(uuid) to authenticated;

-- Lightweight listing for restore and duplicate checks. Runs as the caller under RLS.
create function public.list_schedule_semesters() returns jsonb
language sql stable security invoker set search_path = '' as $$
    select coalesce(jsonb_agg(jsonb_build_object(
               'semester_id', s.id,
               'name', s.name,
               'first_class_date', s.first_class_date,
               'last_class_date', s.last_class_date,
               'sync_version', s.sync_version,
               'updated_at', to_char(s.updated_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
               'course_count', (select count(*) from public.courses c
                                 where c.semester_id = s.id and c.user_id = s.user_id))
             order by s.first_class_date desc), '[]'::jsonb)
      from public.semesters s
     where s.user_id = (select auth.uid())
$$;

revoke all on function public.list_schedule_semesters() from public, anon, authenticated;
grant execute on function public.list_schedule_semesters() to authenticated;
