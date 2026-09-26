-- Run against a disposable Supabase database after the migration: psql -v ON_ERROR_STOP=1 -f supabase/tests/schedule_rls.sql
-- The transaction rolls back all fixtures. A failing assertion aborts the run.
begin;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values
 ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'maroon-rls-a@example.invalid', '', now(), now(), now()),
 ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'maroon-rls-b@example.invalid', '', now(), now(), now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

insert into public.semesters (id, name, first_class_date, last_class_date)
values ('20000000-0000-0000-0000-000000000001', 'RLS test', '2027-08-30', '2027-12-10');
insert into public.courses (id, semester_id, code, title)
values ('30000000-0000-0000-0000-000000000001',
        '20000000-0000-0000-0000-000000000001', 'MATH 251', 'Calculus III');
insert into public.course_meetings
    (id, course_id, meeting_type, weekdays, start_time, end_time)
values ('40000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000001', 'lecture', array[2,4]::smallint[],
        '17:30', '18:45');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);

do $$
declare changed integer;
begin
    if (select count(*) from public.semesters) <> 0
       or (select count(*) from public.courses) <> 0
       or (select count(*) from public.course_meetings) <> 0 then
        raise exception 'SELECT policy exposed another user''s schedule';
    end if;

    update public.semesters set name = 'Stolen'
     where id = '20000000-0000-0000-0000-000000000001';
    get diagnostics changed = row_count;
    if changed <> 0 then raise exception 'UPDATE policy allowed cross-user change'; end if;

    delete from public.course_meetings
     where id = '40000000-0000-0000-0000-000000000001';
    get diagnostics changed = row_count;
    if changed <> 0 then raise exception 'DELETE policy allowed cross-user change'; end if;

    begin
        insert into public.courses (semester_id, code, title)
        values ('20000000-0000-0000-0000-000000000001', 'CHEM 107', 'Chemistry');
        raise exception 'INSERT accepted another user''s semester';
    exception when foreign_key_violation then null;
    end;

    begin
        insert into public.semesters (user_id, name, first_class_date, last_class_date)
        values ('10000000-0000-0000-0000-000000000001', 'Impersonated',
                '2027-08-30', '2027-12-10');
        raise exception 'INSERT accepted another user_id';
    exception when insufficient_privilege then null;
    end;
end;
$$;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
do $$
begin
    if (select count(*) from public.semesters) <> 1
       or (select count(*) from public.courses) <> 1
       or (select count(*) from public.course_meetings) <> 1 then
        raise exception 'Owner lost access or another user changed data';
    end if;
end;
$$;

rollback;
