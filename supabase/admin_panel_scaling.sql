-- Run once in Supabase SQL Editor after the existing attendance/exam schemas.
-- Atomic class creation: a duplicate never rewrites an existing class beacon.
create or replace function public.admin_create_class_section(
  p_teacher_id uuid, p_subject_id uuid, p_section_name text,
  p_beacon_uuid text, p_beacon_name text
) returns uuid
language plpgsql security invoker set search_path = public as $$
declare
  v_section_id uuid;
  v_id uuid;
begin
  if nullif(trim(p_section_name), '') is null or length(trim(p_section_name)) > 80 then
    raise exception 'Enter a section name of 1–80 characters.';
  end if;
  -- Validate the generated UUID before storing it in the existing text column.
  perform p_beacon_uuid::uuid;
  if p_teacher_id is null or p_subject_id is null or p_beacon_uuid is null then
    raise exception 'Teacher, subject, and beacon are required.';
  end if;
  -- Serialize only competing creates for the same teacher/subject/section.
  perform pg_advisory_xact_lock(hashtextextended(
    p_teacher_id::text || ':' || p_subject_id::text || ':' || trim(p_section_name), 0));
  insert into public.sections(section_name) values(trim(p_section_name))
    on conflict(section_name) do nothing returning id into v_section_id;
  if v_section_id is null then
    select id into v_section_id from public.sections where section_name = trim(p_section_name);
  end if;
  if exists(select 1 from public.subject_offerings where teacher_id = p_teacher_id
    and subject_id = p_subject_id and section_id = v_section_id
    and coalesce(school_year, '') = '' and coalesce(semester, '') = '') then
    raise exception 'This class already exists. Open it from Class Sections.' using errcode = '23505';
  end if;
  insert into public.subject_offerings(teacher_id, subject_id, section_id,
    is_active, beacon_uuid, beacon_name)
  values(p_teacher_id, p_subject_id, v_section_id, true, p_beacon_uuid,
    nullif(trim(p_beacon_name), '')) returning id into v_id;
  return v_id;
end;
$$;
grant execute on function public.admin_create_class_section(uuid, uuid, text, text, text) to anon, authenticated;

-- Support server-side exam filters and stable page ordering.
create index if not exists idx_admin_exams_teacher_page on public.exam_sessions(teacher_id, created_at desc, id);
create index if not exists idx_admin_exams_offering_page on public.exam_sessions(subject_offering_id, created_at desc, id);
create index if not exists idx_admin_questions_exam_page on public.exam_questions(exam_session_id, created_at desc, id);
create index if not exists idx_admin_attempts_exam_page on public.exam_attempts(exam_session_id, started_at desc, id);
create index if not exists idx_admin_questions_page on public.exam_questions(created_at desc, id);
create index if not exists idx_admin_attempts_page on public.exam_attempts(started_at desc, id);
create index if not exists idx_admin_students_page on public.students(created_at desc, id);
create index if not exists idx_admin_enrollments_page on public.student_subject_enrollments(created_at desc, id);
