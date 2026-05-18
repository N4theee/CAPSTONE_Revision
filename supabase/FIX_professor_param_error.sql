-- =============================================================================
-- FIX: ERROR 42P13 "cannot change name of input parameter p_professor_id"
-- Run this in Supabase SQL Editor, then re-run RUN_ALL_ATTENDXIMITY.sql
-- (or run ble_attendance_schema.sql + 99_professor_rpc_compat.sql)
-- =============================================================================

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

notify pgrst, 'reload schema';
