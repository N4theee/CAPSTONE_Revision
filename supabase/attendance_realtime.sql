-- Run once in the Supabase SQL Editor to enable professor live attendance.
-- Safe to run again. Keeps existing table permissions and policies.
begin;
alter table public.attendance_records replica identity full;
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'attendance_records'
  ) then
    alter publication supabase_realtime add table public.attendance_records;
  end if;
end $$;
commit;
