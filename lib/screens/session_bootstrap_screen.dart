import 'package:flutter/material.dart';

import '../services/device_identity_service.dart';
import '../services/device_management_service.dart';
import '../services/local_session_service.dart';
import '../services/supabase_service.dart';
import 'home_screen.dart';
import 'student_dashboard_screen.dart';
import 'student_screen.dart';

/// Cold start: restore student session and optionally open active attendance.
class SessionBootstrapScreen extends StatefulWidget {
  const SessionBootstrapScreen({super.key});

  @override
  State<SessionBootstrapScreen> createState() => _SessionBootstrapScreenState();
}

class _SessionBootstrapScreenState extends State<SessionBootstrapScreen> {
  final _db = SupabaseService();
  final _local = LocalSessionService();
  final _identity = DeviceIdentityService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;

    final saved = await _local.getSavedUserSession();
    if (saved == null) {
      _goHome();
      return;
    }

    try {
      // An explicit revoked result must never restore the old phone's session.
      final valid = await DeviceManagementService().sessionValid(
        saved.user.linkedId,
        saved.deviceUuid,
      );
      if (!valid) {
        await _local.clearUserSession();
        if (mounted) _goHome();
        return;
      }
    } catch (_) {
      // Keep existing offline/bootstrap behavior until the server is reachable.
      // The app-wide guard checks again in the foreground.
    }

    try {
      await _identity.getDeviceIdentity();
      final status = await _db.getStudentActiveSessionStatus(
        saved.user.linkedId,
      );

      if (!mounted) return;

      if (status.hasActiveSession &&
          status.offeringId != null &&
          status.offeringId!.isNotEmpty) {
        final offerings = await _db.getStudentOfferings(saved.user.linkedId);
        if (!mounted) return;
        SubjectOffering? match;
        for (final o in offerings) {
          if (o.id == status.offeringId) {
            match = o;
            break;
          }
        }

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => StudentDashboardScreen(user: saved.user),
          ),
        );

        if (match != null && mounted) {
          final offering = match;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => StudentScreen(
                studentId: saved.user.linkedId,
                studentName: saved.user.fullName,
                offering: offering,
              ),
            ),
          );
        }
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => StudentDashboardScreen(user: saved.user),
        ),
      );
    } catch (e, st) {
      debugPrint('[SessionBootstrap] $e\n$st');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => StudentDashboardScreen(user: saved.user),
        ),
      );
    }
  }

  void _goHome() {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
