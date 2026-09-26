-- Confirmed schedule data only. Imported images and OCR text never enter this schema.
-- Every child has a composite FK so a client cannot attach its row to another user's parent.

create table public.semesters (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
    name text not null check (length(btrim(name)) between 1 and 120),
    campus text not null default 'College Station',
    first_class_date date not null,
    last_class_date date not null,
    time_zone text not null default 'America/Chicago',
    sync_version integer not null default 0 check (sync_version >= 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint semester_dates_valid check (last_class_date >= first_class_date),
    constraint semester_owner_key unique (id, user_id)
);

create table public.courses (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
    semester_id uuid not null,
    code text not null check (length(btrim(code)) between 1 and 40),
    title text not null check (length(btrim(title)) between 1 and 200),
    section text,
    credits numeric(4,1) check (credits >= 0 and credits <= 30),
    color_hex text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    -- Target of the course_meetings composite foreign key. Without it this migration fails
    -- with SQLSTATE 42830, so no database can contain an earlier version of this file.
    constraint course_owner_key unique (id, user_id),
    constraint course_semester_owner foreign key (semester_id, user_id)
        references public.semesters (id, user_id) on delete cascade
);

create table public.course_meetings (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
    course_id uuid not null,
    meeting_type text not null default 'lecture'
        check (meeting_type in ('lecture', 'lab', 'recitation', 'other')),
    weekdays smallint[] not null
        check (cardinality(weekdays) between 1 and 7
            and weekdays <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[]),
    start_time time without time zone not null,
    end_time time without time zone not null,
    building_code text,
    room text,
    start_date date,
    end_date date,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint meeting_time_valid check (end_time > start_time),
    constraint meeting_dates_valid check (end_date is null or start_date is null or end_date >= start_date),
    constraint meeting_course_owner foreign key (course_id, user_id)
        references public.courses (id, user_id) on delete cascade
);

create index semesters_by_owner on public.semesters (user_id, first_class_date);
create index courses_by_owner_semester on public.courses (user_id, semester_id);
create index meetings_by_owner_course on public.course_meetings (user_id, course_id);

create function public.set_schedule_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger semesters_updated_at before update on public.semesters
    for each row execute function public.set_schedule_updated_at();
create trigger courses_updated_at before update on public.courses
    for each row execute function public.set_schedule_updated_at();
create trigger meetings_updated_at before update on public.course_meetings
    for each row execute function public.set_schedule_updated_at();

alter table public.semesters enable row level security;
alter table public.courses enable row level security;
alter table public.course_meetings enable row level security;

revoke all on public.semesters, public.courses, public.course_meetings from anon;
revoke all on public.semesters, public.courses, public.course_meetings from authenticated;
grant select, insert, update, delete on public.semesters, public.courses, public.course_meetings to authenticated;

create policy semesters_select on public.semesters for select to authenticated
    using ((select auth.uid()) = user_id);
create policy semesters_insert on public.semesters for insert to authenticated
    with check ((select auth.uid()) = user_id);
create policy semesters_update on public.semesters for update to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy semesters_delete on public.semesters for delete to authenticated
    using ((select auth.uid()) = user_id);

create policy courses_select on public.courses for select to authenticated
    using ((select auth.uid()) = user_id);
create policy courses_insert on public.courses for insert to authenticated
    with check ((select auth.uid()) = user_id);
create policy courses_update on public.courses for update to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy courses_delete on public.courses for delete to authenticated
    using ((select auth.uid()) = user_id);

create policy meetings_select on public.course_meetings for select to authenticated
    using ((select auth.uid()) = user_id);
create policy meetings_insert on public.course_meetings for insert to authenticated
    with check ((select auth.uid()) = user_id);
create policy meetings_update on public.course_meetings for update to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy meetings_delete on public.course_meetings for delete to authenticated
    using ((select auth.uid()) = user_id);

-- One transaction replaces a reviewed schedule. The expected version prevents
-- a stale device from silently overwriting newer edits. RLS still applies
-- because this function runs with the caller's privileges.
create function public.replace_schedule_snapshot(
    p_semester_id uuid,
    p_expected_version integer,
    p_name text,
    p_first_class_date date,
    p_last_class_date date,
    p_courses jsonb
) returns integer language plpgsql security invoker set search_path = '' as $$
declare
    owner_id uuid := (select auth.uid());
    current_version integer;
    next_version integer;
    course_item jsonb;
    meeting_item jsonb;
    course_id uuid;
begin
    if owner_id is null then
        raise exception 'Authentication required' using errcode = '28000';
    end if;
    if jsonb_typeof(p_courses) is distinct from 'array' then
        raise exception 'Invalid course list' using errcode = '22023';
    end if;
    if jsonb_array_length(p_courses) not between 1 and 100 then
        raise exception 'Invalid course list' using errcode = '22023';
    end if;

    select sync_version into current_version
      from public.semesters
     where id = p_semester_id and user_id = owner_id
     for update;

    if not found then
        if p_expected_version is not null then
            raise exception 'Schedule version conflict' using errcode = '40001';
        end if;
        insert into public.semesters
            (id, user_id, name, first_class_date, last_class_date, sync_version)
        values
            (p_semester_id, owner_id, p_name, p_first_class_date, p_last_class_date, 1);
        next_version := 1;
    else
        if p_expected_version is distinct from current_version then
            raise exception 'Schedule version conflict' using errcode = '40001';
        end if;
        next_version := current_version + 1;
        update public.semesters
           set name = p_name,
               first_class_date = p_first_class_date,
               last_class_date = p_last_class_date,
               sync_version = next_version
         where id = p_semester_id and user_id = owner_id;
    end if;

    delete from public.courses
     where semester_id = p_semester_id and user_id = owner_id;

    for course_item in select value from jsonb_array_elements(p_courses) loop
        course_id := (course_item ->> 'id')::uuid;
        insert into public.courses
            (id, user_id, semester_id, code, title, section, credits, color_hex)
        values
            (course_id, owner_id, p_semester_id,
             course_item ->> 'code', course_item ->> 'title',
             course_item ->> 'section', (course_item ->> 'credits')::numeric,
             course_item ->> 'color_hex');

        if jsonb_typeof(course_item -> 'meetings') is distinct from 'array' then
            raise exception 'Invalid meetings list' using errcode = '22023';
        end if;
        if jsonb_array_length(course_item -> 'meetings') not between 1 and 30 then
            raise exception 'Invalid meetings list' using errcode = '22023';
        end if;
        for meeting_item in select value from jsonb_array_elements(course_item -> 'meetings') loop
            insert into public.course_meetings
                (id, user_id, course_id, meeting_type, weekdays, start_time,
                 end_time, building_code, room)
            values
                ((meeting_item ->> 'id')::uuid, owner_id, course_id,
                 meeting_item ->> 'meeting_type',
                 array(select value::smallint from jsonb_array_elements_text(meeting_item -> 'weekdays')),
                 (meeting_item ->> 'start_time')::time,
                 (meeting_item ->> 'end_time')::time,
                 meeting_item ->> 'building_code', meeting_item ->> 'room');
        end loop;
    end loop;
    return next_version;
end;
$$;

revoke all on function public.replace_schedule_snapshot(uuid, integer, text, date, date, jsonb)
    from public, anon;
grant execute on function public.replace_schedule_snapshot(uuid, integer, text, date, date, jsonb)
    to authenticated;
