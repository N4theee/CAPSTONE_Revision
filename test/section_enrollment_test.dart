import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:ble_attendance/screens/student_dashboard_screen.dart';
import 'package:ble_attendance/screens/teacher_dashboard_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ble_attendance/services/device_identity_service.dart';
import 'package:ble_attendance/services/section_enrollment_service.dart';
import 'package:ble_attendance/services/supabase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  bool assigned = false;
  bool missingRegistration = false,
      deviceDenied = false,
      missingMetadata = false;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://section-test.invalid',
      anonKey: 'test',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((r) async {
        requests.add(r);
        final name = r.url.path.split('/').last;
        if (name == 'register_student_with_section_request' &&
            missingRegistration) {
          return http.Response(
            '{"code":"PGRST202","message":"Missing registration wrapper"}',
            404,
            request: r,
            headers: {'content-type': 'application/json'},
          );
        }
        if (name == 'app_student_login_with_device' && deviceDenied) {
          return http.Response(
            '{"code":"P0001","message":"Cannot sign in. This device is already registered to another student."}',
            400,
            request: r,
            headers: {'content-type': 'application/json'},
          );
        }
        if (missingMetadata && name.startsWith('school_')) {
          return http.Response(
            '{"code":"PGRST205","message":"Missing table"}',
            404,
            request: r,
            headers: {'content-type': 'application/json'},
          );
        }
        final dynamic data = switch (name) {
          'register_student_with_section_request' => 'student-1',
          'app_student_login_with_device' => [
            {
              'role': 'student',
              'linked_id': 'student-1',
              'full_name': 'Student',
              'username': 'student',
            },
          ],
          'school_student_requests' => [
            {'requested_grade': 11, 'requested_program': 'ICT'},
          ],
          'school_section_placements' =>
            assigned
                ? [
                    {
                      'school_year': '2026-2027',
                      'school_sections': {
                        'grade': 11,
                        'program': 'ICT',
                        'sections': {'section_name': 'ICT 11-A'},
                      },
                    },
                  ]
                : [],
          'subject_offerings' => [
            for (final n in [1, 2])
              {
                'id': 'offering-$n',
                'subject_id': 'subject-$n',
                'section_id': 'section-$n',
                'teacher_id': 'teacher-1',
                'beacon_uuid': 'beacon-$n',
                'beacon_name': 'Class $n',
                'subjects': {
                  'subject_code': 'SUB$n',
                  'subject_title': n == 1 ? 'Mathematics' : 'Science',
                },
                'sections': {'section_name': n == 1 ? 'A' : 'B'},
                'teachers': {'full_name': 'Teacher'},
              },
          ],
          'admin_school_command' => {'enrolled': 2},
          _ => [],
        };
        return http.Response(
          jsonEncode(data),
          200,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  setUp(() {
    requests.clear();
    missingRegistration = deviceDenied = missingMetadata = assigned = false;
  });
  tearDownAll(() async => Supabase.instance.dispose());

  test(
    'registration request preserves device registration arguments',
    () async {
      final id = await SupabaseService().registerStudent(
        studentId: '2026-001',
        fullName: 'Student',
        username: 'student',
        password: 'password',
        deviceUuid: 'device-1',
        deviceName: 'Phone',
        requestedGrade: 11,
        requestedProgram: 'ICT',
      );
      expect(id, 'student-1');
      expect(
        requests.single.url.path,
        endsWith('/register_student_with_section_request'),
      );
      expect(jsonDecode(requests.single.body), {
        'p_student_id': '2026-001',
        'p_full_name': 'Student',
        'p_username': 'student',
        'p_password': 'password',
        'p_device_uuid': 'device-1',
        'p_device_name': 'Phone',
        'p_requested_grade': 11,
        'p_requested_program': 'ICT',
      });
    },
  );
  test(
    'missing wrapper fails without losing preferences through a legacy fallback',
    () async {
      missingRegistration = true;
      await expectLater(
        SupabaseService().registerStudent(
          studentId: '1',
          fullName: 'Student',
          username: 'student',
          password: 'password',
          requestedGrade: 11,
          requestedProgram: 'ICT',
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect(requests, hasLength(1));
      expect(
        requests.any((r) => r.url.path.endsWith('/register_student')),
        isFalse,
      );
    },
  );
  const identity = DeviceIdentity(
    deviceUuid: 'device-1',
    deviceName: 'Phone',
    deviceFingerprint: 'fingerprint-1',
  );
  test(
    'device-bound login still forwards fingerprint and uses the same secure RPC',
    () async {
      final user = await SupabaseService().loginStudentWithDevice(
        username: 'student',
        password: 'password',
        identity: identity,
      );
      expect(user?.linkedId, 'student-1');
      expect(
        requests.single.url.path,
        endsWith('/app_student_login_with_device'),
      );
      expect(jsonDecode(requests.single.body), {
        'p_username': 'student',
        'p_password': 'password',
        'p_device_uuid': 'device-1',
        'p_device_name': 'Phone',
        'p_device_fingerprint': 'fingerprint-1',
      });
    },
  );
  test('one-student-per-device rejection still blocks login', () async {
    deviceDenied = true;
    await expectLater(
      SupabaseService().loginStudentWithDevice(
        username: 'student',
        password: 'password',
        identity: identity,
      ),
      throwsA(
        isA<PostgrestException>().having(
          (e) => e.message,
          'message',
          contains('already registered to another student'),
        ),
      ),
    );
    expect(requests, hasLength(1));
  });
  test('student profile uses scoped requests and pending placement', () async {
    final profile = await SectionEnrollmentService().studentPlacement(
      'student-1',
    );
    expect(profile['placement'], isNull);
    expect(profile['request'], {
      'requested_grade': 11,
      'requested_program': 'ICT',
    });
    expect(requests, hasLength(2));
    for (final r in requests) {
      expect(r.url.queryParameters['student_id'], 'eq.student-1');
    }
  });
  test(
    'missing new metadata does not disable existing student features',
    () async {
      missingMetadata = true;
      expect(await SectionEnrollmentService().studentPlacement('student-1'), {
        'available': false,
      });
    },
  );
  test('section choices filter before bounded pagination', () async {
    await SectionEnrollmentService().sections(
      page: 2,
      year: '2026-2027',
      grade: 11,
      program: 'ICT',
    );
    final q = requests.single.url.queryParameters;
    expect(q['school_year'], 'eq.2026-2027');
    expect(q['grade'], 'eq.11');
    expect(q['program'], 'eq.ICT');
    expect(q['offset'], '50');
    expect(q['limit'], '25');
  });
  test('bulk placement is one credential-verified operation', () async {
    await SectionEnrollmentService().command(
      'enroll',
      {
        'term_id': 'term-1',
        'student_ids': ['student-1', 'student-2'],
      },
      username: 'admin',
      password: 'admin-password',
    );
    expect(requests, hasLength(1));
    expect(jsonDecode(requests.single.body)['p_data'], {
      'term_id': 'term-1',
      'student_ids': ['student-1', 'student-2'],
    });
    expect(requests.single.url.path, endsWith('/admin_school_command'));
  });
  const student = AppUser(
    role: 'student',
    linkedId: 'student-1',
    fullName: 'Student',
    username: 'student',
  );
  for (final hasPlacement in [false, true]) {
    testWidgets(
      'student dashboard shows ${hasPlacement ? 'approved placement' : 'pending request'}',
      (tester) async {
        assigned = hasPlacement;
        await tester.binding.setSurfaceSize(const Size(390, 844));
        await tester.pumpWidget(
          const MaterialApp(home: StudentDashboardScreen(user: student)),
        );
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(
          find.text(hasPlacement ? 'ICT 11-A' : 'Awaiting section assignment'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            hasPlacement
                ? 'Grade 11 · ICT · 2026-2027'
                : 'Requested Grade 11 · ICT',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.binding.setSurfaceSize(null);
      },
    );
  }
  testWidgets('teacher section filter displays only its assigned subjects', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(
      const MaterialApp(
        home: TeacherDashboardScreen(
          user: AppUser(
            role: 'teacher',
            linkedId: 'teacher-1',
            fullName: 'Teacher',
            username: 'teacher',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Mathematics'), findsOneWidget);
    expect(find.textContaining('Science'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Mathematics'), findsOneWidget);
    expect(find.textContaining('Science'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
}
