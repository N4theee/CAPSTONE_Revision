import 'dart:async';
import 'package:flutter/material.dart';
import '../services/device_management_service.dart';
import '../services/local_session_service.dart';
import '../screens/home_screen.dart';

/// Rejects a revoked saved login on every route, including when resuming the app.
/// Connectivity failures never masquerade as an administrator reset.
class StudentDeviceSessionGuard extends StatefulWidget {
  const StudentDeviceSessionGuard({
    super.key,
    required this.navigatorKey,
    required this.child,
  });
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  @override
  State<StudentDeviceSessionGuard> createState() =>
      _StudentDeviceSessionGuardState();
}

class _StudentDeviceSessionGuardState extends State<StudentDeviceSessionGuard>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _checking = false;
  final _local = LocalSessionService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _check());
  }

  Future<void> _check() async {
    if (_checking ||
        !mounted ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
      return;
    }
    _checking = true;
    try {
      final revision = _local.revision;
      final saved = await _local.getSavedUserSession();
      if (saved == null) return;
      final valid = await DeviceManagementService().sessionValid(
        saved.user.linkedId,
        saved.deviceUuid,
      );
      if (!mounted || valid || revision != _local.revision) return;
      final nav = widget.navigatorKey.currentState;
      if (nav == null) return;
      await _local.clearUserSession();
      if (!mounted) return;
      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
      // Show the reason after the new route is mounted.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = widget.navigatorKey.currentContext;
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your device login is no longer valid. Please sign in on your approved phone or contact the administrator.',
              ),
            ),
          );
        }
      });
    } catch (_) {
      // Offline or missing migration: retry later; never discard a valid login.
    } finally {
      _checking = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
