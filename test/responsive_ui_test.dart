import 'ui_fixtures.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ble_attendance/services/supabase_service.dart';
import 'package:ble_attendance/screens/auth_screen.dart';
import 'package:ble_attendance/screens/create_exam_session_screen.dart';
import 'package:ble_attendance/screens/exam_history_screen.dart';
import 'package:ble_attendance/screens/exam_rankings_screen.dart';
import 'package:ble_attendance/screens/home_screen.dart';
import 'package:ble_attendance/screens/join_exam_screen.dart';
import 'package:ble_attendance/screens/student_attendance_detail_screen.dart';
import 'package:ble_attendance/screens/student_dashboard_screen.dart';
import 'package:ble_attendance/screens/student_history_screen.dart';
import 'package:ble_attendance/screens/student_subject_details_screen.dart';
import 'package:ble_attendance/screens/take_exam_screen.dart';
import 'package:ble_attendance/screens/teacher_dashboard_screen.dart';
import 'package:ble_attendance/screens/teacher_screen.dart';
import 'package:ble_attendance/screens/teacher_exam_active_screen.dart';
import 'package:ble_attendance/screens/teacher_exam_sessions_screen.dart';
import 'package:ble_attendance/screens/teacher_history_screen.dart';
import 'package:ble_attendance/screens/teacher_session_detail_screen.dart';
import 'package:ble_attendance/screens/teacher_subject_details_screen.dart';
import 'package:ble_attendance/ui/adaptive_layout.dart';

Future<void> mount(
  WidgetTester tester,
  Widget page,
  Size size,
  double scale, {
  double keyboard = 0,
}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'Preview',
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: RepaintBoundary(key: const ValueKey('preview'), child: page),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> checkScroll(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  final scrolls = find.byType(Scrollable).evaluate().toList();
  for (final element in scrolls) {
    if (!element.mounted) continue;
    final state = (element as StatefulElement).state as ScrollableState;
    if (!state.position.hasContentDimensions ||
        state.position.maxScrollExtent <= 0) {
      continue;
    }
    final max = state.position.maxScrollExtent;
    for (final fraction in [0.5, 1.0, 0.0]) {
      if (!state.mounted) break;
      state.position.jumpTo(max * fraction);
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await (FontLoader('ProxamityScript')
          ..addFont(rootBundle.load('assets/fonts/NotoSansMath-Regular.ttf')))
        .load();
    final font = File('C:/Windows/Fonts/segoeui.ttf');
    if (font.existsSync()) {
      await (FontLoader('Preview')..addFont(
            Future.value(ByteData.sublistView(font.readAsBytesSync())),
          ))
          .load();
    }
    await Supabase.initialize(
      url: 'https://ui-test.invalid',
      anonKey: 'test-only',
      httpClient: MockClient((request) async => fakeResponse(request)),
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      debug: false,
    );
  });
  tearDown(() {
    failHistory = false;
  });
  tearDownAll(() async {
    await Supabase.instance.dispose();
  });

  final screens = <String, Widget Function()>{
    'teacher attendance controls': () =>
        const TeacherScreen(teacherName: longName, offering: offering),
    'teacher exam controls': () =>
        TeacherExamActiveScreen(offering: offering, session: session),
    'home': () => const HomeScreen(),
    'registration': () => const AuthScreen(initialRole: 'student'),
    'student courses': () => const StudentDashboardScreen(user: student),
    'teacher courses': () => const TeacherDashboardScreen(user: teacher),
    'student subject': () => const StudentSubjectDetailsScreen(
      studentId: 'student-1',
      studentName: longName,
      offering: offering,
    ),
    'teacher subject': () => const TeacherSubjectDetailsScreen(
      teacherName: longName,
      offering: offering,
    ),
    'exam history': () =>
        const ExamHistoryScreen(studentId: 'student-1', offering: offering),
    'rankings': () => ExamRankingsScreen(offering: offering, session: session),
    'create exam': () => const CreateExamSessionScreen(offering: offering),
    'take exam': () =>
        TakeExamScreen(session: session, attempt: attempt, offering: offering),
    'join exam': () => const JoinExamScreen(
      studentId: 'student-1',
      studentName: longName,
      offering: offering,
    ),
    'exam sessions': () => const TeacherExamSessionsScreen(
      teacherName: longName,
      offering: offering,
    ),
    'student attendance history': () =>
        const StudentHistoryScreen(studentId: 'student-1'),
    'teacher attendance history': () =>
        const TeacherHistoryScreen(teacherId: 'teacher-1'),
    'attendance detail': () => StudentAttendanceDetailScreen(
      item: StudentAttendanceHistoryItem(
        subjectCode: offering.subjectCode,
        subjectTitle: longTitle,
        section: offering.section,
        teacherName: longName,
        sessionStartedAt: now,
        markedAt: now,
      ),
    ),
    'teacher session detail': () =>
        TeacherSessionDetailScreen(teacherId: 'teacher-1', session: attendance),
  };
  for (final entry in screens.entries) {
    for (final width in [320.0, 360.0, 390.0, 600.0, 768.0, 1024.0, 1440.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets('${entry.key} width=$width text=$scale', (tester) async {
          await mount(tester, entry.value(), Size(width, 800), scale);
          await checkScroll(tester);
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          tester.view.resetViewInsets();
          await tester.binding.setSurfaceSize(null);
        });
      }
    }
    testWidgets('${entry.key} short landscape', (tester) async {
      await mount(tester, entry.value(), const Size(568, 320), 2);
      await checkScroll(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      tester.view.resetViewInsets();
      await tester.binding.setSurfaceSize(null);
    });
  }
  for (final name in ['registration', 'create exam']) {
    testWidgets('$name keyboard does not hide focused fields', (tester) async {
      await mount(
        tester,
        screens[name]!(),
        const Size(320, 640),
        2,
        keyboard: 280,
      );
      await checkScroll(tester);
      final field = find.byType(TextField).first;
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      tester.view.resetViewInsets();
      await tester.binding.setSurfaceSize(null);
    });
  }
  testWidgets('history failure offers retry rather than an empty history', (
    tester,
  ) async {
    failHistory = true;
    await mount(tester, screens['exam history']!(), const Size(390, 800), 1);
    expect(find.byType(LoadError), findsOneWidget);
    expect(find.text('No exam attempts yet'), findsNothing);
    failHistory = false;
    await tester.tap(find.text('Retry'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(LoadError), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    tester.view.resetViewInsets();
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('save representative UI previews', (tester) async {
    final directory = Directory('build/ui_previews')
      ..createSync(recursive: true);
    for (final name in [
      'home',
      'student courses',
      'teacher courses',
      'student subject',
      'teacher subject',
      'exam history',
      'take exam',
    ]) {
      await mount(
        tester,
        screens[name]!(),
        Size(name == 'teacher subject' ? 1440 : 390, 844),
        1,
      );
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('preview')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '${directory.path}/${name.replaceAll(' ', '-')}.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
    tester.view.resetViewInsets();
    await tester.binding.setSurfaceSize(null);
  });
}
