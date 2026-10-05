# ProXamity admin panel

The existing Admin Panel login opens the new dashboard. Wide screens show a
collapsible sidebar; narrow screens use a navigation drawer.

## One-time database setup

Run `supabase/admin_panel_scaling.sql` to enable the new class-creation form and
its concurrency protection and query indexes. Run
`supabase/admin_dashboard_summary.sql` for charts and activity if it has not
already been applied. Apply both files in the Supabase SQL Editor after the
attendance and exam schemas are installed. The function aggregates enrollments,
exam statuses, seven days of recorded attendance, and recent school events.
It uses existing table read policies. Counts and directory pages continue to
work if this optional summary function is unavailable.

## Pages and actions

| Page | Functions |
| --- | --- |
| Dashboard | Exact database counts, summary charts, recent records, quick actions |
| Students | Paged directory, name editing, enrollment/attendance/attempt details |
| Teachers | Paged directory, teacher creation, name editing, assigned classes and exams |
| Admins | Existing administrator directory and name editing |
| Subjects | Create, edit, and view assigned class sections |
| Class Sections | Searchable teacher/subject/section choices, optional new section, automatic beacon identifier, enrolled students, teacher/beacon editing, active/inactive setting |
| Enrollments | Paged student/active-class choice pickers and removal workflow and individual removal with confirmation |
| Exams | Teacher-owned exam oversight, attempts, questions, and incidents |
| Question Bank | Server-side teacher, subject, and exam filters; review existing exam questions and answer choices; no independent global question pool |
| Attempt Logs | Server-side teacher, subject, and exam filters; scores, durations, violations, paged Bluetooth monitoring history |
| Attendance Sessions | Session directory and recorded attendance details |
| Attendance Records | Paged, searchable records and date filtering |
| Analytics & Reports | Attendance, exam, result, and incident CSV reports; existing class-based attendance filters |
| Settings | School-name and school-year display preferences saved to this browser |
| Activity Logs | Recent events derived from registration, enrollment, exam, and attendance timestamps |

Directory searches filter the loaded page. Reports export every page matching
the selected date/status filters and search text. CSV fields are quoted and
formula-like text is escaped. Password hashes are never requested.

Class edits first check for active attendance or active/paused exams and refuse
changes while those sessions are running. User disabling is not exposed because
the existing account schema does not have an account activation field. Exam
creation remains with teachers. The activity feed is derived from records and
does not track every administrative edit.

The enrollment chart groups class registrations, including students registered
in multiple offerings. It is not a count of unique students. The attendance
chart shows recorded attendance and does not infer historical absences from the
current enrollment roster.

## Validation

`test/admin_panel_test.dart` covers navigation, screen sizes and enlarged text,
subject creation, attempt monitoring, failure/retry behavior, and query scoping.
The screenshot in `artifacts/admin-dashboard.png` uses test data. Verify your
actual Supabase queries and permissions after applying the summary function.

## Concurrent use

The admin pages do not run background polling or subscribe to the student event
stream. Directories and searchable dropdowns load 25 rows at a time. Dropdown
search waits 350 milliseconds after typing and filters in Postgres. Question
Bank and Attempt Logs filter before pagination, so matches outside the current
page are included. Changing teacher or subject clears the dependent exam filter.
Teacher creation no longer loads student/class/enrollment lists, and opening
Activity Logs only fetches its summary. CSV reports are explicitly requested and
fetch larger pages; narrow the date range for large exports.

The new class RPC runs in one transaction and serializes only conflicting
creates for the same teacher, subject, and section. Duplicate requests fail
without modifying the existing subject title or Bluetooth configuration.
The SQL uses the existing table permissions rather than elevating callers.
These changes reduce competing requests; no deployed database load test has
been performed, so they do not establish a guaranteed simultaneous-user limit.

Enrollments now opens a subject directory with enrolled section and teacher summaries and enrollment counts. Select a subject, then a section and its handling teacher, to load the paged student roster. Question Bank opens an exam directory; selecting an exam loads only its questions in question order. Teacher, subject, exam, and date filters apply to the exam directory.
