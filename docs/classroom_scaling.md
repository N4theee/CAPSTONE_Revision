# Classroom attendance and exam updates

## Database setup

Run `supabase/attendance_realtime.sql` in the project's Supabase SQL Editor.
It adds attendance records to the Realtime publication without changing access
policies. Until applied, professor attendance still refreshes every 30 seconds.
The combined student status query uses the existing attendance foreign key;
it needs no new database function.

## Behavior

- Student attendance checks use one request every 10–15 seconds, after the
  previous request completes. They pause outside the foreground and refresh
  on return. Confirmed attendance stays confirmed for that session.
- Dashboard notification polling uses the same interval and pauses while the
  attendance screen is open to avoid duplicate session checks. Notification
  polling also pauses outside the foreground.
- Professor attendance subscribes to changes for the current session, debounces
  bursts, and refreshes every 30 seconds as a fallback. Subscriptions are removed
  on session end and screen disposal.
- Immediate exams are saved unopened, Bluetooth advertising is prepared, and
  then the exam is activated. Failed startup leaves a saved exam available for
  retry in Exam Active. Do not create a replacement exam just to retry Bluetooth.
- Scheduled exams now require the professor to start them in Exam Active.
  Student code validation cannot activate a scheduled exam without its beacon.
- The exam beacon belongs to a shared session service, survives route changes,
  and checks the session and advertising state every 15 seconds in the
  foreground. It checks again on return to the app. End, cancel, sign-out, or a
  detected removed/expired/terminal session stops it. Remote changes can take
  up to the next check to be detected. Network failure defers that verification.
- One professor phone supports one exam beacon at a time. Starting attendance
  advertising while an exam beacon is owned is blocked to avoid replacing it.
- Existing signal thresholds and beacon matching rules are unchanged.

## Verify with phones before rollout

1. Create an immediate exam on the professor phone. Confirm advertising is ready
   before sharing the code. Join from a student phone while staying on Exam Active.
2. Repeat with Exam Monitor visible, and after navigating back to the exam hub
   and professor dashboard. Students should detect the same beacon on each screen.
3. Turn Bluetooth off and try starting an exam. Confirm a clear failure and that
   students cannot activate it by entering the code. Turn Bluetooth on and retry
   the saved exam through Exam Active.
4. Pause/resume, end/cancel, and sign out. Confirm the beacon stops on cleanup.
   Return from another app and confirm recovery. Locked-screen and background
   advertising are not guaranteed by this change.
5. Mark attendance from several student devices and verify professor live
   updates after enabling the publication. Disconnect/reconnect the professor's
   network and check fallback refresh. Confirm attendance stays marked when a
   student returns to the app, and a new session requires a new attendance mark.
6. Progress from one classroom to one floor, then simulate 720 students and 16
   professors. Measure latency, failed requests, and Wi-Fi behavior. Automated
   regression tests do not establish building-wide capacity.
