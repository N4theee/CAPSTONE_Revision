import 'dart:async';
import 'dart:convert';

import 'package:ble_attendance/services/exam_beacon_service.dart';
import 'package:ble_attendance/services/supabase_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ui_fixtures.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  var attendanceRows = <Map<String, dynamic>>[];
  var examStatus = 'scheduled';
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://scaling-test.invalid',
      anonKey: 'test',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        final rows = request.url.path.endsWith('exam_sessions')
            ? [
                {...fixtures.examRow, 'status': examStatus},
              ]
            : attendanceRows;
        return http.Response(
          jsonEncode(rows),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());
  setUp(() {
    requests.clear();
    attendanceRows = [];
    examStatus = 'scheduled';
  });

  test('one scoped request preserves a session with no attendance', () async {
    attendanceRows = [
      {'id': 'session-1', 'attendance_records': []},
    ];
    final row = await SupabaseService().getStudentOfferingSession(
      offeringId: 'class-1',
      studentId: 'student-1',
    );
    expect(row!['already_marked'], false);
    expect(requests, hasLength(1));
    final params = requests.single.url.queryParameters;
    expect(params['subject_offering_id'], 'eq.class-1');
    expect(params['attendance_records.student_id'], 'eq.student-1');
    expect(params['select'], contains('attendance_records('));
    expect(params['select'], isNot(contains('!inner')));
  });

  test(
    'confirmed attendance stays confirmed without re-fetching its record',
    () async {
      attendanceRows = [
        {'id': 'session-1', 'attendance_records': []},
      ];
      final row = await SupabaseService().getStudentOfferingSession(
        offeringId: 'class-1',
        studentId: 'student-1',
        confirmedSessionId: 'session-1',
      );
      expect(row!['already_marked'], true);
      expect(
        requests
            .single
            .url
            .queryParameters['attendance_records.attendance_session_id'],
        'neq.session-1',
      );
    },
  );

  test('a new session does not inherit prior confirmed attendance', () async {
    attendanceRows = [
      {'id': 'session-2', 'attendance_records': []},
    ];
    final row = await SupabaseService().getStudentOfferingSession(
      offeringId: 'class-1',
      studentId: 'student-1',
      confirmedSessionId: 'session-1',
    );
    expect(row!['already_marked'], false);
  });

  test('existing attendance is returned by the same request', () async {
    attendanceRows = [
      {
        'id': 'session-1',
        'attendance_records': [
          {'id': 'record-1'},
        ],
      },
    ];
    final row = await SupabaseService().getStudentOfferingSession(
      offeringId: 'class-1',
      studentId: 'student-1',
    );
    expect(row!['already_marked'], true);
    expect(requests, hasLength(1));
  });

  test('student code validation cannot activate a scheduled exam', () async {
    await expectLater(
      ExamService().validateExamCode(
        examCode: 'EXAM123',
        subjectOfferingId: 'class-1',
      ),
      throwsA(isA<ExamServiceException>()),
    );
    expect(requests, hasLength(1));
    expect(requests.single.method, 'GET');
  });

  testWidgets('beacon survives navigation and recovers when app resumes', (
    tester,
  ) async {
    var starts = 0;
    var stops = 0;
    final service = ExamBeaconService.forTesting(
      prepare: (_, _) async {
        starts++;
      },
      stopAdvertising: () async {
        stops++;
      },
      loadSession: (_) async => fixtures.session,
    );
    try {
      await service.ensure(fixtures.session, fixtures.offering);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Text('Another professor screen'),
        ),
      );
      expect(stops, 0);
      expect(service.isReadyFor(fixtures.session.id), true);
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(service.ready.value, false);
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(starts, 2);
      expect(service.ready.value, true);
    } finally {
      await service.stop();
    }
    expect(stops, 1);
  });

  testWidgets('failed startup is visible and can be retried', (tester) async {
    var fail = true;
    final service = ExamBeaconService.forTesting(
      prepare: (_, _) async {
        if (fail) throw Exception('Bluetooth off');
      },
      stopAdvertising: () async {},
      loadSession: (_) async => fixtures.session,
    );
    try {
      await expectLater(
        service.ensure(fixtures.session, fixtures.offering),
        throwsException,
      );
      expect(service.ready.value, false);
      expect(service.error.value, contains('Bluetooth off'));
      fail = false;
      await service.ensure(fixtures.session, fixtures.offering);
      expect(service.ready.value, true);
      expect(service.error.value, isNull);
    } finally {
      await service.stop();
    }
  });

  testWidgets('externally removed session stops advertising on recovery', (
    tester,
  ) async {
    var stops = 0;
    final service = ExamBeaconService.forTesting(
      prepare: (_, _) async {},
      stopAdvertising: () async {
        stops++;
      },
      loadSession: (_) async => null,
    );
    await service.ensure(fixtures.session, fixtures.offering);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(stops, 1);
    expect(service.ready.value, false);
  });

  testWidgets('stop waits for in-flight startup and leaves beacon off', (
    tester,
  ) async {
    final gate = Completer<void>();
    var stops = 0;
    final service = ExamBeaconService.forTesting(
      prepare: (_, _) => gate.future,
      stopAdvertising: () async {
        stops++;
      },
      loadSession: (_) async => fixtures.session,
    );
    final start = service.ensure(fixtures.session, fixtures.offering);
    final stop = service.stop();
    gate.complete();
    await Future.wait([start, stop]);
    expect(service.ready.value, false);
    expect(stops, 1);
  });
}
