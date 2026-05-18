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
