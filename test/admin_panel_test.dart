import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ble_attendance/screens/admin_web_panel_screen.dart';
import 'package:ble_attendance/screens/admin_class_form.dart';
import 'package:ble_attendance/services/admin_data_service.dart';
import 'package:ble_attendance/services/supabase_service.dart';

final _student = {
  'id': 'student-1',
  'full_name': 'Juan Dela Cruz',
  'student_number': '2026-001',
  'email': 'juan',
  'created_at': '2026-10-02T09:00:00Z',
};
final _teacher = {
  'id': 'teacher-1',
  'full_name': 'Nathan Orias',
  'email': 'nathan',
  'max_students': 45,
  'created_at': '2026-10-01T09:00:00Z',
};
final _class = {
  'id': 'class-1',
  'teacher_id': 'teacher-1',
  'subject_id': 'subject-1',
  'section_id': 'section-1',
  'beacon_uuid': '12345678-1234-1234-1234-123456789012',
  'beacon_name': 'IT401',
  'is_active': true,
  'created_at': '2026-10-01T09:00:00Z',
  'subjects': {
    'subject_code': 'IT401',
    'subject_title': 'Application Development',
  },
  'sections': {'section_name': 'BSIT 4A'},
  'teachers': {'full_name': 'Nathan Orias'},
};
final _exam = {
  'id': 'exam-1',
  'exam_title': 'Prelim Examination',
  'exam_code': 'EXM-ABCDE',
  'status': 'active',
  'teacher_id': 'teacher-1',
  'subject_offering_id': 'class-1',
  'created_at': '2026-10-02T09:00:00Z',
  'subject_offerings': _class,
  'teachers': {'full_name': 'Nathan Orias'},
};
final _enrollment = {
  'id': 'enroll-1',
  'student_id': 'student-1',
  'subject_offering_id': 'class-1',
  'created_at': '2026-10-02T09:00:00Z',
  'students': _student,
  'subject_offerings': _class,
};
final _attempt = {
  'id': 'attempt-1',
  'student_id': 'student-1',
  'exam_session_id': 'exam-1',
  'status': 'completed',
  'exam_score': 85,
  'violation_count': 1,
  'completion_seconds': 1800,
  'started_at': '2026-10-02T09:00:00Z',
  'students': _student,
  'exam_sessions': _exam,
};
final _session = {
  'id': 'session-1',
  'is_active': false,
  'subject_offering_id': 'class-1',
  'started_at': '2026-10-02T09:00:00Z',
  'subject_offerings': _class,
};
final _record = {
  'id': 'record-1',
  'student_id': 'student-1',
  'attendance_session_id': 'session-1',
  'status': 'Present',
  'marked_at': '2026-10-02T09:00:00Z',
  'device_name': 'Android',
  'students': _student,
  'attendance_sessions': _session,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  bool fail = false, duplicateClass = false;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await (FontLoader('Preview')..addFont(
          Future.value(
            ByteData.sublistView(
              File('C:/Windows/Fonts/segoeui.ttf').readAsBytesSync(),
            ),
          ),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await Supabase.initialize(
      url: 'https://admin-test.invalid',
      anonKey: 'test',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (duplicateClass &&
            request.url.path.endsWith('/admin_create_class_section')) {
          return http.Response(
            '{"message":"duplicate class","code":"23505"}',
            409,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (fail) {
          return http.Response(
            '{"message":"Offline","code":"ERROR"}',
            503,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        final path = request.url.path.split('/').last;
        dynamic data = switch (path) {
          'students' => [_student],
          'teachers' => [_teacher],
          'admins' => [
            {
              'id': 'admin-1',
              'full_name': 'School Admin',
              'email': 'admin',
              'created_at': '2026-10-01T09:00:00Z',
            },
          ],
          'subjects' => [
            {
              'id': 'subject-1',
              'subject_code': 'IT401',
              'subject_title': 'Application Development',
              'created_at': '2026-10-01T09:00:00Z',
            },
          ],
          'sections' => [
            {
              'id': 'section-1',
              'section_name': 'BSIT 4A',
              'created_at': '2026-10-01T09:00:00Z',
            },
          ],
          'subject_offerings' => [_class],
          'student_subject_enrollments' => [_enrollment],
          'exam_sessions' => [_exam],
          'exam_attempts' => [_attempt],
          'attendance_sessions' => [_session],
          'attendance_records' => [_record],
          'exam_questions' => [
            {
              'id': 'q1',
              'question_text': 'What is a database index?',
              'points': 1,
              'question_order': 1,
              'exam_session_id': 'exam-1',
              'exam_sessions': _exam,
              'created_at': '2026-10-02T09:00:00Z',
            },
          ],
          'exam_choices' => [
            {
              'id': 'c1',
              'exam_question_id': 'q1',
              'choice_text': 'A structure that speeds up lookup',
              'is_correct': true,
              'choice_order': 1,
            },
          ],
          'exam_alerts' => [
            {
              'id': 'alert-1',
              'student_id': 'student-1',
              'exam_attempt_id': 'attempt-1',
              'exam_session_id': 'exam-1',
              'alert_type': 'out_of_range',
              'message': 'Student moved out of range',
              'created_at': '2026-10-02T09:00:00Z',
              'students': _student,
              'exam_sessions': _exam,
            },
          ],
          'exam_proximity_logs' => [
            {
              'id': 'log-1',
              'is_in_range': false,
              'rssi': -95,
              'created_at': '2026-10-02T09:15:00Z',
            },
          ],
          'admin_dashboard_summary' => {
            'enrollment_sections': [
              {'label': 'BSIT 4A', 'value': 35},
              {'label': 'BSIT 4B', 'value': 40},
              {'label': 'STEM 12A', 'value': 42},
            ],
            'exam_statuses': [
              {'label': 'ended', 'value': 14},
              {'label': 'active', 'value': 2},
              {'label': 'scheduled', 'value': 2},
            ],
            'attendance_daily': [
              for (var i = 0; i < 5; i++)
                {'day': '2026-09-${26 + i}', 'value': 120 + i * 12},
            ],
            'activity': [
              {
                'title': 'Student enrolled',
                'detail': 'Juan Dela Cruz → IT401',
                'event_at': '2026-10-02T09:00:00Z',
                'destination': 'enrollments',
              },
            ],
          },
          'get_admin_enrollments' => [
            {
              'student_id': 'student-1',
              'student_name': 'Juan Dela Cruz',
              'offering_id': 'class-1',
              'teacher_id': 'teacher-1',
              'teacher_name': 'Nathan Orias',
              'subject_code': 'IT401',
              'subject_title': 'Application Development',
              'section': 'BSIT 4A',
            },
          ],
          'admin_create_teacher_account' => 'teacher-2',
          'admin_create_class_section' => 'class-2',
          'admin_create_subject_offering' => null,
          'admin_assign_student_to_offering' => true,
          _ => [],
        };
        if (request.headers['accept']?.contains('vnd.pgrst.object') == true &&
            data is List) {
          data = data.first;
        }
        return http.Response(
          request.method == 'HEAD' ? '' : jsonEncode(data),
          200,
          request: request,
          headers: {
            'content-type': 'application/json',
            'content-range': '0-0/1',
          },
        );
      }),
    );
  });
  setUp(() {
    requests.clear();
    fail = false;
    duplicateClass = false;
  });
  tearDownAll(() async => Supabase.instance.dispose());

  Future<void> mount(
    WidgetTester tester, {
    double width = 1440,
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 1000));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          fontFamily: 'Preview',
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: Size(width, 1000),
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: const RepaintBoundary(
          key: ValueKey('admin-preview'),
          child: AdminWebPanelScreen(
            user: AppUser(
              role: 'admin',
              linkedId: 'admin-1',
              fullName: 'Nathan Orias',
              username: 'admin',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  }

  testWidgets('dashboard shows real summaries and saves desktop preview', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('Good day, Nathan!'), findsOneWidget);
    expect(find.text('Class Enrollments'), findsOneWidget);
    expect(find.text('Recent Exam Sessions'), findsOneWidget);
    expect(find.text('Create Teacher'), findsOneWidget);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('admin-preview')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('artifacts').createSync(recursive: true);
      File(
        'artifacts/admin-dashboard.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await finish(tester);
  });
  for (final label in [
    'Students',
    'Teachers',
    'Admins',
    'Subjects',
    'Class Sections',
    'Enrollments',
    'Exams',
    'Question Bank',
    'Attempt Logs',
    'Attendance Sessions',
    'Attendance Records',
    'Analytics & Reports',
    'Settings',
    'Activity Logs',
  ]) {
    testWidgets('$label navigation loads its page', (tester) async {
      await mount(tester);
      final target = find.descendant(
        of: find.byKey(const ValueKey('admin-navigation')),
        matching: find.text(label),
      );
      await tester.scrollUntilVisible(
        target,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text(label), findsWidgets);
      expect(find.textContaining('Could not load'), findsNothing);
      if (label == 'Settings') {
        expect(find.text('Save preferences'), findsOneWidget);
      }
      await finish(tester);
    });
  }
  testWidgets(
    'enrollments require subject and section before loading students',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('Enrollments').first);
      await tester.pumpAndSettle();
      requests.clear();
      await tester.tap(find.text('IT401').first);
      await tester.pumpAndSettle();
      expect(
        requests.any(
          (r) => r.url.path.endsWith('/student_subject_enrollments'),
        ),
        isFalse,
      );
      expect(
        requests.any(
          (r) => r.url.queryParameters['subject_id'] == 'eq.subject-1',
        ),
        isTrue,
      );
      await tester.tap(find.text('BSIT 4A').first);
      await tester.pumpAndSettle();
      expect(find.text('Juan Dela Cruz'), findsOneWidget);
      expect(
        requests.any(
          (r) => r.url.queryParameters['subject_offering_id'] == 'eq.class-1',
        ),
        isTrue,
      );
      await finish(tester);
    },
  );
  testWidgets('question bank loads questions only after selecting an exam', (
    tester,
  ) async {
    await mount(tester);
    requests.clear();
    await tester.scrollUntilVisible(
      find.text('Question Bank'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Question Bank'));
    await tester.pumpAndSettle();
    expect(find.text('What is a database index?'), findsNothing);
    expect(
      requests.any((r) => r.url.path.endsWith('/exam_questions')),
      isFalse,
    );
    await tester.tap(find.text('Prelim Examination').first);
    await tester.pumpAndSettle();
    expect(find.text('What is a database index?'), findsOneWidget);
    expect(
      requests.any(
        (r) => r.url.queryParameters['exam_session_id'] == 'eq.exam-1',
      ),
      isTrue,
    );
    await finish(tester);
  });
  for (final width in [320.0, 390.0, 768.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('dashboard responsive width=$width scale=$scale', (
        tester,
      ) async {
        await mount(tester, width: width, scale: scale);
        if (width < 1000) {
          await tester.tap(find.byTooltip('Toggle navigation'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Students'));
          await tester.pumpAndSettle();
        }
        await finish(tester);
      });
    }
  }
  testWidgets('create subject saves to the database', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Create Subject'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'CS101');
    await tester.enterText(fields.at(1), 'Computer Science');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final inserts = requests
        .where((r) => r.method == 'POST' && r.url.path.endsWith('/subjects'))
        .toList();
    expect(inserts, hasLength(1));
    expect(jsonDecode(inserts.single.body)['subject_code'], 'CS101');
    await finish(tester);
  });
  testWidgets('attempt details display monitoring history', (tester) async {
    await mount(tester);
    await tester.scrollUntilVisible(
      find.text('Attempt Logs'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Attempt Logs'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('View details'));
    await tester.pumpAndSettle();
    expect(find.text('Bluetooth monitoring history'), findsOneWidget);
    expect(find.text('Out of range'), findsOneWidget);
    await finish(tester);
  });
  test('paged queries are scoped and never fetch account hashes', () async {
    await AdminDataService().page('students', page: 2);
    final r = requests.single;
    expect(r.url.queryParameters['offset'], '50');
    expect(r.url.queryParameters['limit'], '25');
    expect(r.url.queryParameters['select'], isNot(contains('password')));
  });
  testWidgets('failed data load offers retry', (tester) async {
    fail = true;
    await mount(tester);
    expect(find.text('Retry'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load'), findsNothing);
    await finish(tester);
  });
  Future<void> navigate(WidgetTester tester, String label) async {
    final target = find.descendant(
      of: find.byKey(const ValueKey('admin-navigation')),
      matching: find.text(label),
    );
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String label, String choice) async {
    await tester.tap(find.text('Select $label').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(choice).last);
    await tester.pumpAndSettle();
  }

  testWidgets('class creation chooses existing records and generates beacon', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Create Class Section').first);
    await tester.pumpAndSettle();
    expect(find.text('Subject Code (ex: IT401)'), findsNothing);
    await choose(tester, 'Teacher', 'Nathan Orias ·');
    await choose(tester, 'Subject', 'IT401 —');
    await choose(tester, 'Section', 'BSIT 4A');
    await tester.tap(
      find.descendant(
        of: find.byType(AdminClassForm),
        matching: find.widgetWithText(FilledButton, 'Create Class Section'),
      ),
    );
    await tester.pumpAndSettle();
    final request = requests.singleWhere(
      (r) => r.url.path.endsWith('/admin_create_class_section'),
    );
    final body = jsonDecode(request.body) as Map;
    expect(body['p_subject_id'], 'subject-1');
    expect(body['p_teacher_id'], 'teacher-1');
    expect(body['p_section_name'], 'BSIT 4A');
    expect(body['p_beacon_name'], 'IT401 · BSIT 4A');
    expect(body['p_beacon_uuid'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(
      requests.any((r) => r.url.path.endsWith('/get_admin_enrollments')),
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('class form requires choices and supports a new section', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Create Class Section').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AdminClassForm),
        matching: find.widgetWithText(FilledButton, 'Create Class Section'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Select a teacher, subject, and section.'),
      findsOneWidget,
    );
    expect(
      requests.any((r) => r.url.path.endsWith('/admin_create_class_section')),
      isFalse,
    );
    await choose(tester, 'Teacher', 'Nathan Orias ·');
    await choose(tester, 'Subject', 'IT401 —');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'BSIT 4B');
    await tester.tap(
      find.descendant(
        of: find.byType(AdminClassForm),
        matching: find.widgetWithText(FilledButton, 'Create Class Section'),
      ),
    );
    await tester.pumpAndSettle();
    final request = requests.singleWhere(
      (r) => r.url.path.endsWith('/admin_create_class_section'),
    );
    expect(jsonDecode(request.body)['p_section_name'], 'BSIT 4B');
    await finish(tester);
  });

  for (final pageTitle in ['Question Bank', 'Attempt Logs']) {
    testWidgets(
      '$pageTitle filters in the database and resets dependent exam',
      (tester) async {
        await mount(tester);
        await navigate(tester, pageTitle);
        await choose(tester, 'Teacher', 'Nathan Orias ·');
        await choose(tester, 'Subject', 'IT401 —');
        await choose(tester, 'Exam', 'Prelim Examination ·');
        final table = pageTitle == 'Question Bank'
            ? 'exam_questions'
            : 'exam_attempts';
        final query = requests
            .lastWhere((r) => r.url.path.endsWith('/$table'))
            .url
            .queryParameters;
        expect(query['exam_sessions.teacher_id'], 'eq.teacher-1');
        expect(
          query['exam_sessions.subject_offerings.subject_id'],
          'eq.subject-1',
        );
        expect(query['exam_session_id'], 'eq.exam-1');
        expect(query['select'], contains('exam_sessions!inner'));
        expect(query['select'], contains('subject_offerings!inner'));
        await tester.tap(find.text('Clear exam filters'));
        await tester.pumpAndSettle();
        final clear = requests
            .lastWhere((r) => r.url.path.endsWith('/$table'))
            .url
            .queryParameters;
        expect(clear.containsKey('exam_session_id'), isFalse);
        expect(clear.containsKey('exam_sessions.teacher_id'), isFalse);
        await finish(tester);
      },
    );
  }

  testWidgets('enrollment loads paged student and class choices', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Enroll Student').first);
    await tester.pumpAndSettle();
    await choose(tester, 'Student', 'Juan Dela Cruz ·');
    await choose(tester, 'Class', 'IT401 · BSIT 4A ·');
    await tester.tap(find.text('Save Enrollment'));
    await tester.pumpAndSettle();
    final request = requests.singleWhere(
      (r) => r.url.path.endsWith('/admin_assign_student_to_offering'),
    );
    expect(jsonDecode(request.body), {
      'p_student_id': 'student-1',
      'p_offering_id': 'class-1',
    });
    expect(
      requests.any((r) => r.url.path.endsWith('/get_admin_enrollments')),
      isFalse,
    );
    await finish(tester);
  });

  test(
    'dropdown search and exam options are scoped to a bounded page',
    () async {
      await AdminDataService().lookup(
        'exams',
        search: 'Prelim',
        page: 2,
        teacherId: 'teacher-1',
        subjectId: 'subject-1',
      );
      final query = requests.last.url.queryParameters;
      expect(query['teacher_id'], 'eq.teacher-1');
      expect(query['subject_offerings.subject_id'], 'eq.subject-1');
      expect(query['exam_title'], 'ilike.%Prelim%');
      expect(query['offset'], '50');
      expect(query['limit'], '25');
      expect(query['select'], contains('subject_offerings!inner'));
    },
  );
  testWidgets('duplicate class response preserves the form and allows retry', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Create Class Section').first);
    await tester.pumpAndSettle();
    await choose(tester, 'Teacher', 'Nathan Orias ·');
    await choose(tester, 'Subject', 'IT401 —');
    await choose(tester, 'Section', 'BSIT 4A');
    duplicateClass = true;
    await tester.tap(
      find.descendant(
        of: find.byType(AdminClassForm),
        matching: find.widgetWithText(FilledButton, 'Create Class Section'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('This class already exists. Open it from Class Sections.'),
      findsOneWidget,
    );
    expect(find.byType(AdminClassForm), findsOneWidget);
    expect(
      requests
          .where((r) => r.url.path.endsWith('/admin_create_class_section'))
          .length,
      1,
    );
    await finish(tester);
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('class choices fit narrow screen $width with enlarged text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: Size(width, 1000),
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const AdminClassForm(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Select Teacher'));
      await tester.tap(find.text('Select Teacher'));
      await tester.pumpAndSettle();
      expect(find.text('Search teacher'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await finish(tester);
    });
  }
}
