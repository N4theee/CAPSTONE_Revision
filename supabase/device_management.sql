-- Apply after the existing attendance/device security setup. Safe to rerun.
begin;

create table if not exists public.device_reset_history (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.admins(id) on delete restrict,
  admin_name text not null,
  admin_username text not null,
  student_id uuid not null references public.students(id) on delete restrict,
  student_name text not null,
  student_number text,
  action text not null check (action in ('reset_student_device', 'release_device')),
  reason text not null check (reason in ('Lost phone','Broken phone','Replacement phone','Device reassignment','Other')),
  details text not null default '',
  devices jsonb not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_device_reset_history_recent on public.device_reset_history(created_at desc,id);
alter table public.device_reset_history enable row level security;
revoke all on public.device_reset_history from public, anon, authenticated;
-- All binding/session writes must use the existing SECURITY DEFINER login,
-- registration and sign-out functions or the credential-verified reset below.
revoke insert,update,delete,truncate,references,trigger on public.student_devices, public.student_login_sessions from public,anon,authenticated;

create or replace function public.admin_device_management(
  p_username text, p_password text, p_action text,
  p_student_id uuid default null, p_device_uuid text default null,
  p_reason text default null, p_details text default '', p_page integer default 0
) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_admin public.admins%rowtype;
  v_student public.students%rowtype;
  v_devices jsonb; v_log jsonb; v_rows jsonb;
  v_uuid text := nullif(trim(p_device_uuid),'');
  v_reason text := trim(p_reason); v_details text := trim(coalesce(p_details,''));
  v_count integer; v_session_count integer; v_lock text;
begin
  select * into v_admin from public.admins a
  where lower(trim(a.email))=lower(trim(p_username))
    and a.password_hash=extensions.crypt(trim(p_password),a.password_hash);
  if not found then
    raise exception 'Administrator credentials are required.' using errcode='42501';
  end if;
  if p_action='history' then
    if p_page is null or p_page<0 or p_page>100000 then raise exception 'Invalid history page.'; end if;
    select coalesce(jsonb_agg(to_jsonb(h) order by h.created_at desc,h.id),'[]'::jsonb)
      into v_rows from (select * from public.device_reset_history
        where p_student_id is null or student_id=p_student_id
        order by created_at desc,id limit 25 offset p_page*25) h;
    return jsonb_build_object('rows',v_rows);
  end if;
  if p_action not in ('reset_student_device','release_device') or p_action is null then
    raise exception 'Unknown device action.';
  end if;
  if v_reason is null or v_reason not in ('Lost phone','Broken phone','Replacement phone','Device reassignment','Other') then
    raise exception 'Choose a reset reason.';
  end if;
  if v_reason='Other' and length(v_details)<5 then raise exception 'Explain the other reason (at least 5 characters).'; end if;
  if length(v_details)>1000 then raise exception 'Keep the explanation within 1000 characters.'; end if;
  if p_action='release_device' and v_uuid is null then raise exception 'Select the device to release.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_student_id::text,0));
  select * into v_student from public.students where id=p_student_id for update;
  if not found then raise exception 'Student not found.'; end if;
  -- Lock device UUIDs in a stable order, shared with login, to avoid reset/rebind races.
  for v_lock in select distinct device_uuid from public.student_devices
    where student_id=p_student_id and is_active and not is_revoked
      and (p_action='reset_student_device' or device_uuid=v_uuid) order by device_uuid
  loop
    perform pg_advisory_xact_lock(hashtextextended(v_lock,1));
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'device_uuid',d.device_uuid,
    'device_name',d.device_name,'registered_at',d.registered_at)),'[]'::jsonb)
    into v_devices from public.student_devices d
    where d.student_id=p_student_id and d.is_active and not d.is_revoked
      and (p_action='reset_student_device' or d.device_uuid=v_uuid);
  if p_action='release_device' and jsonb_array_length(v_devices)=0 then
    raise exception 'This device binding changed. Refresh and select the current device.';
  end if;
  update public.student_devices set is_active=false,is_primary=false,is_revoked=true,
    attendance_enabled=false,revoked_at=now()
    where student_id=p_student_id and (is_active or not is_revoked)
      and (p_action='reset_student_device' or device_uuid=v_uuid);
  get diagnostics v_count = row_count;
  -- Include active orphaned login sessions in the audit snapshot before revocation.
  select v_devices || coalesce(jsonb_agg(jsonb_build_object('device_uuid',s.device_uuid,
      'device_name','Login session','signed_in_at',s.signed_in_at)) filter (
      where not exists(select 1 from jsonb_array_elements(v_devices) d where d->>'device_uuid'=s.device_uuid)),'[]'::jsonb)
    into v_devices from public.student_login_sessions s where s.student_id=p_student_id and s.is_active
      and (p_action='reset_student_device' or s.device_uuid=v_uuid);
  update public.student_login_sessions set is_active=false,last_seen_at=now()
    where student_id=p_student_id and is_active
      and (p_action='reset_student_device' or device_uuid=v_uuid);
  get diagnostics v_session_count = row_count;
  if v_count=0 and v_session_count=0 then raise exception 'There is no device binding or active login to reset.'; end if;
  insert into public.device_reset_history(admin_id,admin_name,admin_username,student_id,student_name,
    student_number,action,reason,details,devices)
    values(v_admin.id,v_admin.full_name,v_admin.email,v_student.id,v_student.full_name,
      v_student.student_number,p_action,v_reason,v_details,v_devices)
    returning to_jsonb(device_reset_history.*) into v_log;
  return jsonb_build_object('entry',v_log);
end $$;

create or replace function public.student_device_session_valid(p_student_id uuid,p_device_uuid text)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.student_login_sessions s join public.student_devices d
    on d.student_id=s.student_id and d.device_uuid=s.device_uuid
    where s.student_id=p_student_id and s.device_uuid=p_device_uuid and s.is_active
      and d.is_active and not d.is_revoked and d.is_primary and d.attendance_enabled and d.approval_status='approved');
$$;

-- Serialize login with administrator resets; preserve the existing login contract.
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

  perform pg_advisory_xact_lock(hashtextextended(v_student_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended(v_uuid,1));

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


revoke all on function public.admin_device_management(text,text,text,uuid,text,text,text,integer) from public;
grant execute on function public.admin_device_management(text,text,text,uuid,text,text,text,integer) to anon,authenticated;
revoke all on function public.student_device_session_valid(uuid,text) from public;
grant execute on function public.student_device_session_valid(uuid,text) to anon,authenticated;
notify pgrst, 'reload schema';
commit;
