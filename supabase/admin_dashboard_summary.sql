-- Install after the attendance and exam schemas. Uses existing read policies.
create or replace function public.admin_dashboard_summary()
returns jsonb language sql stable security invoker set search_path = public as $$
select jsonb_build_object(
  'enrollment_sections', coalesce((
    select jsonb_agg(x) from (
      with groups as (
        select s.section_name, count(*) as value,
          row_number() over (order by count(*) desc, s.section_name) as position
        from student_subject_enrollments e
        join subject_offerings o on o.id = e.subject_offering_id
        join sections s on s.id = o.section_id
        group by s.section_name
      )
      select case when position <= 5 then section_name else 'Other sections' end as label,
        sum(value) as value
      from groups group by case when position <= 5 then section_name else 'Other sections' end
      order by sum(value) desc
    ) x
  ), '[]'::jsonb),
  'exam_statuses', coalesce((
    select jsonb_agg(x) from (
      select status as label, count(*) as value from exam_sessions
      group by status order by status
    ) x
  ), '[]'::jsonb),
  'attendance_daily', coalesce((
    select jsonb_agg(x order by x.day) from (
      select (marked_at at time zone 'Asia/Shanghai')::date as day, count(*) as value
      from attendance_records
      where marked_at >= (((now() at time zone 'Asia/Shanghai')::date - 6)::timestamp
        at time zone 'Asia/Shanghai')
      group by (marked_at at time zone 'Asia/Shanghai')::date
    ) x
  ), '[]'::jsonb),
  'activity', coalesce((
    select jsonb_agg(x order by x.event_at desc) from (
      select * from (
        select 'Teacher registered' as title, full_name as detail, created_at as event_at, 'teachers' as destination from teachers
        union all
        select 'Class created', coalesce(beacon_name, 'Class section'), created_at, 'classes' from subject_offerings
        union all
        select 'Student enrolled', s.full_name, e.created_at, 'enrollments' from student_subject_enrollments e join students s on s.id = e.student_id
        union all
        select 'Exam created', exam_title, created_at, 'exams' from exam_sessions
        union all
        select 'Attendance recorded', s.full_name, a.marked_at, 'records' from attendance_records a join students s on s.id = a.student_id
      ) events order by event_at desc limit 12
    ) x
  ), '[]'::jsonb)
);
$$;
grant execute on function public.admin_dashboard_summary() to anon, authenticated;
