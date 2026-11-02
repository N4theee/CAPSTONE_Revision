# Device Management

Apply `supabase/device_management.sql` in Supabase SQL Editor **after** the
existing attendance/device security schema. Use this additive migration for an
existing project; do not rerun a fresh-install script. It is safe to rerun and
does not reset devices until an administrator confirms a reset.

## Administrator workflow

Open **Device Management** under User Management and search for a student.

- **Reset a student’s device:** revokes the student's device bindings and login
  session so their next successful login can bind the intended replacement phone.
- **Release a device for another account:** releases the selected phone from the
  displayed student and revokes the matching login. Another account can bind this
  phone if that account has no other current device; reset its old binding first
  when necessary. Releasing a phone does not erase app data on the physical phone.

Each reset requires an administrator username/password and one of Lost phone,
Broken phone, Replacement phone, Device reassignment, or Other. Other requires an
explanation of at least five characters. An optional explanation/approval
reference can record the teacher's paper or letter reference. No upload or
active-exam restriction is added. Account, enrollment, attendance and exam data
are retained. Existing attempts are not ended or edited by a reset.

The server validates the administrator's bcrypt password for **each** reset and
history request. Passwords are held only by the dialog, cleared after submission
or rejection, and never stored in preferences. Failed submissions keep the
reason/explanation available for retry but require the password again.

## Reset history and integrity

**View reset history** requires administrator credentials and loads 25 entries
per page across all students. Each entry records server time, verified admin ID,
admin name/username, student ID/name/number, action, reason, explanation and the
previous device IDs/names. Names are snapshots and survive later name edits.
The new history table has no client read/write grants; it is read through the
credential-verified function. Reset, session revocation and audit insertion are
one transaction. Student/device locks serialize reset against the login RPC.
Direct client writes to device bindings and login sessions are revoked; existing
registration/login/sign-out SECURITY DEFINER functions continue to work.

The app checks a saved student's session at startup, every 15 seconds in the
foreground, and on resume. A confirmed invalid result clears the saved login and
removes student routes. Offline/missing-setup errors retry without falsely
reporting a reset. The old phone is not remotely erased and cannot receive an
immediate sign-out while offline. Existing secure attendance device validation
rejects the revoked binding on the server.

This feature does not replace the app's custom authentication architecture or
its broader existing anonymous database policies. In particular it is not a new
server authorization layer for all exam-table operations. Deploy the updated
student app as well as the migration for the foreground sign-out behavior.
Do not reapply older scripts that restore open device/session write grants.

## Validation

- `test/device_management_test.dart`: password/reason validation, Other reason,
  wrong-password retry, release targeting/cancellation, history credentials,
  missing setup, narrow layout, saved-session revocation and offline behavior.
- `test/device_management_sql.cjs`: executes the real baseline and migration
  twice in isolated PostgreSQL with pgcrypto, exercises credential/permission
  failures, replacement/reassignment/same-phone rebinding, revocation, audit
  records and preservation of academic data including an active exam.

Run the SQL test with an absolute path to an installed `@electric-sql/pglite`
package: `node test/device_management_sql.cjs <package-path>`. It never connects
to the live Supabase database. After applying the migration, verify with separate
admin and student devices, including reset while the old phone is offline.
