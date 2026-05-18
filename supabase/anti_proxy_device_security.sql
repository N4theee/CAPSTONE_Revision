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
