import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ble_attendance/screens/admin_device_management.dart';
import 'package:ble_attendance/services/device_management_service.dart';
import 'package:ble_attendance/services/device_identity_service.dart';
import 'package:ble_attendance/services/local_session_service.dart';
import 'package:ble_attendance/services/supabase_service.dart';
import 'package:ble_attendance/widgets/student_device_session_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  bool bound = true, valid = true, offline = false, missing = false;
  final entry = {
    'id': 'reset-1',
    'student_id': 'student-1',
    'student_name': 'Maria Santos',
    'student_number': '2026-001',
    'admin_name': 'School Admin',
    'admin_username': 'admin',
    'action': 'reset_student_device',
    'reason': 'Broken phone',
    'details': 'Approval letter 42',
    'created_at': '2026-11-02T16:05:00Z',
    'devices': [
      {'device_name': 'Old Android phone', 'device_uuid': 'phone-1'},
    ],
  };

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://device-test.invalid',
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
        int status = 200;
        dynamic data;
        if (name == 'admin_device_management') {
          final body = jsonDecode(r.body) as Map;
          if (missing) {
            status = 404;
            data = {'code': 'PGRST202', 'message': 'Missing function'};
          } else if (body['p_password'] != 'admin-test-password') {
            status = 403;
            data = {
              'code': '42501',
              'message': 'Administrator credentials are required.',
            };
          } else if (body['p_action'] == 'history') {
            data = {
              'rows': [entry],
            };
          } else {
            bound = false;
            valid = false;
            data = {
              'entry': {
                ...entry,
                'action': body['p_action'],
                'reason': body['p_reason'],
                'details': body['p_details'],
              },
            };
          }
        } else if (name == 'student_device_session_valid') {
          if (offline) {
            status = 503;
            data = {'message': 'Network unavailable', 'code': 'ERROR'};
          } else {
            data = valid;
          }
        } else if (name == 'students') {
          data = [
            {
              'id': 'student-1',
              'full_name': 'Maria Santos',
              'email': 'maria',
              'student_number': '2026-001',
            },
          ];
        } else if (name == 'student_devices') {
          data = bound
              ? [
                  {
                    'id': 'device-1',
                    'device_uuid': 'phone-1',
                    'device_name': 'Old Android phone',
                    'registered_at': '2026-10-01T00:00:00Z',
                    'last_seen_at': '2026-11-02T00:00:00Z',
                  },
                ]
              : [];
        } else {
          data = [];
        }
        return http.Response(
          jsonEncode(data),
          status,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalSessionService().clearUserSession();
    requests.clear();
    bound = valid = true;
    offline = missing = false;
  });
  tearDownAll(() async => Supabase.instance.dispose());

  Future<void> mount(
    WidgetTester tester, {
    double width = 1000,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: AdminDeviceManagement(adminUsername: 'admin'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select Student'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Maria Santos ·').last);
    await tester.pumpAndSettle();
  }

  Future<void> reason(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> password(WidgetTester tester, String value) => tester.enterText(
    find.widgetWithText(TextFormField, 'Admin password'),
    value,
  );
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  List<http.Request> commands() => requests
      .where((r) => r.url.path.endsWith('/admin_device_management'))
      .toList();

  testWidgets(
    'reset requires a reason/password, reports wrong password and records success',
    (tester) async {
      await mount(tester);
      expect(find.text('Old Android phone'), findsOneWidget);
      await tester.tap(find.text('Reset a student’s device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm reset'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a reason.'), findsOneWidget);
      expect(commands(), isEmpty);
      await reason(tester, 'Other');
      await password(tester, 'admin-test-password');
      await tester.tap(find.text('Confirm reset'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Explain the other reason'), findsOneWidget);
      expect(commands(), isEmpty);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Explanation / approval reference'),
        'Approval letter 42',
      );
      await password(tester, 'wrong');
      await tester.tap(find.text('Confirm reset'));
      await tester.pumpAndSettle();
      expect(
        find.text('Administrator credentials are required.'),
        findsOneWidget,
      );
      await password(tester, 'admin-test-password');
      await tester.tap(find.text('Confirm reset'));
      await tester.pumpAndSettle();
      final body = jsonDecode(commands().last.body) as Map;
      expect(body['p_action'], 'reset_student_device');
      expect(body['p_student_id'], 'student-1');
      expect(body['p_reason'], 'Other');
      expect(body['p_details'], 'Approval letter 42');
      expect(find.textContaining('By School Admin (admin)'), findsOneWidget);
      expect(find.text('Reason: Other'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
      await finish(tester);
    },
  );

  testWidgets(
    'release targets the selected phone and cancellation makes no request',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('Release a device for another account'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Device ID: phone-1'), findsWidgets);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(commands(), isEmpty);
      await tester.tap(find.text('Release a device for another account'));
      await tester.pumpAndSettle();
      await reason(tester, 'Device reassignment');
      await password(tester, 'admin-test-password');
      await tester.tap(find.text('Confirm reset'));
      await tester.pumpAndSettle();
      final body = jsonDecode(commands().single.body) as Map;
      expect(body['p_action'], 'release_device');
      expect(body['p_device_uuid'], 'phone-1');
      expect(find.text('Released device for another account'), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets('history is credential verified and missing setup is explicit', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('View reset history'));
    await tester.pumpAndSettle();
    expect(commands(), isEmpty);
    await password(tester, 'admin-test-password');
    await tester.tap(find.text('View history'));
    await tester.pumpAndSettle();
    expect(jsonDecode(commands().last.body)['p_action'], 'history');
    expect(find.text('Reason: Broken phone'), findsOneWidget);
    missing = true;
    await tester.tap(find.text('Reset a student’s device'));
    await tester.pumpAndSettle();
    await reason(tester, 'Lost phone');
    await password(tester, 'admin-test-password');
    await tester.tap(find.text('Confirm reset'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Device Management setup is missing'),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('device management and authorization fit narrow enlarged text', (
    tester,
  ) async {
    await mount(tester, width: 320, scale: 2);
    await tester.ensureVisible(find.text('Reset a student’s device'));
    await tester.tap(find.text('Reset a student’s device'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  Future<void> saveSession() => LocalSessionService().saveUserSession(
    AppUser(
      role: 'student',
      linkedId: 'student-1',
      fullName: 'Maria Santos',
      username: 'maria',
    ),
    const DeviceIdentity(
      deviceUuid: 'phone-1',
      deviceName: 'Old Android phone',
      deviceFingerprint: 'fp',
    ),
  );
  Future<void> mountGuard(WidgetTester tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        builder: (_, child) =>
            StudentDeviceSessionGuard(navigatorKey: key, child: child!),
        home: const Scaffold(body: Text('Protected student route')),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'revocation removes saved login and clears protected navigation',
    (tester) async {
      await saveSession();
      await mountGuard(tester);
      expect(find.text('Protected student route'), findsOneWidget);
      valid = false;
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(await LocalSessionService().getSavedUserSession(), isNull);
      expect(find.text('Protected student route'), findsNothing);
      await finish(tester);
    },
  );

  testWidgets('offline session check preserves the saved login', (
    tester,
  ) async {
    await saveSession();
    offline = true;
    await mountGuard(tester);
    expect(await LocalSessionService().getSavedUserSession(), isNotNull);
    expect(find.text('Protected student route'), findsOneWidget);
    await finish(tester);
  });

  test('session validity check sends the saved student and device', () async {
    expect(
      await DeviceManagementService().sessionValid('student-1', 'phone-1'),
      isTrue,
    );
    final body = jsonDecode(requests.single.body) as Map;
    expect(body, {'p_student_id': 'student-1', 'p_device_uuid': 'phone-1'});
  });
}
