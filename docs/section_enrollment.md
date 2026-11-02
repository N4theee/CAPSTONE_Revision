# Section enrollment setup

This update adds fixed section placement without replacing the existing
subject-class enrollments. BLE scanning/broadcasting, device identity, secure
student login, attendance marking, exam joining and exam monitoring continue
to use the existing offering IDs and security functions.

## Apply to your existing Supabase project

Run these files in order in **Supabase → SQL Editor**:

1. `supabase/section_enrollment.sql`
2. `supabase/section_curriculum_drafts.sql`

Apply only these additive updates to an existing project. Do not rerun the
fresh-install `NEW_PROJECT_SETUP.sql` over an existing secured deployment.
The new migration expects the existing student, teacher, admin, subject,
section, offering, enrollment, attendance and exam tables. Existing password
hashes must use the app's bcrypt account creation flow for admin verification.
No administrator password or service-role key belongs in the SQL files.

The migration can be rerun. It does not move existing students, change their
device records, or delete attendance/exam history. The draft seed can also be
rerun: it does not duplicate subjects, reset semester choices or change an
approved curriculum.

For a quick test, optionally run `supabase/section_enrollment_demo.sql` after
replacing its `v_teacher_id` placeholder with an existing teacher UUID. It
creates a clearly labeled 45-seat test section with two subjects and a ready
Semester 1. It does not enroll students or mark the researched templates as
approved. Its two full-year subject choices are test assumptions only.

## Draft subjects

The seed contains all 93 subject entries supplied for eight combinations of
Grade 11/12 and ICT, GAS, EIM and HE. Research labels, including slash names,
are preserved. Codes beginning `DRAFT-` distinguish these research records
from existing subjects. HUMSS is available as a program but has no invented
curriculum; create it after receiving the school's subject list.

No semester distribution, specialization choices, section counts or official
curriculum approval is assumed. All templates begin unapproved with
unconfirmed semester values. Each subject can be assigned Semester 1,
Semester 2, or Full year (included in both), or excluded from a draft.
For a new version, copy a curriculum and modify its draft. Approved templates
are frozen. Existing global subject editing still controls subject names.

## Admin workflow

Open **Enrollments**:

1. **Curricula:** open a draft, exclude subjects the school does not offer and
   confirm each remaining subject's semester. Approve only after reviewing it.
   For testing, create a separate version clearly named `TEST ONLY` and use
   an explicit test semester distribution; keep the research originals draft.
2. **Sections:** create a section with school year, grade, program, capacity
   (default 45), and optional adviser. Use consecutive years such as
   `2026-2027`. The existing section name is year-qualified to prevent historical
   classes from being reused in a later school year.
3. Open **Subjects & Teachers**, choose **Set up semester**, and select an
   approved matching curriculum. Assign a teacher to every semester subject,
   then **Make semester ready**. Each assignment creates an inactive existing
   subject offering with its own generated beacon UUID; readiness activates it.
4. Use **Student requests** or **Enroll students**. Choose school year, grade,
   program, section and a ready semester. Add one or multiple students, review
   the subjects/teachers and confirm. The server verifies administrator
   credentials, capacity and conflicts and writes every placement/enrollment
   in one transaction. A failure saves none of the batch.

Administrator credentials are requested for each mutation because the app
uses custom account login rather than Supabase Auth roles. Credentials are
not saved to preferences by this feature. New metadata tables grant read
access following the existing app's custom-login read model; client writes
are restricted to credential-verified operations. This does not migrate or
replace the existing project's broader authentication/RLS model.

Section placement is unique per student and school year. Enrolling the same
student in the same semester again does not duplicate records or consume a
second seat. Requested grade/program are preferences; the admin approves the
actual placement. Section directories and student choices are paged.

## Student and teacher app

New student registration requires a requested grade/program. Registration and
the request are saved together using a wrapper around the installed existing
registration function. The following login still uses device UUID,
fingerprint and the existing secure device-binding RPC. A missing migration
fails registration explicitly instead of discarding the request.

Students see **Awaiting section assignment** and their requested program, then
their assigned section, grade, program and school year once placed. Their
subject cards load from existing subject enrollments and show the teacher.
Teacher dashboards filter assigned subjects by section. Existing teacher
class-detail screens, rosters, attendance and exams remain in use.

An existing student with subject enrollments but no placement can still use
their existing courses. Their dashboard identifies the pending admin review.
An unavailable new metadata table does not block existing course access.

## Existing students and later semesters

No automatic inference or transfer is performed. Active legacy enrollments
in a different section block new placement. Review those records and resolve
the student's actual section deliberately; do not delete attendance or exam
records to force a placement. **Class Sections** remains available to review
legacy subject classes. A dedicated transfer/reassignment workflow is not
included: ready teacher assignments are frozen to preserve exam ownership.

Set up Semester 2 separately. Enroll the existing section members in its ready
term; they retain the same annual placement and get the new subject offerings.
This is explicit, so merely preparing a future semester does not enroll anyone.

**Close semester** removes that semester's offerings from active dashboards
without deleting enrollments or history. Closure is blocked while attendance
or exams are active/paused, and closed managed classes cannot start new
sessions. Scheduled exams should be resolved before closing a semester; they
cannot subsequently start in a closed class. Closing does not reassign teachers
or rewrite beacons. Legacy offerings skip the new semester-start guard.

## Validation

- `test/section_enrollment_sql.cjs` executes the migration and seed twice in
  isolated PostgreSQL with real pgcrypto. It checks draft counts, approval,
  teacher readiness, atomic batches, capacity, duplicates, conflicts, client
  write guards, semester closure, next-semester enrollment and preservation
  of legacy device, attendance, exam and enrollment records.
- `test/section_enrollment_test.dart` checks request forwarding, missing-setup
  behavior, secure device-login arguments/rejections, scoped metadata queries
  and one-operation bulk enrollment.
- Admin workflow tests cover section roster/teacher views and the enrollment
  preview/credential boundary. Responsive tests cover app screens.

To run the isolated SQL test, install `@electric-sql/pglite` in a temporary
directory and pass its absolute package directory as the argument:

```
node test/section_enrollment_sql.cjs <absolute-path-to-pglite-package>
```

Local tests do not connect to your deployed Supabase database or establish a
hardware BLE test result. After applying the SQL, test with one section,
one teacher and a separate student account/device before rolling out broadly.

Class Sections and Enrollments now share the section setup directory. Use Review legacy subject classes to inspect earlier subject classes. Failed placements keep the directory or section visible and offer a read-only review of the selected students’ existing enrollments.
