-- Apply after the existing attendance, exam and anti-proxy schemas.
-- Additive migration: no existing enrollments, sessions, exams or devices are deleted.
begin;

create table if not exists public.school_curricula (
  id uuid primary key default gen_random_uuid(),
  program text not null check (program in ('ICT','GAS','EIM','HE','HUMSS')),
  grade integer not null check (grade in (11,12)),
  version text not null,
  approved boolean not null default false,
  unique(program,grade,version)
);
create table if not exists public.school_curriculum_subjects (
  curriculum_id uuid not null references public.school_curricula(id),
  subject_id uuid not null references public.subjects(id),
  semester integer check (semester in (0,1,2)), -- 0 = full year; NULL = unconfirmed draft
  primary key(curriculum_id,subject_id)
);
create table if not exists public.school_sections (
  id uuid primary key default gen_random_uuid(),
  section_id uuid not null unique references public.sections(id),
  school_year text not null check (school_year ~ '^[0-9]{4}-[0-9]{4}$'),
  grade integer not null check (grade in (11,12)),
  program text not null check (program in ('ICT','GAS','EIM','HE','HUMSS')),
  capacity integer not null default 45 check (capacity between 1 and 100),
  adviser_id uuid references public.teachers(id),
  created_at timestamptz not null default now()
);
create table if not exists public.school_section_terms (
  id uuid primary key default gen_random_uuid(),
  school_section_id uuid not null references public.school_sections(id),
  curriculum_id uuid not null references public.school_curricula(id),
  semester integer not null check (semester in (1,2)),
  ready boolean not null default false,
  closed boolean not null default false,
  unique(school_section_id,semester)
);
alter table public.school_section_terms add column if not exists closed boolean not null default false;
create table if not exists public.school_teaching_assignments (
  term_id uuid not null references public.school_section_terms(id),
  subject_id uuid not null references public.subjects(id),
  offering_id uuid not null unique references public.subject_offerings(id),
  primary key(term_id,subject_id)
);
create table if not exists public.school_student_requests (
  student_id uuid primary key references public.students(id),
  requested_grade integer not null check (requested_grade in (11,12)),
  requested_program text not null check (requested_program in ('ICT','GAS','EIM','HE','HUMSS')),
  created_at timestamptz not null default now()
);
create table if not exists public.school_section_placements (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id),
  school_section_id uuid not null references public.school_sections(id),
  school_year text not null,
  created_at timestamptz not null default now(),
  unique(student_id,school_year)
);
create index if not exists school_placements_section on public.school_section_placements(school_section_id);

