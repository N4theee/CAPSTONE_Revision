-- =============================================================================
-- ATTENDXIMITY — complete Supabase SQL (paste entire file into SQL Editor)
-- =============================================================================
-- Run once on your project. Idempotent where possible.
-- Order embedded below:
--   1) Professor → teacher migration
--   2) Core schema + RPCs (teachers table, app_login, admin, sessions)
--   3) Anti-proxy device security (student device binding)
--   4) Legacy professor RPC aliases (optional backward compatibility)
--
-- Default admin after run: username ADMIN-Nath / password 1234567890
-- Teacher login role in app: teacher (professor also accepted at DB level)
-- =============================================================================

-- >>>>> FILE: 00_migrate_professor_to_teacher.sql <<<<<

-- =============================================================================
-- Attendximity: professor → teacher migration (run BEFORE main schema on old DBs)
-- Idempotent — safe to run multiple times.
-- =============================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- 1) Table: professors → teachers
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.professors') is not null
     and to_regclass('public.teachers') is null then
    execute 'alter table public.professors rename to teachers';
    raise notice 'Renamed table professors → teachers';
  elsif to_regclass('public.professors') is not null
        and to_regclass('public.teachers') is not null then
    insert into public.teachers (id, full_name, email, password_hash, max_students, created_at)
    select p.id, p.full_name, p.email, p.password_hash, p.max_students, p.created_at
    from public.professors p
    on conflict (email) do update
      set full_name = excluded.full_name,
          password_hash = excluded.password_hash,
          max_students = excluded.max_students;
    if to_regclass('public.professors_legacy') is null then
      execute 'alter table public.professors rename to professors_legacy';
      raise notice 'Merged professors into teachers; backup → professors_legacy';
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2) Column: subject_offerings.professor_id → teacher_id
-- ---------------------------------------------------------------------------
do $$
declare
  v_fk_name text;
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subject_offerings'
      and column_name = 'professor_id'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subject_offerings'
      and column_name = 'teacher_id'
  ) then
    select c.conname into v_fk_name
    from pg_constraint c
    join pg_class t on c.conrelid = t.oid
    join pg_attribute a on a.attrelid = t.oid and a.attnum = any (c.conkey)
    where t.relname = 'subject_offerings'
      and c.contype = 'f'
      and a.attname = 'professor_id'
    limit 1;

    if v_fk_name is not null then
      execute format('alter table public.subject_offerings drop constraint %I', v_fk_name);
    end if;

    execute 'alter table public.subject_offerings rename column professor_id to teacher_id';

    execute $sql$
      alter table public.subject_offerings
      add constraint subject_offerings_teacher_id_fkey
      foreign key (teacher_id) references public.teachers(id) on delete restrict
    $sql$;

    raise notice 'Renamed subject_offerings.professor_id → teacher_id';
  end if;
end $$;

-- Re-point FK if teacher_id exists but still references professors_legacy
do $$
declare
  v_fk_name text;
  v_ref_table text;
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subject_offerings'
      and column_name = 'teacher_id'
  ) then
    return;
  end if;

  select c.conname, ref.relname
  into v_fk_name, v_ref_table
  from pg_constraint c
  join pg_class t on c.conrelid = t.oid
  join pg_class ref on c.confrelid = ref.oid
  join pg_attribute a on a.attrelid = t.oid and a.attnum = any (c.conkey)
  where t.relname = 'subject_offerings'
    and c.contype = 'f'
    and a.attname = 'teacher_id'
  limit 1;

  if v_fk_name is not null and v_ref_table in ('professors', 'professors_legacy') then
    execute format('alter table public.subject_offerings drop constraint %I', v_fk_name);
    execute $sql$
      alter table public.subject_offerings
      add constraint subject_offerings_teacher_id_fkey
      foreign key (teacher_id) references public.teachers(id) on delete restrict
    $sql$;
    raise notice 'Fixed subject_offerings FK to reference teachers';
  end if;
end $$;

drop index if exists public.idx_subject_offerings_professor;
create index if not exists idx_subject_offerings_teacher on public.subject_offerings(teacher_id);

-- ---------------------------------------------------------------------------
-- 3) RLS policy rename (professors → teachers)
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.teachers') is not null then
    execute 'alter table public.teachers enable row level security';
    execute 'drop policy if exists "open professors read" on public.teachers';
    execute 'drop policy if exists "open teachers read" on public.teachers';
    execute 'create policy "open teachers read" on public.teachers for select to anon using (true)';
  end if;
end $$;

notify pgrst, 'reload schema';


-- >>>>> FILE: ble_attendance_schema.sql <<<<<

