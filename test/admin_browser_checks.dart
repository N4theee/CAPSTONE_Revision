import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ble_attendance/screens/admin_web_panel_screen.dart';
import 'package:ble_attendance/screens/home_screen.dart';
import 'ui_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://ui-test.invalid',
      anonKey: 'test-only',
      httpClient: MockClient((request) async => fakeResponse(request)),
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());
  for (final width in [320.0, 390.0, 768.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('admin width=$width text=$scale', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 844));
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const AdminWebPanelScreen(),
          ),
        );
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(tester.takeException(), isNull);
        final state = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        final max = state.position.maxScrollExtent;
        for (double offset = 0; offset <= max; offset += 250) {
          state.position.jumpTo(offset);
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.binding.setSurfaceSize(null);
      });
    }
  }
  testWidgets('admin login remains reachable with keyboard', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 650));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: const HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Admin Panel (Web)'));
    await tester.tap(find.text('Admin Panel (Web)'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Login'));
    expect(find.text('Login').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    tester.view.resetViewInsets();
    await tester.binding.setSurfaceSize(null);
  });
}