-- Public metadata reads follow this app's existing custom-login read model.
-- New tables do not grant client write access. Mutations require verified admin credentials.
do $$ declare t text; begin
  foreach t in array array['school_curricula','school_curriculum_subjects','school_sections',
    'school_section_terms','school_teaching_assignments','school_student_requests','school_section_placements'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from anon, authenticated',t);
    execute format('grant select on public.%I to anon, authenticated',t);
    execute format('drop policy if exists school_metadata_read on public.%I',t);
    execute format('create policy school_metadata_read on public.%I for select to anon, authenticated using (true)',t);
  end loop;
end $$;

-- Wrapper preserves the installed register_student implementation and its device arguments.
-- Account and request are written together; login still uses app_student_login_with_device.
create or replace function public.register_student_with_section_request(
  p_student_id text,p_full_name text,p_username text,p_password text,
  p_device_uuid text,p_device_name text,p_requested_grade integer,p_requested_program text
) returns text language plpgsql security definer set search_path = public, extensions as $$
declare v_id text; begin
  if p_requested_grade not in (11,12) or p_requested_grade is null or
    p_requested_program is null or p_requested_program not in ('ICT','GAS','EIM','HE','HUMSS') then
    raise exception 'Select your requested grade and program.';
  end if;
  if nullif(trim(p_username),'') is null or nullif(trim(p_full_name),'') is null or
    nullif(trim(p_password),'') is null then raise exception 'Complete the registration fields.'; end if;
  -- A registration request must never change another existing account's preferences.
  if exists(select 1 from public.students where email = trim(p_username)) then
    raise exception 'This username is already registered. Please sign in.';
  end if;
  if to_regprocedure('public.register_student(text,text,text,text,text,text)') is not null then
    v_id := public.register_student(p_student_id,p_full_name,p_username,p_password,p_device_uuid,p_device_name);
  elsif to_regprocedure('public.register_student(text,text,text,text)') is not null then
    -- Matches the application's existing older-schema fallback; subsequent
    -- login still goes through the installed secure device-binding function.
    v_id := public.register_student(p_student_id,p_full_name,p_username,p_password);
  else
    raise exception 'The existing student registration setup is missing.';
  end if;
  if not exists(select 1 from public.students where id=v_id::uuid
    and password_hash=extensions.crypt(trim(p_password),password_hash)) then
    raise exception 'This username is already registered. Please sign in.';
  end if;
  insert into public.school_student_requests(student_id,requested_grade,requested_program)
    values(v_id::uuid,p_requested_grade,p_requested_program);
  return v_id;
end $$;
revoke all on function public.register_student_with_section_request(text,text,text,text,text,text,integer,text) from public;
grant execute on function public.register_student_with_section_request(text,text,text,text,text,text,integer,text) to anon, authenticated;

-- Atomic administrative operations. Passwords are checked, never stored by these functions.
create or replace function public.admin_school_command(
  p_username text,p_password text,p_action text,p_data jsonb
) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id uuid; v_section public.school_sections%rowtype;
  v_term public.school_section_terms%rowtype; v_curr public.school_curricula%rowtype;
  v_subject uuid; v_teacher uuid; v_offering uuid; v_student uuid; v_students uuid[];
  v_legacy uuid; v_count integer; v_expected integer; v_name text; v_year text;
begin
  if not exists(select 1 from public.admins a where a.email=trim(p_username)
    and a.password_hash=extensions.crypt(trim(p_password),a.password_hash)) then
    raise exception 'Administrator credentials are required.' using errcode='42501';
  end if;
  if p_action in ('curriculum_subject','remove_curriculum_subject') then
    select * into strict v_curr from public.school_curricula where id=(p_data->>'curriculum_id')::uuid for update;
    if v_curr.approved then raise exception 'Approved curricula are frozen. Create a new version.'; end if;
    v_subject := (p_data->>'subject_id')::uuid;
    if p_action='remove_curriculum_subject' then
      delete from public.school_curriculum_subjects where curriculum_id=v_curr.id and subject_id=v_subject;
    elsif p_data->>'semester' is null and coalesce((p_data->>'add')::boolean,false) then
      insert into public.school_curriculum_subjects(curriculum_id,subject_id) values(v_curr.id,v_subject)
        on conflict(curriculum_id,subject_id) do nothing;
    elsif p_data->>'semester' is null then
      update public.school_curriculum_subjects set semester=null where curriculum_id=v_curr.id and subject_id=v_subject;
    else
      insert into public.school_curriculum_subjects values(v_curr.id,v_subject,(p_data->>'semester')::integer)
        on conflict(curriculum_id,subject_id) do update set semester=excluded.semester;
    end if;
    return jsonb_build_object('id',v_curr.id);
  elsif p_action='create_curriculum' then
    if nullif(trim(p_data->>'version'),'') is null then raise exception 'Enter a curriculum version name.'; end if;
    insert into public.school_curricula(program,grade,version)
      values(p_data->>'program',(p_data->>'grade')::integer,trim(p_data->>'version')) returning id into v_id;
    if nullif(p_data->>'copy_id','') is not null then
      insert into public.school_curriculum_subjects(curriculum_id,subject_id,semester)
        select v_id,subject_id,semester from public.school_curriculum_subjects where curriculum_id=(p_data->>'copy_id')::uuid;
    end if;
    return jsonb_build_object('id',v_id);
  elsif p_action='approve_curriculum' then
    select * into strict v_curr from public.school_curricula where id=(p_data->>'id')::uuid for update;
    if not exists(select 1 from public.school_curriculum_subjects where curriculum_id=v_curr.id) or
       exists(select 1 from public.school_curriculum_subjects where curriculum_id=v_curr.id and semester is null) then
      raise exception 'Confirm the semester of every draft subject before approval.';
    end if;
    update public.school_curricula set approved=true where id=v_curr.id;
    return jsonb_build_object('id',v_curr.id);
  elsif p_action='create_section' then
    v_year:=trim(p_data->>'school_year');
    if v_year !~ '^[0-9]{4}-[0-9]{4}$' or split_part(v_year,'-',2)::int<>split_part(v_year,'-',1)::int+1 then
      raise exception 'Use consecutive years, for example 2026-2027.'; end if;
    if nullif(trim(p_data->>'name'),'') is null then raise exception 'Enter a section name.'; end if;
    -- Separate legacy section IDs by school year: historical offerings remain intact.
    v_name:=trim(p_data->>'name') || ' (' || v_year || ')';
    insert into public.sections(section_name) values(v_name) returning id into v_legacy;
    insert into public.school_sections(section_id,school_year,grade,program,capacity,adviser_id)
      values(v_legacy,v_year,(p_data->>'grade')::int,p_data->>'program',
        (p_data->>'capacity')::int,nullif(p_data->>'adviser_id','')::uuid) returning id into v_id;
    return jsonb_build_object('id',v_id);
  elsif p_action='create_term' then
    select * into strict v_section from public.school_sections where id=(p_data->>'section_id')::uuid for update;
    select * into strict v_curr from public.school_curricula where id=(p_data->>'curriculum_id')::uuid;
    if not v_curr.approved or v_curr.grade<>v_section.grade or v_curr.program<>v_section.program then
      raise exception 'Select an approved curriculum matching this section.'; end if;
    insert into public.school_section_terms(school_section_id,curriculum_id,semester)
      values(v_section.id,v_curr.id,(p_data->>'semester')::int) returning id into v_id;
    return jsonb_build_object('id',v_id);
  elsif p_action='assign_teacher' then
    select * into strict v_term from public.school_section_terms where id=(p_data->>'term_id')::uuid for update;
    if v_term.ready or v_term.closed then raise exception 'Ready teaching assignments are frozen to preserve class and exam ownership.'; end if;
    select * into strict v_section from public.school_sections where id=v_term.school_section_id;
    v_subject:=(p_data->>'subject_id')::uuid; v_teacher:=(p_data->>'teacher_id')::uuid;
    if not exists(select 1 from public.school_curriculum_subjects where curriculum_id=v_term.curriculum_id
      and subject_id=v_subject and semester in (0,v_term.semester)) then raise exception 'Subject is not in this semester.'; end if;
    select offering_id into v_offering from public.school_teaching_assignments where term_id=v_term.id and subject_id=v_subject;
    if v_offering is null then
      insert into public.subject_offerings(subject_id,teacher_id,section_id,school_year,semester,beacon_uuid,beacon_name,is_active)
        select v_subject,v_teacher,v_section.section_id,v_section.school_year,v_term.semester::text,
          gen_random_uuid()::text,s.subject_code || ' - ' || se.section_name,false
        from public.subjects s,public.sections se where s.id=v_subject and se.id=v_section.section_id returning id into v_offering;
      insert into public.school_teaching_assignments values(v_term.id,v_subject,v_offering);
    else
      update public.subject_offerings set teacher_id=v_teacher where id=v_offering;
    end if;
    return jsonb_build_object('id',v_offering);
  elsif p_action='ready_term' then
    select * into strict v_term from public.school_section_terms where id=(p_data->>'id')::uuid for update;
    if v_term.closed then raise exception 'This semester is closed.'; end if;
    select count(*) into v_expected from public.school_curriculum_subjects where curriculum_id=v_term.curriculum_id and semester in (0,v_term.semester);
    select count(*) into v_count from public.school_teaching_assignments where term_id=v_term.id;
    if v_expected=0 or v_count<>v_expected then raise exception 'Assign a teacher to every subject before making this semester ready.'; end if;
    update public.subject_offerings set is_active=true where id in(select offering_id from public.school_teaching_assignments where term_id=v_term.id);
    update public.school_section_terms set ready=true where id=v_term.id;
    return jsonb_build_object('id',v_term.id);
  elsif p_action='close_term' then
    select * into strict v_term from public.school_section_terms where id=(p_data->>'id')::uuid for update;
    -- Lock offerings before checking: session/exam inserts referencing them wait.
    perform id from public.subject_offerings where id in
      (select offering_id from public.school_teaching_assignments where term_id=v_term.id) order by id for update;
    if exists(select 1 from public.attendance_sessions s join public.school_teaching_assignments a on a.offering_id=s.subject_offering_id
      where a.term_id=v_term.id and s.is_active) or exists
      (select 1 from public.exam_sessions s join public.school_teaching_assignments a on a.offering_id=s.subject_offering_id
       where a.term_id=v_term.id and s.status in ('active','paused')) then
      raise exception 'End active attendance sessions and exams before closing this semester.';
    end if;
    update public.school_section_terms set closed=true where id=v_term.id;
    update public.subject_offerings set is_active=false where id in
      (select offering_id from public.school_teaching_assignments where term_id=v_term.id);
    return jsonb_build_object('id',v_term.id);
  elsif p_action='enroll' then
    select * into strict v_term from public.school_section_terms where id=(p_data->>'term_id')::uuid for update;
    select * into strict v_section from public.school_sections where id=v_term.school_section_id for update;
    if not v_term.ready or v_term.closed then raise exception 'This semester is not ready for enrollment.'; end if;
    select array_agg(distinct value::uuid order by value::uuid) into v_students
      from jsonb_array_elements_text(p_data->'student_ids');
    if coalesce(cardinality(v_students),0)=0 or cardinality(v_students)>100 then raise exception 'Choose 1 to 100 students.'; end if;
    -- Stable student lock order prevents competing placements across sections.
    perform id from public.students where id=any(v_students) order by id for update;
    if (select count(*) from public.students where id=any(v_students))<>cardinality(v_students) then raise exception 'A selected student no longer exists.'; end if;
    if exists(select 1 from public.school_section_placements where student_id=any(v_students)
      and school_year=v_section.school_year and school_section_id<>v_section.id) then
      raise exception 'A student already has a section this school year. Review their placement first.'; end if;
    -- Never infer or silently replace legacy enrollments in a different section.
    if exists(select 1 from public.student_subject_enrollments e join public.subject_offerings o on o.id=e.subject_offering_id
      where e.student_id=any(v_students) and o.is_active and o.section_id<>v_section.section_id
      and (nullif(o.school_year,'') is null or o.school_year=v_section.school_year)) then
      raise exception 'Existing enrollment conflicts with this section. Review legacy enrollments before placement.'; end if;
    select count(*) into v_count from public.school_section_placements where school_section_id=v_section.id;
    select count(*) into v_expected from unnest(v_students) s where not exists
      (select 1 from public.school_section_placements p where p.student_id=s and p.school_year=v_section.school_year);
    if v_count+v_expected>v_section.capacity then raise exception 'This section does not have enough available seats.'; end if;
    if not exists(select 1 from public.school_teaching_assignments where term_id=v_term.id) or
      exists(select 1 from public.school_teaching_assignments a join public.subject_offerings o on o.id=a.offering_id
        where a.term_id=v_term.id and not o.is_active) then raise exception 'Teaching assignments are incomplete or inactive.'; end if;
    insert into public.school_section_placements(student_id,school_section_id,school_year)
      select s,v_section.id,v_section.school_year from unnest(v_students) s on conflict(student_id,school_year) do nothing;
    insert into public.student_subject_enrollments(student_id,subject_offering_id)
      select s,a.offering_id from unnest(v_students) s cross join public.school_teaching_assignments a
      where a.term_id=v_term.id on conflict(student_id,subject_offering_id) do nothing;
    return jsonb_build_object('enrolled',cardinality(v_students));
  end if;
  raise exception 'Unknown school operation.';
end $$;
revoke all on function public.admin_school_command(text,text,text,jsonb) from public;
grant execute on function public.admin_school_command(text,text,text,jsonb) to anon, authenticated;

-- Preserve legacy individual enrollment, but never use its older public
-- entry point to bypass the credential-verified managed-section workflow.
create or replace function public.admin_assign_student_to_offering(
  p_student_id text,p_offering_id uuid
) returns void language plpgsql security definer set search_path=public as $$ begin
  if exists(select 1 from public.school_teaching_assignments where offering_id=p_offering_id) or
    exists(select 1 from public.subject_offerings o join public.school_sections s on s.section_id=o.section_id where o.id=p_offering_id) then
    raise exception 'Use administrator section enrollment for this managed class.';
  end if;
  insert into public.student_subject_enrollments(student_id,subject_offering_id)
    values(trim(p_student_id)::uuid,p_offering_id) on conflict(student_id,subject_offering_id) do nothing;
end $$;
grant execute on function public.admin_assign_student_to_offering(text,uuid) to anon, authenticated;

-- Existing generic class editors must not rewrite managed assignments.
create or replace function public.protect_ready_school_offering() returns trigger
language plpgsql security invoker set search_path=public as $$ begin
  if tg_op='INSERT' and new.is_active and exists
    (select 1 from public.school_sections where section_id=new.section_id) then
    raise exception 'Create managed classes as draft teaching assignments first.';
  end if;
  if current_user in ('anon','authenticated') and exists
    (select 1 from public.school_sections where section_id=new.section_id) then
    raise exception 'Manage this class through section teaching assignments.';
  end if;
  if tg_op='INSERT' then return new; end if;
  if current_user in ('anon','authenticated') and
    (exists(select 1 from public.school_sections where section_id=old.section_id) or
     exists(select 1 from public.school_teaching_assignments where offering_id=old.id)) then
    raise exception 'Manage this class through section teaching assignments.';
  end if;
  if exists(select 1 from public.school_teaching_assignments a join public.school_section_terms t on t.id=a.term_id
    where a.offering_id=old.id and t.ready and not t.closed) and
    (new.teacher_id,new.subject_id,new.section_id,new.school_year,new.semester,new.beacon_uuid,new.beacon_name,new.is_active)
    is distinct from (old.teacher_id,old.subject_id,old.section_id,old.school_year,old.semester,old.beacon_uuid,old.beacon_name,old.is_active) then
    raise exception 'This is a ready section assignment. Changes require a reviewed transition.';
  end if;
  return new;
end $$;
drop trigger if exists protect_ready_school_offering on public.subject_offerings;
create trigger protect_ready_school_offering before insert or update on public.subject_offerings
  for each row execute function public.protect_ready_school_offering();

-- Block the old per-subject client enrollment path for managed section classes.
-- The credential-verified RPC executes as its owner and is the only client write path.
create or replace function public.protect_school_enrollment() returns trigger
language plpgsql security invoker set search_path=public as $$
declare v_offering uuid; v_section uuid; v_year text; begin
  v_offering:=case when tg_op='DELETE' then old.subject_offering_id else new.subject_offering_id end;
  if current_user in ('anon','authenticated') and
    (exists(select 1 from public.school_teaching_assignments where offering_id=v_offering)
      or (tg_op='UPDATE' and exists(select 1 from public.school_teaching_assignments where offering_id=old.subject_offering_id))) then
    raise exception 'Use administrator section placement for this managed class.';
  end if;
  if tg_op<>'DELETE' then
    select ss.id,ss.school_year into v_section,v_year from public.subject_offerings o
      join public.school_sections ss on ss.section_id=o.section_id where o.id=new.subject_offering_id;
    if v_section is not null and
      (not exists(select 1 from public.school_section_placements where student_id=new.student_id
        and school_section_id=v_section and school_year=v_year)
       or not exists(select 1 from public.school_teaching_assignments a join public.school_section_terms t on t.id=a.term_id
        where a.offering_id=new.subject_offering_id and t.ready and not t.closed)) then
      raise exception 'An approved section placement and ready semester are required.';
    end if;
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
drop trigger if exists protect_school_enrollment on public.student_subject_enrollments;
create trigger protect_school_enrollment before insert or update or delete on public.student_subject_enrollments
  for each row execute function public.protect_school_enrollment();

-- Closing a managed semester cannot race a newly started session. Legacy
-- offerings skip this guard; device validation and BLE checks are untouched.
create or replace function public.guard_school_session_start() returns trigger
language plpgsql security invoker set search_path=public as $$
declare v_open boolean; v_starting boolean; begin
  v_starting:=case when tg_table_name='attendance_sessions'
    then coalesce((to_jsonb(new)->>'is_active')::boolean,false)
    else coalesce(to_jsonb(new)->>'status','') in ('active','paused') end;
  if v_starting and exists(select 1 from public.school_teaching_assignments where offering_id=new.subject_offering_id) then
    perform id from public.subject_offerings where id=new.subject_offering_id for key share;
    select t.ready and not t.closed into v_open from public.school_teaching_assignments a
      join public.school_section_terms t on t.id=a.term_id where a.offering_id=new.subject_offering_id;
    if not coalesce(v_open,false) then raise exception 'This section semester is not open for sessions.'; end if;
  end if;
  return new;
end $$;
drop trigger if exists guard_school_attendance_start on public.attendance_sessions;
create trigger guard_school_attendance_start before insert or update on public.attendance_sessions
  for each row execute function public.guard_school_session_start();
drop trigger if exists guard_school_exam_start on public.exam_sessions;
create trigger guard_school_exam_start before insert or update on public.exam_sessions
  for each row execute function public.guard_school_session_start();
commit;
notify pgrst, 'reload schema';
