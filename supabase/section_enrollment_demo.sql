-- OPTIONAL TEST DATA ONLY. Run after the two required section SQL files.
-- Replace the NULL below with an existing teacher UUID from Supabase Table Editor → teachers.
-- This creates a clearly labeled test curriculum/section, NOT school approval
-- of the researched curriculum. No students or devices are created/enrolled.
begin;
do $$
declare
  v_teacher_id uuid := NULL; -- e.g. 'your-existing-teacher-uuid'::uuid
  v_curriculum uuid; v_legacy uuid; v_section uuid; v_term uuid;
  v_subject uuid; v_offering uuid;
begin
  if v_teacher_id is null or not exists(select 1 from public.teachers where id=v_teacher_id) then
    raise exception 'Replace v_teacher_id with an existing teacher UUID before running this optional demo.';
  end if;
  insert into public.school_curricula(program,grade,version,approved)
    values('ICT',11,'TEST ONLY - two subjects',false)
    on conflict(program,grade,version) do nothing;
  select id into v_curriculum from public.school_curricula where program='ICT' and grade=11 and version='TEST ONLY - two subjects';
  insert into public.school_curriculum_subjects(curriculum_id,subject_id,semester)
    select v_curriculum,id,0 from public.subjects where subject_code in ('DRAFT-11-ICT-01','DRAFT-11-ICT-02')
    on conflict(curriculum_id,subject_id) do nothing;
  if (select count(*) from public.school_curriculum_subjects where curriculum_id=v_curriculum)<>2 then
    raise exception 'Apply section_curriculum_drafts.sql first.';
  end if;
  update public.school_curricula set approved=true where id=v_curriculum;
  insert into public.sections(section_name) values('TEST ONLY - ICT 11-A (2026-2027)')
    on conflict(section_name) do nothing;
  select id into v_legacy from public.sections where section_name='TEST ONLY - ICT 11-A (2026-2027)';
  insert into public.school_sections(section_id,school_year,grade,program,capacity,adviser_id)
    values(v_legacy,'2026-2027',11,'ICT',45,v_teacher_id)
    on conflict(section_id) do nothing;
  select id into v_section from public.school_sections where section_id=v_legacy;
  insert into public.school_section_terms(school_section_id,curriculum_id,semester)
    values(v_section,v_curriculum,1) on conflict(school_section_id,semester) do nothing;
  select id into v_term from public.school_section_terms where school_section_id=v_section and semester=1;
  if exists(select 1 from public.school_section_terms where id=v_term and (ready or closed)) then
    raise notice 'Demo already exists. Its assignments and beacons were preserved.';
    return;
  end if;
  for v_subject in select subject_id from public.school_curriculum_subjects where curriculum_id=v_curriculum loop
    select offering_id into v_offering from public.school_teaching_assignments where term_id=v_term and subject_id=v_subject;
    if v_offering is null then
      insert into public.subject_offerings(subject_id,teacher_id,section_id,school_year,semester,beacon_uuid,beacon_name,is_active)
        select v_subject,v_teacher_id,v_legacy,'2026-2027','1',gen_random_uuid()::text,'TEST - '||subject_code,false
        from public.subjects where id=v_subject returning id into v_offering;
      insert into public.school_teaching_assignments(term_id,subject_id,offering_id) values(v_term,v_subject,v_offering);
    end if;
  end loop;
  update public.subject_offerings set is_active=true where id in(select offering_id from public.school_teaching_assignments where term_id=v_term);
  update public.school_section_terms set ready=true where id=v_term;
end $$;
commit;
