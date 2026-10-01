# UI and responsiveness update

## Changes
- Shared responsive page widths, adaptive headings, and content-sized cards.
- Course dashboards adapt columns to screen width and text size.
- Subject dashboards keep actions visible on phones and use a sidebar on wide screens.
- Searchable class roster and ranking preview with readable long names.
- Exam history and rankings show full details with wrapping status labels.
- Performance chart supports latest 5, latest 10, or all results, with a readable results list.
- Exam questions and answers scroll together; submit controls remain reachable.
- Multiline question/choice editing and keyboard-aware admin login.
- Attendance history cards grow with their content and larger text.
- Removed historical signal/verification claims that were not backed by stored data.
- Added explicit retry states to dashboards, history, and exam/admin loading flows.
- Admin dropdowns and form actions adapt to narrower layouts.
- Wrapped narrow teacher controls and the out-of-range warning heading.

## Validation
401 tests passed with `flutter test --no-pub` (400 UI checks plus the existing test).
The UI matrix covers 18 screens at widths 320, 360, 390, 600, 768, 1024, and 1440; text scales 1, 1.5, and 2; and short landscape windows. Additional checks cover keyboard insets and history retry behavior. All database responses use local fake fixtures; these tests do not use the live database.

Dart analysis passed without errors or warnings. Representative rendered previews are generated in `build/ui_previews`. The test fonts are optional on non-Windows machines; screenshots are diagnostic, not golden-image assertions.

The optional browser suite is `flutter test --no-pub --platform chrome test/admin_browser_checks.dart`. It stalled after launching Chrome in this environment on two attempts, so web admin runtime validation remains unconfirmed.

Bluetooth hardware, live realtime transitions, and physical-device keyboard behavior still need a device smoke test. The student account/exam-history isolation issue requires a separate backend/authentication fix and is not resolved by this UI update.