-- Attendximity normalized schema (Supabase/PostgreSQL)
-- Migration-first script with compatibility RPCs used by the Flutter app.
-- Safe migration note:
-- 1) Run in a staging copy first.
-- 2) This script keeps legacy tables as *_legacy backups before dropping old names.
-- 3) If old IDs are non-UUID strings, generated UUIDs are used for new identities.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Legacy backups (idempotent)
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.app_users') is not null and to_regclass('public.app_users_legacy') is null then
    execute 'alter table public.app_users rename to app_users_legacy';
  end if;
  if to_regclass('public.sessions') is not null and to_regclass('public.sessions_legacy') is null then
    execute 'alter table public.sessions rename to sessions_legacy';
  end if;
  if to_regclass('public.attendance') is not null and to_regclass('public.attendance_legacy') is null then
    execute 'alter table public.attendance rename to attendance_legacy';
  end if;
  if to_regclass('public.professor_student_map') is not null and to_regclass('public.professor_student_map_legacy') is null then
    execute 'alter table public.professor_student_map rename to professor_student_map_legacy';
  end if;
  if to_regclass('public.student_subject_enrollments') is not null then
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='student_subject_enrollments' and column_name='offering_id'
    ) and to_regclass('public.student_subject_enrollments_legacy') is null then
      execute 'alter table public.student_subject_enrollments rename to student_subject_enrollments_legacy';
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Core normalized tables
-- ---------------------------------------------------------------------------
create table if not exists public.admins (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text unique not null,
  password_hash text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.teachers (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text unique not null,
  password_hash text not null,
  max_students integer,
  created_at timestamptz not null default now()
);

create table if not exists public.students (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text unique not null,
  password_hash text not null,
  student_number text unique,
  created_at timestamptz not null default now()
);

create table if not exists public.subjects (
  id uuid primary key default gen_random_uuid(),
  subject_code text not null unique,
  subject_title text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.sections (
  id uuid primary key default gen_random_uuid(),
  section_name text not null unique,
  grade_level text,
  strand text,
  created_at timestamptz not null default now()
);

create table if not exists public.subject_offerings (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete restrict,
  teacher_id uuid not null references public.teachers(id) on delete restrict,
  section_id uuid not null references public.sections(id) on delete restrict,
  school_year text,
  semester text,
  -- Beacon config set by admin; teacher session uses these (no manual entry on teacher device).
  beacon_uuid text,
  beacon_name text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Upgrade existing databases that created subject_offerings before beacon columns existed.
alter table public.subject_offerings add column if not exists beacon_uuid text;
alter table public.subject_offerings add column if not exists beacon_name text;

create table if not exists public.student_subject_enrollments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete restrict,
  subject_offering_id uuid not null references public.subject_offerings(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(student_id, subject_offering_id)
);

create table if not exists public.student_devices (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  device_uuid text not null,
  device_name text,
  device_mac text,
  device_fingerprint text,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  is_active boolean not null default true
);

create table if not exists public.attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  subject_offering_id uuid not null references public.subject_offerings(id) on delete restrict,
  session_date date not null default current_date,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  beacon_uuid text not null,
  beacon_name text,
  rssi_threshold integer not null default -100,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  attendance_session_id uuid not null references public.attendance_sessions(id) on delete restrict,
  student_id uuid not null references public.students(id) on delete restrict,
  student_device_id uuid references public.student_devices(id) on delete set null,
  status text not null default 'Present',
  marked_at timestamptz not null default now(),
  rssi_value integer,
  device_uuid text,
  device_name text,
  device_mac text,
  device_fingerprint text,
  remarks text,
  unique(attendance_session_id, student_id)
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
create index if not exists idx_subject_offerings_teacher on public.subject_offerings(teacher_id);
create index if not exists idx_subject_offerings_subject on public.subject_offerings(subject_id);
create index if not exists idx_subject_offerings_section on public.subject_offerings(section_id);
create unique index if not exists uq_subject_offerings_dedup
  on public.subject_offerings(
    subject_id,
    teacher_id,
    section_id,
    coalesce(school_year, ''),
    coalesce(semester, '')
  );
create index if not exists idx_enrollments_student on public.student_subject_enrollments(student_id);
create index if not exists idx_enrollments_offering on public.student_subject_enrollments(subject_offering_id);
create index if not exists idx_sessions_offering_active on public.attendance_sessions(subject_offering_id, is_active);
create unique index if not exists uq_sessions_active_offering on public.attendance_sessions(subject_offering_id) where is_active = true;
create index if not exists idx_records_session on public.attendance_records(attendance_session_id);
create index if not exists idx_records_student on public.attendance_records(student_id);
create index if not exists idx_student_devices_student on public.student_devices(student_id);
create index if not exists idx_student_devices_uuid on public.student_devices(device_uuid);

-- ---------------------------------------------------------------------------
-- Optional backfill from legacy tables (best-effort)
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.app_users_legacy') is not null then
    insert into public.admins(full_name, email, password_hash)
    select
      coalesce(nullif(trim(full_name), ''), 'Administrator'),
      trim(username),
      password_hash
    from public.app_users_legacy
    where role = 'admin'
    on conflict (email) do nothing;

    insert into public.teachers(full_name, email, password_hash, max_students)
    select
      coalesce(nullif(trim(full_name), ''), 'Teacher'),
      trim(username),
      password_hash,
      30
    from public.app_users_legacy
    where role in ('professor', 'teacher')
    on conflict (email) do nothing;

    insert into public.students(full_name, email, password_hash, student_number)
    select
      coalesce(nullif(trim(full_name), ''), 'Student'),
      trim(username),
      password_hash,
      nullif(trim(linked_id), '')
    from public.app_users_legacy
    where role = 'student'
    on conflict (email) do nothing;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Functions used by app
-- ---------------------------------------------------------------------------
-- PostgreSQL cannot CREATE OR REPLACE when parameter or return column names change
-- (e.g. p_professor_id → p_teacher_id). Drop old signatures first (idempotent).
drop function if exists public.admin_create_subject_offering(text, text, text, text, text, text);
drop function if exists public.get_subject_offerings_view(text);
drop function if exists public.get_subject_offerings_view(text, text);
drop function if exists public.get_admin_attendance_report(timestamptz, timestamptz, text, text, text);
drop function if exists public.get_admin_attendance_report(timestamptz, timestamptz, text, text, text, text);
drop function if exists public.get_admin_enrollments();
drop function if exists public.get_student_dashboard(text);
drop function if exists public.admin_create_professor_account(text, text, text, text, int);
drop function if exists public.get_professor_session_history(text);
drop function if exists public.get_professor_session_attendees(text, uuid);
drop function if exists public.clear_professor_history(text);

create or replace function public.app_login(
  p_username text,
  p_password text,
  p_role text
)
returns table (
  role text,
  linked_id text,
  full_name text,
  username text
)
language sql
security definer
set search_path = public
as $$
  with wanted as (
    select lower(trim(p_username)) as u, lower(trim(p_role)) as r, trim(p_password) as p
  )
  select 'admin'::text, a.id::text, a.full_name, a.email
  from public.admins a, wanted w
  where w.r = 'admin'
    and lower(a.email) = w.u
    and (
      a.password_hash = extensions.crypt(w.p, a.password_hash)
      or a.password_hash = w.p -- TODO: remove plain fallback before production
    )
  union all
  select 'teacher'::text, p.id::text, p.full_name, p.email
  from public.teachers p, wanted w
  where w.r in ('teacher', 'professor')
    and lower(p.email) = w.u
    and (
      p.password_hash = extensions.crypt(w.p, p.password_hash)
      or p.password_hash = w.p -- TODO: remove plain fallback before production
    )
  union all
  select 'student'::text, s.id::text, s.full_name, s.email
  from public.students s, wanted w
  where w.r = 'student'
    and lower(s.email) = w.u
    and (
      s.password_hash = extensions.crypt(w.p, s.password_hash)
      or s.password_hash = w.p -- TODO: remove plain fallback before production
    )
  limit 1;
$$;

create or replace function public.register_student(
  p_student_id text,
  p_full_name text,
  p_username text,
  p_password text,
  p_device_uuid text default null,
  p_device_name text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid;
begin
  insert into public.students(full_name, email, password_hash, student_number)
  values (
    trim(p_full_name),
    trim(p_username),
    extensions.crypt(trim(p_password), extensions.gen_salt('bf')),
    nullif(trim(p_student_id), '')
  )
  on conflict (email) do update
    set full_name = excluded.full_name
  returning id into v_student_id;

  if p_device_uuid is not null and trim(p_device_uuid) <> '' then
    insert into public.student_devices(student_id, device_uuid, device_name)
    values (v_student_id, trim(p_device_uuid), nullif(trim(coalesce(p_device_name, '')), ''))
    on conflict do nothing;
  end if;

  return v_student_id::text;
end;
$$;

create or replace function public.admin_create_teacher_account(
  p_teacher_id text,
  p_full_name text,
  p_username text,
  p_password text,
  p_max_students int default 30
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_teacher_id uuid;
begin
  insert into public.teachers(full_name, email, password_hash, max_students)
  values (
    trim(p_full_name),
    trim(p_username),
    extensions.crypt(trim(p_password), extensions.gen_salt('bf')),
    least(greatest(coalesce(p_max_students, 30), 1), 300)
  )
  on conflict (email) do update
    set full_name = excluded.full_name,
        max_students = excluded.max_students
  returning id into v_teacher_id;

  return v_teacher_id::text;
end;
$$;

create or replace function public.admin_create_subject_offering(
  p_teacher_id text,
  p_subject_code text,
  p_subject_title text,
  p_section text,
  p_beacon_uuid text,
  p_beacon_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_subject_id uuid;
  v_section_id uuid;
  v_offering_id uuid;
begin
  insert into public.subjects(subject_code, subject_title)
  values (trim(p_subject_code), trim(p_subject_title))
  on conflict (subject_code) do update
    set subject_title = excluded.subject_title
  returning id into v_subject_id;

  insert into public.sections(section_name)
  values (trim(p_section))
  on conflict (section_name) do update
    set section_name = excluded.section_name
  returning id into v_section_id;

  insert into public.subject_offerings(
    subject_id, teacher_id, section_id, school_year, semester, is_active,
    beacon_uuid, beacon_name
  )
  values (
    v_subject_id,
    trim(p_teacher_id)::uuid,
    v_section_id,
    null,
    null,
    true,
    nullif(trim(p_beacon_uuid), ''),
    nullif(trim(p_beacon_name), '')
  )
  on conflict do nothing
  returning id into v_offering_id;

  if v_offering_id is null then
    select id into v_offering_id
    from public.subject_offerings
    where subject_id = v_subject_id
      and teacher_id = trim(p_teacher_id)::uuid
      and section_id = v_section_id
    order by created_at desc
    limit 1;
  end if;

  -- Persist admin-configured beacon (used by teacher app when starting a session).
  update public.subject_offerings
  set
    beacon_uuid = nullif(trim(p_beacon_uuid), ''),
    beacon_name = nullif(trim(p_beacon_name), '')
  where id = v_offering_id;

  return v_offering_id;
end;
$$;

create or replace function public.get_subject_offerings_view(
  p_teacher_id text default null
)
returns table(
  id uuid,
  subject_id uuid,
  section_id uuid,
  subject_code text,
  subject_title text,
  section text,
  teacher_id uuid,
  teacher_name text,
  beacon_uuid text,
  beacon_name text
)
language sql
security definer
set search_path = public
as $$
  select
    so.id,
    so.subject_id,
    so.section_id,
    sub.subject_code,
    sub.subject_title,
    sec.section_name as section,
    so.teacher_id,
    p.full_name as teacher_name,
    so.beacon_uuid,
    so.beacon_name
  from public.subject_offerings so
  join public.subjects sub on sub.id = so.subject_id
  join public.sections sec on sec.id = so.section_id
  join public.teachers p on p.id = so.teacher_id
  where so.is_active = true
    and (p_teacher_id is null or so.teacher_id = trim(p_teacher_id)::uuid)
  order by sub.subject_code, sec.section_name;
$$;

create or replace function public.get_student_dashboard(
  p_student_id text
)
returns table (
  offering_id uuid,
  subject_id uuid,
  section_id uuid,
  subject_code text,
  subject_title text,
  section text,
  teacher_id uuid,
  teacher_name text,
  beacon_uuid text,
  beacon_name text
)
language sql
security definer
set search_path = public
as $$
  select
    so.id as offering_id,
    so.subject_id,
    so.section_id,
    sub.subject_code,
    sub.subject_title,
    sec.section_name,
    so.teacher_id,
    p.full_name,
    so.beacon_uuid,
    so.beacon_name
  from public.student_subject_enrollments sse
  join public.subject_offerings so on so.id = sse.subject_offering_id
  join public.subjects sub on sub.id = so.subject_id
  join public.sections sec on sec.id = so.section_id
  join public.teachers p on p.id = so.teacher_id
  where sse.student_id = trim(p_student_id)::uuid
    and so.is_active = true
  order by sub.subject_code, sec.section_name;
$$;

create or replace function public.admin_assign_student_to_offering(
  p_student_id text,
  p_offering_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.student_subject_enrollments(student_id, subject_offering_id)
  values (trim(p_student_id)::uuid, p_offering_id)
  on conflict (student_id, subject_offering_id) do nothing;
end;
$$;

create or replace function public.get_admin_enrollments()
returns table (
  student_id uuid,
  student_name text,
  offering_id uuid,
  teacher_id uuid,
  teacher_name text,
  subject_code text,
  subject_title text,
  section text
)
language sql
security definer
set search_path = public
as $$
  select
    s.id as student_id,
    s.full_name as student_name,
    so.id as offering_id,
    p.id as teacher_id,
    p.full_name as teacher_name,
    sub.subject_code,
    sub.subject_title,
    sec.section_name as section
  from public.student_subject_enrollments sse
  join public.students s on s.id = sse.student_id
  join public.subject_offerings so on so.id = sse.subject_offering_id
  join public.teachers p on p.id = so.teacher_id
  join public.subjects sub on sub.id = so.subject_id
  join public.sections sec on sec.id = so.section_id
  order by s.full_name, sub.subject_code, sec.section_name;
$$;

create or replace function public.get_admin_attendance_report(
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_teacher_id text default null,
  p_subject_code text default null,
  p_section_name text default null
)
returns table(
  session_id uuid,
  session_started_at timestamptz,
  session_ended_at timestamptz,
  subject_code text,
  subject_title text,
  section text,
  teacher_id uuid,
  teacher_name text,
  student_id uuid,
  student_name text,
  marked_at timestamptz,
  status text,
  device_name text,
  device_mac text,
  device_fingerprint text
)
language sql
security definer
set search_path = public
as $$
  select
    sess.id,
    sess.started_at,
    sess.ended_at,
    sub.subject_code,
    sub.subject_title,
    sec.section_name,
    p.id,
    p.full_name,
    st.id,
    st.full_name,
    ar.marked_at,
    ar.status,
    ar.device_name,
    ar.device_mac,
    ar.device_fingerprint
  from public.attendance_records ar
  join public.attendance_sessions sess on sess.id = ar.attendance_session_id
  join public.subject_offerings so on so.id = sess.subject_offering_id
  join public.subjects sub on sub.id = so.subject_id
  join public.sections sec on sec.id = so.section_id
  join public.teachers p on p.id = so.teacher_id
  join public.students st on st.id = ar.student_id
  where (p_from is null or ar.marked_at >= p_from)
    and (p_to is null or ar.marked_at <= p_to)
    and (p_teacher_id is null or so.teacher_id = trim(p_teacher_id)::uuid)
    and (p_subject_code is null or sub.subject_code = p_subject_code)
    and (p_section_name is null or sec.section_name = p_section_name)
  order by ar.marked_at desc;
$$;

create or replace function public.update_display_name(
  p_role text,
  p_linked_id text,
  p_full_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if trim(p_role) = 'student' then
    update public.students
    set full_name = trim(p_full_name)
    where id = trim(p_linked_id)::uuid;
  elsif trim(p_role) in ('teacher', 'professor') then
    update public.teachers
    set full_name = trim(p_full_name)
    where id = trim(p_linked_id)::uuid;
  elsif trim(p_role) = 'admin' then
    update public.admins
    set full_name = trim(p_full_name)
    where id = trim(p_linked_id)::uuid;
  else
    raise exception 'Invalid role';
  end if;
end;
$$;

create or replace function public.get_teacher_session_history(
  p_teacher_id text
)
returns table (
  session_id uuid,
  subject_code text,
  subject_title text,
  section text,
  started_at timestamptz,
  ended_at timestamptz,
  is_active boolean
)
language sql
security definer
set search_path = public
as $$
  select
    sess.id,
    sub.subject_code,
    sub.subject_title,
    sec.section_name,
    sess.started_at,
    sess.ended_at,
    sess.is_active
  from public.attendance_sessions sess
  join public.subject_offerings so on so.id = sess.subject_offering_id
  join public.subjects sub on sub.id = so.subject_id
  join public.sections sec on sec.id = so.section_id
  where so.teacher_id = trim(p_teacher_id)::uuid
  order by sess.started_at desc;
$$;

-- OUT/return columns changed vs older DBs; Postgres forbids CREATE OR REPLACE for that.
drop function if exists public.get_teacher_session_attendees(text, uuid);

create or replace function public.get_teacher_session_attendees(
  p_teacher_id text,
  p_session_id uuid
)
returns table (
  student_id uuid,
  student_name text,
  marked_at timestamptz,
  device_used text,
  is_present boolean
)
language sql
security definer
set search_path = public
as $$
  select
    st.id,
    st.full_name,
    ar.marked_at,
    case
      when ar.id is not null then
        coalesce(
          nullif(trim(ar.device_name), ''),
          case when nullif(trim(ar.device_uuid), '') is not null then 'Registered handset' end,
          case when nullif(trim(ar.device_fingerprint), '') is not null then 'Device fingerprint on file' end,
          'Unknown device'
        )
      else null
    end as device_used,
    (ar.id is not null) as is_present
  from public.attendance_sessions sess
  join public.subject_offerings so on so.id = sess.subject_offering_id
  join public.student_subject_enrollments sse on sse.subject_offering_id = so.id
  join public.students st on st.id = sse.student_id
  left join public.attendance_records ar
    on ar.attendance_session_id = sess.id
    and ar.student_id = st.id
  where sess.id = p_session_id
    and so.teacher_id = trim(p_teacher_id)::uuid
  order by st.full_name asc;
$$;

create or replace function public.get_session_device_anomalies(
  p_session_id uuid
)
returns table (
  device_uuid text,
  students_count bigint,
  student_ids text[],
  student_names text[],
  first_marked_at timestamptz,
  last_marked_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    ar.device_uuid,
    count(distinct ar.student_id) as students_count,
    array_agg(distinct ar.student_id::text order by ar.student_id::text) as student_ids,
    array_agg(distinct st.full_name order by st.full_name) as student_names,
    min(ar.marked_at) as first_marked_at,
    max(ar.marked_at) as last_marked_at
  from public.attendance_records ar
  join public.students st on st.id = ar.student_id
  where ar.attendance_session_id = p_session_id
    and ar.device_uuid is not null
    and trim(ar.device_uuid) <> ''
  group by ar.device_uuid
  having count(distinct ar.student_id) > 1
  order by students_count desc, first_marked_at asc;
$$;

create or replace function public.get_student_attendance_history(
  p_student_id text
)
returns table (
  subject_code text,
  subject_title text,
  section text,
  teacher_name text,
  session_started_at timestamptz,
  marked_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    sub.subject_code,
    sub.subject_title,
    sec.section_name,
    p.full_name,
    sess.started_at,
    ar.marked_at
  from public.attendance_records ar
  join public.attendance_sessions sess on sess.id = ar.attendance_session_id
  join public.subject_offerings so on so.id = sess.subject_offering_id
  join public.subjects sub on sub.id = so.subject_id
  join public.sections sec on sec.id = so.section_id
  join public.teachers p on p.id = so.teacher_id
  where ar.student_id = trim(p_student_id)::uuid
  order by ar.marked_at desc;
$$;

create or replace function public.clear_teacher_history(
  p_teacher_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('row_security', 'off', true);
  delete from public.attendance_records ar
  using public.attendance_sessions sess, public.subject_offerings so
  where ar.attendance_session_id = sess.id
    and sess.subject_offering_id = so.id
    and so.teacher_id = trim(p_teacher_id)::uuid;

  delete from public.attendance_sessions sess
  using public.subject_offerings so
  where sess.subject_offering_id = so.id
    and so.teacher_id = trim(p_teacher_id)::uuid;
end;
$$;

create or replace function public.clear_student_history(
  p_student_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('row_security', 'off', true);
  delete from public.attendance_records
  where student_id = trim(p_student_id)::uuid;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
grant execute on function public.app_login(text, text, text) to anon, authenticated;
grant execute on function public.register_student(text, text, text, text, text, text) to anon, authenticated;
grant execute on function public.admin_create_teacher_account(text, text, text, text, int) to anon, authenticated;
grant execute on function public.admin_create_subject_offering(text, text, text, text, text, text) to anon, authenticated;
grant execute on function public.get_subject_offerings_view(text) to anon, authenticated;
grant execute on function public.admin_assign_student_to_offering(text, uuid) to anon, authenticated;
grant execute on function public.get_admin_enrollments() to anon, authenticated;
grant execute on function public.get_student_dashboard(text) to anon, authenticated;
grant execute on function public.get_admin_attendance_report(timestamptz, timestamptz, text, text, text) to anon, authenticated;
grant execute on function public.update_display_name(text, text, text) to anon, authenticated;
grant execute on function public.get_teacher_session_history(text) to anon, authenticated;
grant execute on function public.get_teacher_session_attendees(text, uuid) to anon, authenticated;
grant execute on function public.get_session_device_anomalies(uuid) to anon, authenticated;
grant execute on function public.get_student_attendance_history(text) to anon, authenticated;
grant execute on function public.clear_teacher_history(text) to anon, authenticated;
grant execute on function public.clear_student_history(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.admins enable row level security;
alter table public.teachers enable row level security;
alter table public.students enable row level security;
alter table public.subjects enable row level security;
alter table public.sections enable row level security;
alter table public.subject_offerings enable row level security;
alter table public.student_subject_enrollments enable row level security;
alter table public.student_devices enable row level security;
alter table public.attendance_sessions enable row level security;
alter table public.attendance_records enable row level security;

drop policy if exists "open admins read" on public.admins;
create policy "open admins read" on public.admins for select to anon using (true);
drop policy if exists "open teachers read" on public.teachers;
create policy "open teachers read" on public.teachers for select to anon using (true);
drop policy if exists "open students read" on public.students;
create policy "open students read" on public.students for select to anon using (true);
drop policy if exists "open subjects rw" on public.subjects;
create policy "open subjects rw" on public.subjects for all to anon using (true) with check (true);
drop policy if exists "open sections rw" on public.sections;
create policy "open sections rw" on public.sections for all to anon using (true) with check (true);
drop policy if exists "open offerings rw" on public.subject_offerings;
create policy "open offerings rw" on public.subject_offerings for all to anon using (true) with check (true);
drop policy if exists "open enrollments rw" on public.student_subject_enrollments;
create policy "open enrollments rw" on public.student_subject_enrollments for all to anon using (true) with check (true);
drop policy if exists "open devices rw" on public.student_devices;
create policy "open devices rw" on public.student_devices for all to anon using (true) with check (true);
drop policy if exists "open sessions rw" on public.attendance_sessions;
create policy "open sessions rw" on public.attendance_sessions for all to anon using (true) with check (true);
drop policy if exists "open records rw" on public.attendance_records;
create policy "open records rw" on public.attendance_records for all to anon using (true) with check (true);

-- ---------------------------------------------------------------------------
-- Default admin account
-- ---------------------------------------------------------------------------
insert into public.admins(full_name, email, password_hash)
values (
  'Nath',
  'ADMIN-Nath',
  extensions.crypt('1234567890', extensions.gen_salt('bf'))
)
on conflict (email) do update
set full_name = excluded.full_name,
    password_hash = excluded.password_hash;

notify pgrst, 'reload schema';


-- >>>>> FILE: anti_proxy_device_security.sql <<<<<

-- Anti-proxy device security (Attendximity)
-- Run this in Supabase SQL Editor after ble_attendance_schema.sql (or merge into your pipeline).
-- Extends existing public.student_devices; adds student_login_sessions and RPCs.

-- ---------------------------------------------------------------------------
-- 1) Extend student_devices
-- ---------------------------------------------------------------------------
alter table public.student_devices
  add column if not exists is_primary boolean not null default true,
  add column if not exists is_revoked boolean not null default false,
  add column if not exists attendance_enabled boolean not null default true,
  add column if not exists approval_status text not null default 'approved',
  add column if not exists revoked_at timestamptz,
  add column if not exists registered_at timestamptz;

update public.student_devices
set registered_at = coalesce(registered_at, first_seen_at, now())
where registered_at is null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on c.conrelid = t.oid
    where t.relname = 'student_devices'
      and c.conname = 'student_devices_approval_status_check'
  ) then
    alter table public.student_devices
      add constraint student_devices_approval_status_check
      check (approval_status in ('pending', 'approved', 'rejected'));
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2) student_login_sessions (one row per student)
-- ---------------------------------------------------------------------------
create table if not exists public.student_login_sessions (
  student_id uuid primary key references public.students(id) on delete cascade,
  device_uuid text not null,
  device_fingerprint text,
  signed_in_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  is_active boolean not null default true
);

create index if not exists idx_student_login_sessions_active_device
  on public.student_login_sessions(student_id, is_active);

alter table public.student_login_sessions enable row level security;

drop policy if exists "open student_login_sessions rw" on public.student_login_sessions;
create policy "open student_login_sessions rw"
  on public.student_login_sessions
  for all
  to anon
  using (true)
  with check (true);

-- ---------------------------------------------------------------------------
-- 3) Data cleanup before partial unique indexes (idempotent)
-- ---------------------------------------------------------------------------
-- At most one active approved primary device row per student (keep earliest).
with ranked as (
  select
    id,
    row_number() over (
      partition by student_id
      order by registered_at nulls last, first_seen_at nulls last, id
    ) as rn
  from public.student_devices
  where is_active
    and not is_revoked
    and approval_status = 'approved'
    and is_primary
)
update public.student_devices d
set
  is_active = false,
  is_primary = false
from ranked r
where d.id = r.id
  and r.rn > 1;

-- One student per active approved device_uuid (keep earliest row per device_uuid).
with ranked as (
  select
    id,
    row_number() over (
      partition by device_uuid
      order by registered_at nulls last, first_seen_at nulls last, id
    ) as rn
  from public.student_devices
  where coalesce(trim(device_uuid), '') <> ''
    and is_active
    and not is_revoked
    and approval_status = 'approved'
)
update public.student_devices d
set
  is_active = false,
  is_revoked = true,
  revoked_at = coalesce(d.revoked_at, now())
from ranked r
where d.id = r.id
  and r.rn > 1;

drop index if exists uq_student_devices_one_active_primary_student;
create unique index uq_student_devices_one_active_primary_student
  on public.student_devices (student_id)
  where is_primary = true
    and is_active = true
    and not is_revoked
    and approval_status = 'approved';

drop index if exists uq_student_devices_one_active_approved_uuid;
create unique index uq_student_devices_one_active_approved_uuid
  on public.student_devices (device_uuid)
  where is_active = true
    and not is_revoked
    and approval_status = 'approved'
    and coalesce(trim(device_uuid), '') <> '';

-- ---------------------------------------------------------------------------
-- 4) RPC: app_student_login_with_device
-- ---------------------------------------------------------------------------
create or replace function public.app_student_login_with_device(
  p_username text,
  p_password text,
  p_device_uuid text,
  p_device_name text,
  p_device_fingerprint text
)
returns table (
  role text,
  linked_id text,
  full_name text,
  username text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid;
  v_full_name text;
  v_email text;
  v_pass_ok boolean;
  v_uuid text := nullif(trim(coalesce(p_device_uuid, '')), '');
  v_name text := nullif(trim(coalesce(p_device_name, '')), '');
  v_fp text := nullif(trim(coalesce(p_device_fingerprint, '')), '');
  v_existing_device_student uuid;
  v_primary record;
begin
  if v_uuid is null then
    raise exception 'Device identity is required for student login.';
  end if;

  select
    s.id,
    s.full_name,
    s.email,
    (
      s.password_hash = extensions.crypt(trim(p_password), s.password_hash)
      or s.password_hash = trim(p_password)
    )
  into v_student_id, v_full_name, v_email, v_pass_ok
  from public.students s
  where lower(trim(s.email)) = lower(trim(p_username))
  limit 1;

  if v_student_id is null or not coalesce(v_pass_ok, false) then
    return;
  end if;

  -- Device already registered to another student (active approved).
  select sd.student_id
  into v_existing_device_student
  from public.student_devices sd
  where sd.device_uuid = v_uuid
    and sd.student_id <> v_student_id
    and sd.is_active
    and not sd.is_revoked
    and sd.approval_status = 'approved'
  limit 1;

  if v_existing_device_student is not null then
    raise exception 'Cannot sign in. This device is already registered to another student.';
  end if;

  -- Account already signed in on a different device.
  if exists (
    select 1
    from public.student_login_sessions sls
    where sls.student_id = v_student_id
      and sls.is_active
      and sls.device_uuid is distinct from v_uuid
  ) then
    raise exception 'Cannot sign in. This student account is already signed in on another device.';
  end if;

  select *
  into v_primary
  from public.student_devices sd
  where sd.student_id = v_student_id
    and sd.is_primary
    and sd.is_active
    and not sd.is_revoked
    and sd.approval_status = 'approved'
    and sd.attendance_enabled
  order by sd.registered_at nulls last, sd.first_seen_at nulls last
  limit 1;

  if not found then
    -- First approved attendance device for this student.
    insert into public.student_devices (
      student_id,
      device_uuid,
      device_name,
      device_fingerprint,
      first_seen_at,
      last_seen_at,
      is_active,
      is_primary,
      is_revoked,
      attendance_enabled,
      approval_status,
      registered_at
    )
    values (
      v_student_id,
      v_uuid,
      v_name,
      v_fp,
      now(),
      now(),
      true,
      true,
      false,
      true,
      'approved',
      now()
    );
  else
    if v_primary.device_uuid is distinct from v_uuid then
      raise exception 'Cannot sign in. This is not your registered device.';
    end if;

    update public.student_devices
    set
      device_name = coalesce(v_name, device_name),
      device_fingerprint = coalesce(v_fp, device_fingerprint),
      last_seen_at = now()
    where id = v_primary.id;
  end if;

  insert into public.student_login_sessions (
    student_id,
    device_uuid,
    device_fingerprint,
    signed_in_at,
    last_seen_at,
    is_active
  )
  values (
    v_student_id,
    v_uuid,
    v_fp,
    now(),
    now(),
    true
  )
  on conflict (student_id) do update
    set
      device_uuid = excluded.device_uuid,
      device_fingerprint = excluded.device_fingerprint,
      last_seen_at = now(),
      is_active = true,
      signed_in_at = case
        when student_login_sessions.device_uuid is distinct from excluded.device_uuid
        then now()
        else student_login_sessions.signed_in_at
      end;

  return query
  select
    'student'::text,
    v_student_id::text,
    v_full_name,
    v_email;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5) RPC: validate_student_attendance_device
-- ---------------------------------------------------------------------------
create or replace function public.validate_student_attendance_device(
  p_student_id uuid,
  p_device_uuid text,
  p_device_fingerprint text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uuid text := nullif(trim(coalesce(p_device_uuid, '')), '');
  v_fp text := nullif(trim(coalesce(p_device_fingerprint, '')), '');
  v_ok boolean;
begin
  if v_uuid is null then
    raise exception 'Attendance blocked. This is not your registered attendance device.';
  end if;

  select true
  into v_ok
  from public.student_devices sd
  where sd.student_id = p_student_id
    and sd.device_uuid = v_uuid
    and sd.is_primary
    and sd.is_active
    and not sd.is_revoked
    and sd.attendance_enabled
    and sd.approval_status = 'approved'
    and (
      sd.device_fingerprint is null
      or trim(sd.device_fingerprint) = ''
      or v_fp is null
      or sd.device_fingerprint = v_fp
    )
  limit 1;

  if not coalesce(v_ok, false) then
    raise exception 'Attendance blocked. This is not your registered attendance device.';
  end if;

  return true;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6) RPC: mark_attendance_secure
-- ---------------------------------------------------------------------------
create or replace function public.mark_attendance_secure(
  p_session_id uuid,
  p_student_id uuid,
  p_student_name text,
  p_device_uuid text,
  p_device_name text,
  p_device_fingerprint text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_active boolean;
  v_name text := nullif(trim(coalesce(p_device_name, '')), '');
  v_uuid text := nullif(trim(coalesce(p_device_uuid, '')), '');
  v_fp text := nullif(trim(coalesce(p_device_fingerprint, '')), '');
  v_inserted boolean := false;
begin
  select s.is_active
  into v_active
  from public.attendance_sessions s
  where s.id = p_session_id
  limit 1;

  if not coalesce(v_active, false) then
    raise exception 'Attendance session has ended.';
  end if;

  perform public.validate_student_attendance_device(
    p_student_id,
    coalesce(p_device_uuid, ''),
    coalesce(p_device_fingerprint, '')
  );

  insert into public.attendance_records (
    attendance_session_id,
    student_id,
    student_device_id,
    status,
    marked_at,
    device_uuid,
    device_name,
    device_fingerprint
  )
  values (
    p_session_id,
    p_student_id,
    null,
    'Present',
    now(),
    v_uuid,
    v_name,
    v_fp
  )
  on conflict (attendance_session_id, student_id) do nothing
  returning true into v_inserted;

  return coalesce(v_inserted, false);
end;
$$;

-- ---------------------------------------------------------------------------
-- 7) RPC: student_sign_out_device
-- ---------------------------------------------------------------------------
create or replace function public.student_sign_out_device(
  p_student_id uuid,
  p_device_uuid text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uuid text := nullif(trim(coalesce(p_device_uuid, '')), '');
  v_has_active_session boolean;
begin
  if v_uuid is null then
    raise exception 'Device identity is required to sign out.';
  end if;

  select exists (
    select 1
    from public.student_subject_enrollments e
    join public.attendance_sessions s
      on s.subject_offering_id = e.subject_offering_id
    where e.student_id = p_student_id
      and s.is_active = true
  )
  into v_has_active_session;

  if coalesce(v_has_active_session, false) then
    raise exception 'Session is active, cannot logout.';
  end if;

  update public.student_login_sessions sls
  set is_active = false
  where sls.student_id = p_student_id
    and sls.device_uuid = v_uuid;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8) RPC: get_student_active_session_status
-- ---------------------------------------------------------------------------
create or replace function public.get_student_active_session_status(
  p_student_id uuid
)
returns table (
  has_active_session boolean,
  session_id uuid,
  offering_id uuid,
  already_marked boolean,
  subject_code text,
  subject_title text,
  section text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session_id uuid;
  v_offering_id uuid;
  v_marked boolean;
  v_code text;
  v_title text;
  v_section text;
begin
  select
    s.id,
    s.subject_offering_id
  into v_session_id, v_offering_id
  from public.student_subject_enrollments e
  join public.attendance_sessions s
    on s.subject_offering_id = e.subject_offering_id
    and s.is_active = true
  where e.student_id = p_student_id
  order by s.started_at desc
  limit 1;

  if v_session_id is null then
    return query select false, null::uuid, null::uuid, false, null::text, null::text, null::text;
    return;
  end if;

  select exists (
    select 1
    from public.attendance_records ar
    where ar.attendance_session_id = v_session_id
      and ar.student_id = p_student_id
  )
  into v_marked;

  select
    sj.subject_code,
    sj.subject_title,
    sec.section_name
  into v_code, v_title, v_section
  from public.subject_offerings o
  join public.subjects sj on sj.id = o.subject_id
  join public.sections sec on sec.id = o.section_id
  where o.id = v_offering_id
  limit 1;

  return query
  select
    true,
    v_session_id,
    v_offering_id,
    coalesce(v_marked, false),
    coalesce(v_code, ''),
    coalesce(v_title, ''),
    coalesce(v_section, '');
end;
$$;

-- ---------------------------------------------------------------------------
-- 9) Grants + schema reload
-- ---------------------------------------------------------------------------
grant execute on function public.app_student_login_with_device(text, text, text, text, text) to anon, authenticated;
grant execute on function public.validate_student_attendance_device(uuid, text, text) to anon, authenticated;
grant execute on function public.mark_attendance_secure(uuid, uuid, text, text, text, text) to anon, authenticated;
grant execute on function public.student_sign_out_device(uuid, text) to anon, authenticated;
grant execute on function public.get_student_active_session_status(uuid) to anon, authenticated;

notify pgrst, 'reload schema';


-- >>>>> FILE: 99_professor_rpc_compat.sql <<<<<

-- =============================================================================
-- Attendximity: legacy "professor" RPC aliases → teacher implementations
-- Run AFTER ble_attendance_schema.sql (idempotent).
-- Keeps old function names working while the Flutter UI says "Teacher".
-- =============================================================================

-- Replace overloads that use dual professor/teacher filter params.
drop function if exists public.get_subject_offerings_view(text);
drop function if exists public.get_subject_offerings_view(text, text);
drop function if exists public.get_admin_attendance_report(timestamptz, timestamptz, text, text, text);
drop function if exists public.get_admin_attendance_report(timestamptz, timestamptz, text, text, text, text);

-- Login role "professor" is already accepted in app_login (teacher branch).

-- ---------------------------------------------------------------------------
-- Admin: create account
-- ---------------------------------------------------------------------------
create or replace function public.admin_create_professor_account(
  p_professor_id text,
  p_full_name text,
  p_username text,
  p_password text,
  p_max_students int default 30
)
returns text
language sql
security definer
set search_path = public
as $$
  select public.admin_create_teacher_account(
    p_professor_id,
    p_full_name,
    p_username,
    p_password,
    p_max_students
  );
$$;

-- ---------------------------------------------------------------------------
-- Offerings view: accept p_professor_id OR p_teacher_id
-- ---------------------------------------------------------------------------
create or replace function public.get_subject_offerings_view(
  p_teacher_id text default null,
  p_professor_id text default null
)
returns table(
  id uuid,
  subject_id uuid,
  section_id uuid,
  subject_code text,
  subject_title text,
  section text,
  teacher_id uuid,
  teacher_name text,
  beacon_uuid text,
  beacon_name text
)
language sql
security definer
set search_path = public
as $$
  select
    so.id,
    so.subject_id,
    so.section_id,
    sub.subject_code,
    sub.subject_title,
    sec.section_name as section,
    so.teacher_id,
    p.full_name as teacher_name,
    so.beacon_uuid,
    so.beacon_name
  from public.subject_offerings so
  join public.subjects sub on sub.id = so.subject_id
  join public.sections sec on sec.id = so.section_id
  join public.teachers p on p.id = so.teacher_id
  where so.is_active = true
    and (
      coalesce(nullif(trim(p_teacher_id), ''), nullif(trim(p_professor_id), '')) is null
      or so.teacher_id = trim(coalesce(nullif(trim(p_teacher_id), ''), nullif(trim(p_professor_id), '')))::uuid
    )
  order by sub.subject_code, sec.section_name;
$$;

-- ---------------------------------------------------------------------------
-- Admin report: accept p_professor_id OR p_teacher_id
-- ---------------------------------------------------------------------------
create or replace function public.get_admin_attendance_report(
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_teacher_id text default null,
  p_professor_id text default null,
  p_subject_code text default null,
  p_section_name text default null
)
returns table(
  session_id uuid,
  session_started_at timestamptz,
  session_ended_at timestamptz,
  subject_code text,
  subject_title text,
  section text,
  teacher_id uuid,
  teacher_name text,
  student_id uuid,
  student_name text,
  marked_at timestamptz,
  status text,
  device_name text,
  device_mac text,
  device_fingerprint text
)
language sql
security definer
set search_path = public
as $$
  select
    sess.id,
    sess.started_at,
    sess.ended_at,
    sub.subject_code,
    sub.subject_title,
    sec.section_name,
    p.id,
    p.full_name,
    st.id,
    st.full_name,
    ar.marked_at,
    ar.status,
    ar.device_name,
    ar.device_mac,
    ar.device_fingerprint
  from public.attendance_records ar
  join public.attendance_sessions sess on sess.id = ar.attendance_session_id
  join public.subject_offerings so on so.id = sess.subject_offering_id
  join public.subjects sub on sub.id = so.subject_id
  join public.sections sec on sec.id = so.section_id
  join public.teachers p on p.id = so.teacher_id
  join public.students st on st.id = ar.student_id
  where (p_from is null or ar.marked_at >= p_from)
    and (p_to is null or ar.marked_at <= p_to)
    and (
      coalesce(nullif(trim(p_teacher_id), ''), nullif(trim(p_professor_id), '')) is null
      or so.teacher_id = trim(coalesce(nullif(trim(p_teacher_id), ''), nullif(trim(p_professor_id), '')))::uuid
    )
    and (p_subject_code is null or sub.subject_code = p_subject_code)
    and (p_section_name is null or sec.section_name = p_section_name)
  order by ar.marked_at desc;
$$;

-- ---------------------------------------------------------------------------
-- Session history / attendees / clear (professor param names)
-- ---------------------------------------------------------------------------
create or replace function public.get_professor_session_history(
  p_professor_id text
)
returns table (
  session_id uuid,
  subject_code text,
  subject_title text,
  section text,
  started_at timestamptz,
  ended_at timestamptz,
  is_active boolean
)
language sql
security definer
set search_path = public
as $$
  select * from public.get_teacher_session_history(p_professor_id);
$$;

drop function if exists public.get_professor_session_attendees(text, uuid);

create or replace function public.get_professor_session_attendees(
  p_professor_id text,
  p_session_id uuid
)
returns table (
  student_id uuid,
  student_name text,
  marked_at timestamptz,
  device_used text,
  is_present boolean
)
language sql
security definer
set search_path = public
as $$
  select * from public.get_teacher_session_attendees(p_professor_id, p_session_id);
$$;

create or replace function public.clear_professor_history(
  p_professor_id text
)
returns void
language sql
security definer
set search_path = public
as $$
  select public.clear_teacher_history(p_professor_id);
$$;

-- Optional alias used by some deployments
create or replace function public.clear_teacher_session_history(
  p_teacher_id text
)
returns void
language sql
security definer
set search_path = public
as $$
  select public.clear_teacher_history(p_teacher_id);
$$;

-- ---------------------------------------------------------------------------
-- Grants (legacy names)
-- ---------------------------------------------------------------------------
grant execute on function public.admin_create_professor_account(text, text, text, text, int) to anon, authenticated;
grant execute on function public.get_subject_offerings_view(text, text) to anon, authenticated;
grant execute on function public.get_admin_attendance_report(timestamptz, timestamptz, text, text, text, text) to anon, authenticated;
grant execute on function public.get_professor_session_history(text) to anon, authenticated;
grant execute on function public.get_professor_session_attendees(text, uuid) to anon, authenticated;
grant execute on function public.clear_professor_history(text) to anon, authenticated;
grant execute on function public.clear_teacher_session_history(text) to anon, authenticated;

notify pgrst, 'reload schema';

