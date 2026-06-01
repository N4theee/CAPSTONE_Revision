-- =============================================================================
-- Attendximity — Exam Sessions (BLE proximity exams)
-- =============================================================================
-- Run in Supabase SQL Editor AFTER the core schema (ble_attendance_schema.sql
-- or FRESH_INSTALL / RUN_ALL_ATTENDXIMITY). Idempotent where possible.
-- Does not modify attendance tables, RPCs, or BLE attendance logic.
-- =============================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- 1) exam_sessions
-- ---------------------------------------------------------------------------
create table if not exists public.exam_sessions (
  id uuid primary key default gen_random_uuid(),
  subject_offering_id uuid not null references public.subject_offerings(id) on delete restrict,
  teacher_id uuid not null references public.teachers(id) on delete restrict,
  exam_title text not null,
  exam_code text not null unique,
  ble_uuid text not null,
  rssi_threshold integer not null default -85,
  grace_period_seconds integer not null default 30,
  status text not null default 'scheduled',
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  constraint exam_sessions_status_check
    check (status in ('scheduled', 'active', 'paused', 'ended', 'cancelled'))
);

-- Allow paused on existing installs
alter table public.exam_sessions drop constraint if exists exam_sessions_status_check;
alter table public.exam_sessions add constraint exam_sessions_status_check
  check (status in ('scheduled', 'active', 'paused', 'ended', 'cancelled'));

-- ---------------------------------------------------------------------------
-- 2) exam_attempts
-- ---------------------------------------------------------------------------
create table if not exists public.exam_attempts (
  id uuid primary key default gen_random_uuid(),
  exam_session_id uuid not null references public.exam_sessions(id) on delete restrict,
  student_id uuid not null references public.students(id) on delete restrict,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  status text not null default 'in_progress',
  exam_score numeric not null default 0,
  completion_seconds integer,
  violation_count integer not null default 0,
  unique (exam_session_id, student_id),
  constraint exam_attempts_status_check
    check (status in ('in_progress', 'completed', 'flagged', 'auto_ended'))
);

-- ---------------------------------------------------------------------------
-- 3) exam_proximity_logs
-- ---------------------------------------------------------------------------
create table if not exists public.exam_proximity_logs (
  id uuid primary key default gen_random_uuid(),
  exam_attempt_id uuid not null references public.exam_attempts(id) on delete restrict,
  student_id uuid not null references public.students(id) on delete restrict,
  exam_session_id uuid not null references public.exam_sessions(id) on delete restrict,
  rssi integer,
  is_in_range boolean not null default false,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 4) exam_alerts
-- ---------------------------------------------------------------------------
create table if not exists public.exam_alerts (
  id uuid primary key default gen_random_uuid(),
  exam_session_id uuid not null references public.exam_sessions(id) on delete restrict,
  exam_attempt_id uuid references public.exam_attempts(id) on delete restrict,
  student_id uuid not null references public.students(id) on delete restrict,
  alert_type text not null,
  message text,
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  constraint exam_alerts_alert_type_check
    check (alert_type in ('out_of_range', 'returned_in_range', 'auto_ended'))
);

-- ---------------------------------------------------------------------------
-- 5) exam_rankings
-- ---------------------------------------------------------------------------
create table if not exists public.exam_rankings (
  id uuid primary key default gen_random_uuid(),
  exam_session_id uuid not null references public.exam_sessions(id) on delete restrict,
  student_id uuid not null references public.students(id) on delete restrict,
  exam_score numeric not null default 0,
  speed_points numeric not null default 0,
  violation_penalty numeric not null default 0,
  overall_score numeric not null default 0,
  rank_number integer,
  remarks text,
  created_at timestamptz not null default now(),
  unique (exam_session_id, student_id)
);

-- ---------------------------------------------------------------------------
-- Indexes (exam_session_id, student_id, subject_offering_id, status)
-- ---------------------------------------------------------------------------
create index if not exists idx_exam_sessions_offering
  on public.exam_sessions(subject_offering_id);
create index if not exists idx_exam_sessions_teacher
  on public.exam_sessions(teacher_id);
create index if not exists idx_exam_sessions_status
  on public.exam_sessions(status);

create index if not exists idx_exam_attempts_session
  on public.exam_attempts(exam_session_id);
create index if not exists idx_exam_attempts_student
  on public.exam_attempts(student_id);
create index if not exists idx_exam_attempts_status
  on public.exam_attempts(status);

create index if not exists idx_exam_proximity_logs_session
  on public.exam_proximity_logs(exam_session_id);
create index if not exists idx_exam_proximity_logs_attempt
  on public.exam_proximity_logs(exam_attempt_id);
create index if not exists idx_exam_proximity_logs_student
  on public.exam_proximity_logs(student_id);

create index if not exists idx_exam_alerts_session
  on public.exam_alerts(exam_session_id);
create index if not exists idx_exam_alerts_student
  on public.exam_alerts(student_id);
create index if not exists idx_exam_alerts_attempt
  on public.exam_alerts(exam_attempt_id);

create index if not exists idx_exam_rankings_session
  on public.exam_rankings(exam_session_id);
create index if not exists idx_exam_rankings_student
  on public.exam_rankings(student_id);

-- ---------------------------------------------------------------------------
-- Unique exam code generator (EXM-ABCDE)
-- ---------------------------------------------------------------------------
create or replace function public.generate_unique_exam_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_suffix text;
  v_chars constant text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  v_i integer;
  v_pick integer;
begin
  loop
    v_suffix := '';
    for v_i in 1..5 loop
      v_pick := 1 + floor(random() * length(v_chars))::integer;
      v_suffix := v_suffix || substr(v_chars, v_pick, 1);
    end loop;
    v_code := 'EXM-' || v_suffix;
    exit when not exists (
      select 1
      from public.exam_sessions es
      where es.exam_code = v_code
    );
  end loop;
  return v_code;
end;
$$;

grant execute on function public.generate_unique_exam_code() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS (same open anon pattern as attendance tables)
-- ---------------------------------------------------------------------------
alter table public.exam_sessions enable row level security;
alter table public.exam_attempts enable row level security;
alter table public.exam_proximity_logs enable row level security;
alter table public.exam_alerts enable row level security;
alter table public.exam_rankings enable row level security;

drop policy if exists "open exam_sessions rw" on public.exam_sessions;
create policy "open exam_sessions rw"
  on public.exam_sessions
  for all
  to anon
  using (true)
  with check (true);

drop policy if exists "open exam_attempts rw" on public.exam_attempts;
create policy "open exam_attempts rw"
  on public.exam_attempts
  for all
  to anon
  using (true)
  with check (true);

drop policy if exists "open exam_proximity_logs rw" on public.exam_proximity_logs;
create policy "open exam_proximity_logs rw"
  on public.exam_proximity_logs
  for all
  to anon
  using (true)
  with check (true);

drop policy if exists "open exam_alerts rw" on public.exam_alerts;
create policy "open exam_alerts rw"
  on public.exam_alerts
  for all
  to anon
  using (true)
  with check (true);

drop policy if exists "open exam_rankings rw" on public.exam_rankings;
create policy "open exam_rankings rw"
  on public.exam_rankings
  for all
  to anon
  using (true)
  with check (true);

-- Supabase Realtime (teacher Monitor Exam alert stream)
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'exam_alerts'
     ) then
    alter publication supabase_realtime add table public.exam_alerts;
  end if;
exception
  when others then
    raise notice 'Could not add exam_alerts to supabase_realtime: %', sqlerrm;
end $$;

notify pgrst, 'reload schema';
