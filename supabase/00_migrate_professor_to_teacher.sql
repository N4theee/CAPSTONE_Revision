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
