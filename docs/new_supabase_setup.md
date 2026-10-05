# Set up a new Supabase project for ProXamity

This guide installs the current app into an empty database. It does not copy
students, teachers, exams, or records from your old project. The old project
and the app connection remain unchanged until you replace the app configuration.

## 1. Create the account and project

1. Sign up or sign in at https://supabase.com/dashboard.
2. Create an organization if prompted, then choose New project.
3. Give it a name such as ProXamity and choose a database password. This is the
   database password, not the password used to log into your app.
4. Choose a region near the school and wait until the project is ready.
5. Keep the Data API enabled; the app uses it to read tables and call functions.
   If disabled, enable it under Integrations > Data API and expose the public
   schema/tables/functions required by this app.

## 2. Install the whole database

1. Open SQL Editor in the NEW project and create a new query.
2. Open `supabase/NEW_PROJECT_SETUP.sql` from this repository.
3. Copy its ENTIRE contents into the query. Run the whole query, not a selected
   fragment. The file is roughly 1,900 lines.
4. Wait for the result: ProXamity setup complete. Change the default admin
   credentials next.

The installer includes these six files, in dependency order:

1. FRESH_INSTALL_ATTENDXIMITY.sql — accounts, subjects, sections, attendance,
   login functions, student device binding, and the initial administrator.
2. exam_sessions_schema.sql — exam sessions, attempts, monitoring, and alerts.
3. exam_questions_schema.sql — questions, choices, answers, and scoring columns.
4. attendance_realtime.sql — live professor attendance updates.
5. admin_panel_scaling.sql — safe class creation and filtering indexes.
6. admin_dashboard_summary.sql — dashboard charts and activity summaries.

Run either the combined installer OR these six source files in order. Do not
run both. Old professor migration and repair files are not needed for a new
empty database.

The combined installer checks that the public schema is empty and uses one
transaction. If a statement fails, it cannot commit a partial install. Read the
first SQL error; if the editor connection is still in a failed transaction,
run `rollback;` before trying the corrected full installer again. If it reports
that the public schema is not empty, use a fresh project instead of deleting
existing tables.

## 3. Set your own administrator login

The baseline creates the temporary account ADMIN-Nath / 1234567890. In a NEW
SQL Editor query, replace the three placeholders below, then run it:

```sql
update public.admins
set full_name = 'YOUR_NAME',
    email = 'YOUR_ADMIN_USERNAME',
    password_hash = extensions.crypt(
      'YOUR_STRONG_PASSWORD', extensions.gen_salt('bf')
    )
where email = 'ADMIN-Nath'
returning id, full_name, email;
```

The email column currently stores the app login username. The result should
show one administrator. Log in with your NEW username/password. If you need an
apostrophe inside a SQL value, write two apostrophes, for example `O''Brien`.

This app currently uses custom login functions and its admins/teachers/students
tables. Creating users in Supabase Authentication does not create these app
accounts. Create teachers from the admin panel and register students in the app.

## 4. Verify installation

Run this in another SQL Editor query:

```sql
select
  to_regclass('public.students') is not null as students_ready,
  to_regclass('public.exam_questions') is not null as questions_ready,
  to_regclass('public.exam_attempts') is not null as attempts_ready,
  to_regprocedure('public.admin_create_class_section(uuid,uuid,text,text,text)')
    is not null as class_creation_ready,
  to_regprocedure('public.admin_dashboard_summary()')
    is not null as dashboard_ready,
  exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'attendance_records'
  ) as attendance_live_updates_ready;
```

All six columns should be true. Then run:

```sql
select public.admin_dashboard_summary();
```

Empty arrays and zero counts are expected before you add school data.

## 5. Get the app connection details

1. Open the project's Connect panel and copy the Project URL.
2. Open Settings > API Keys. For the app's existing anonKey initialization,
   use the project's legacy anon/public key to keep the current configuration
   approach. Do not copy the service_role or secret key into Flutter.
3. The URL and key must belong to the SAME new project.

The modern publishable key is intended for client apps too. This guide keeps
the current app configuration; migrating key types is a separate change.

Official references:
- https://supabase.com/docs/guides/getting-started/quickstarts/flutter
- https://supabase.com/docs/guides/getting-started/api-keys

## 6. Connect THIS app

Open `lib/config.dart` and replace only these two values:

```dart
static const String supabaseUrl = 'YOUR_NEW_PROJECT_URL';
static const String supabaseKey = 'YOUR_NEW_PROJECT_ANON_PUBLIC_KEY';
```

Leave the other proximity settings alone. `lib/main.dart` imports this file.
The separate `lib/config/supabase_config.dart` file is not used by the current
startup code, so changing only that file will not change the app connection.

Stop the app completely and restart it. Hot reload is insufficient because
Supabase initializes at startup. Sign out of any old saved app account and log
in again; a saved identity from the old database does not exist in the new one.
Rebuild and redistribute the Android/web app to any devices or websites that
must connect to the new project.

For your existing Flutter workspace, launch normally, or use:

```text
flutter run -d chrome
```

## 7. Add school data in a practical order

1. Open the web Admin Panel and log in with your new administrator credentials.
2. Teachers > Create Teacher: create one test teacher account.
3. Subjects > Create Subject: add a subject code and title.
4. Class Sections > Create Class Section: choose the teacher and subject;
   select an existing section or turn on Create a new section. The Bluetooth
   identifier is generated automatically.
5. Register a student in the mobile app.
6. Enrollments > Enroll Student: choose the student and their active class.
7. Log in as the teacher and start an attendance session. Use the student
   phone to check that attendance is recorded and appears for the teacher.
8. Create an exam with questions, start it, and test joining/submitting from a
   student phone. Verify its score and monitoring records in the admin panel.
9. Check Dashboard, Question Bank, and Attempt Logs against those test records.

Bluetooth attendance and exam proximity need supported physical phones; the
web admin panel is for administration and record viewing.

## 8. Understand the setup limits

This installer reproduces the current app schema and permissions; the existing
custom login/open table policies still need a permissions review before using
real student data in a public production deployment. The setup is not proof of
a specific simultaneous-user capacity. Confirm capacity with a deployed load
test after setup.

The combined installer was assembled and checked locally, but has not been
executed against a new hosted Supabase project in this session.
