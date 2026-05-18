-- =============================================================================
-- BACKUP REFERENCE: schema with "professor" naming (before teacher rename)
-- =============================================================================
-- This file is a SNAPSHOT of your schema definition (tables, functions, RLS).
-- It does NOT include your live row data (student accounts, attendance rows, etc.).
-- To backup actual data, use Supabase Dashboard export or: supabase db dump
--
-- Use this file to:
--   - Understand / recreate the OLD professor-based structure on a NEW empty project
--   - Compare against the teacher schema after migration
--
-- Do NOT run this on your live project if it already has the teacher rename applied.
-- =============================================================================

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

create table if not exists public.professors (
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
  professor_id uuid not null references public.professors(id) on delete restrict,
  section_id uuid not null references public.sections(id) on delete restrict,
  school_year text,
  semester text,
  -- Beacon config set by admin; professor session uses these (no manual entry on prof device).
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
create index if not exists idx_subject_offerings_professor on public.subject_offerings(professor_id);
create index if not exists idx_subject_offerings_subject on public.subject_offerings(subject_id);
create index if not exists idx_subject_offerings_section on public.subject_offerings(section_id);
create unique index if not exists uq_subject_offerings_dedup
  on public.subject_offerings(
    subject_id,
    professor_id,
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

    insert into public.professors(full_name, email, password_hash, max_students)
    select
      coalesce(nullif(trim(full_name), ''), 'Professor'),
      trim(username),
      password_hash,
      30
    from public.app_users_legacy
    where role = 'professor'
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
  select 'professor'::text, p.id::text, p.full_name, p.email
  from public.professors p, wanted w
  where w.r = 'professor'
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

create or replace function public.admin_create_professor_account(
  p_professor_id text,
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
  v_professor_id uuid;
begin
  insert into public.professors(full_name, email, password_hash, max_students)
  values (
    trim(p_full_name),
    trim(p_username),
    extensions.crypt(trim(p_password), extensions.gen_salt('bf')),
    least(greatest(coalesce(p_max_students, 30), 1), 300)
  )
  on conflict (email) do update
    set full_name = excluded.full_name,
        max_students = excluded.max_students
  returning id into v_professor_id;

  return v_professor_id::text;
end;
$$;

create or replace function public.admin_create_subject_offering(
  p_professor_id text,
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
    subject_id, professor_id, section_id, school_year, semester, is_active,
    beacon_uuid, beacon_name
  )
  values (
    v_subject_id,
    trim(p_professor_id)::uuid,
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
      and professor_id = trim(p_professor_id)::uuid
      and section_id = v_section_id
    order by created_at desc
    limit 1;
  end if;

  -- Persist admin-configured beacon (used by professor app when starting a session).
  update public.subject_offerings
  set
    beacon_uuid = nullif(trim(p_beacon_uuid), ''),
    beacon_name = nullif(trim(p_beacon_name), '')
  where id = v_offering_id;

  return v_offering_id;
end;
$$;

create or replace function public.get_subject_offerings_view(
  p_professor_id text default null
)
returns table(
  id uuid,
  subject_id uuid,
  section_id uuid,
  subject_code text,
  subject_title text,
  section text,
  professor_id uuid,
  professor_name text,
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
    so.professor_id,
    p.full_name as professor_name,
    so.beacon_uuid,
    so.beacon_name
  from public.subject_offerings so
  join public.subjects sub on sub.id = so.subject_id
  join public.sections sec on sec.id = so.section_id
  join public.professors p on p.id = so.professor_id
  where so.is_active = true
    and (p_professor_id is null or so.professor_id = trim(p_professor_id)::uuid)
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
  professor_id uuid,
  professor_name text,
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
    so.professor_id,
    p.full_name,
    so.beacon_uuid,
    so.beacon_name
  from public.student_subject_enrollments sse
  join public.subject_offerings so on so.id = sse.subject_offering_id
  join public.subjects sub on sub.id = so.subject_id
  join public.sections sec on sec.id = so.section_id
  join public.professors p on p.id = so.professor_id
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
  professor_id uuid,
  professor_name text,
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
    p.id as professor_id,
    p.full_name as professor_name,
    sub.subject_code,
    sub.subject_title,
    sec.section_name as section
  from public.student_subject_enrollments sse
  join public.students s on s.id = sse.student_id
  join public.subject_offerings so on so.id = sse.subject_offering_id
  join public.professors p on p.id = so.professor_id
  join public.subjects sub on sub.id = so.subject_id
  join public.sections sec on sec.id = so.section_id
  order by s.full_name, sub.subject_code, sec.section_name;
$$;

create or replace function public.get_admin_attendance_report(
  p_from timestamptz default null,
  p_to timestamptz default null,
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
  professor_id uuid,
  professor_name text,
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
  join public.professors p on p.id = so.professor_id
  join public.students st on st.id = ar.student_id
  where (p_from is null or ar.marked_at >= p_from)
    and (p_to is null or ar.marked_at <= p_to)
    and (p_professor_id is null or so.professor_id = trim(p_professor_id)::uuid)
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
  elsif trim(p_role) = 'professor' then
    update public.professors
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
  where so.professor_id = trim(p_professor_id)::uuid
  order by sess.started_at desc;
$$;

-- OUT/return columns changed vs older DBs; Postgres forbids CREATE OR REPLACE for that.
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
    and so.professor_id = trim(p_professor_id)::uuid
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
  professor_name text,
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
  join public.professors p on p.id = so.professor_id
  where ar.student_id = trim(p_student_id)::uuid
  order by ar.marked_at desc;
$$;

create or replace function public.clear_professor_history(
  p_professor_id text
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
    and so.professor_id = trim(p_professor_id)::uuid;

  delete from public.attendance_sessions sess
  using public.subject_offerings so
  where sess.subject_offering_id = so.id
    and so.professor_id = trim(p_professor_id)::uuid;
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
grant execute on function public.admin_create_professor_account(text, text, text, text, int) to anon, authenticated;
grant execute on function public.admin_create_subject_offering(text, text, text, text, text, text) to anon, authenticated;
grant execute on function public.get_subject_offerings_view(text) to anon, authenticated;
grant execute on function public.admin_assign_student_to_offering(text, uuid) to anon, authenticated;
grant execute on function public.get_admin_enrollments() to anon, authenticated;
grant execute on function public.get_student_dashboard(text) to anon, authenticated;
grant execute on function public.get_admin_attendance_report(timestamptz, timestamptz, text, text, text) to anon, authenticated;
grant execute on function public.update_display_name(text, text, text) to anon, authenticated;
grant execute on function public.get_professor_session_history(text) to anon, authenticated;
grant execute on function public.get_professor_session_attendees(text, uuid) to anon, authenticated;
grant execute on function public.get_session_device_anomalies(uuid) to anon, authenticated;
grant execute on function public.get_student_attendance_history(text) to anon, authenticated;
grant execute on function public.clear_professor_history(text) to anon, authenticated;
grant execute on function public.clear_student_history(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.admins enable row level security;
alter table public.professors enable row level security;
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
drop policy if exists "open professors read" on public.professors;
create policy "open professors read" on public.professors for select to anon using (true);
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
