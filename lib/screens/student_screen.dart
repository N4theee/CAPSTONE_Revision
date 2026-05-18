import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../services/ble_service.dart';
import '../services/device_identity_service.dart';
import '../services/supabase_service.dart';
import '../ui/responsive.dart';
import '../ui/student_attendance_ui.dart';
import '../util/db_timestamptz.dart';

class StudentScreen extends StatefulWidget {
  const StudentScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.offering,
  });

  final String studentId;
  final String studentName;
  final SubjectOffering offering;

  @override
  State<StudentScreen> createState() => _StudentScreenState();
}

class _StudentScreenState extends State<StudentScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final _ble = BleService();
  final _db = SupabaseService();
  final _identity = DeviceIdentityService();
  StreamSubscription<bool>? _proximitySub;

  bool _inRange = false;
  bool _attended = false;
  bool _sessionActive = false;
  bool _loading = false;
  bool _bleGranted = false;

  String? _sessionId;
  String? _subject;
  String? _beaconUuid;
  String? _beaconAdvertisedName;
  DateTime? _sessionStartedAt;
  int _sessionRssiThreshold = AppConfig.rssiThreshold;

  Map<String, int> _nearbyDevices = {};
  bool _scanningNearby = false;

  Timer? _sessionPollTimer;
  Timer? _uiClockTimer;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _sessionActive &&
        _beaconUuid != null) {
      _ble.startProximityScanning(
        _beaconUuid!,
        beaconName: _beaconAdvertisedName ?? AppConfig.defaultBeaconName,
        rssiThreshold: _sessionRssiThreshold,
      );
    }
    if (state == AppLifecycleState.paused) {
      _ble.stopProximityScanning();
    }
  }

  Future<void> _init() async {
    final granted = await _ble.requestPermissions();
    setState(() => _bleGranted = granted);

    if (!granted) {
      _toast('Please grant all permissions');
      return;
    }

    _proximitySub = _ble.proximityStream.listen((inRange) {
      if (mounted) setState(() => _inRange = inRange);
    });

    _sessionPollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _checkSession(),
    );

    await _checkSession();
  }

  void _syncUiClock() {
    _uiClockTimer?.cancel();
    if (_sessionActive && _sessionStartedAt != null) {
      _uiClockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _checkSession() async {
    try {
      final sessionForTeacher =
          await _db.getActiveSessionForOffering(widget.offering.id);

      if (sessionForTeacher != null) {
        final newId = sessionForTeacher['id'] as String;
        final dynamic beaconRaw = sessionForTeacher['beacon_uuid'] ??
            sessionForTeacher['beacon_name'];
        if (beaconRaw == null) {
          throw Exception('Session is missing beacon identifier');
        }
        final dynamic beaconNameRaw = sessionForTeacher['beacon_name'];
        final newBeaconUuid = beaconRaw.toString();
        final newBeaconName = beaconNameRaw?.toString();
        final rssiRaw = sessionForTeacher['rssi_threshold'];
        final int parsedRssi;
        if (rssiRaw is int) {
          parsedRssi = rssiRaw;
        } else {
          parsedRssi =
              int.tryParse(rssiRaw?.toString() ?? '') ?? AppConfig.rssiThreshold;
        }
        final startedStr = sessionForTeacher['started_at'] as String?;
        final started = startedStr != null
            ? parseDbTimestamptzToLocal(startedStr)
            : null;

        if (_sessionId != newId) {
          setState(() {
            _sessionId = newId;
            _subject = sessionForTeacher['subject'] as String?;
            _beaconUuid = newBeaconUuid;
            _beaconAdvertisedName = newBeaconName;
            _sessionRssiThreshold = parsedRssi;
            _sessionActive = true;
            _attended = false;
            _sessionStartedAt = started;
          });
          _syncUiClock();

          await _ble.startProximityScanning(
            newBeaconUuid,
            beaconName: newBeaconName ?? AppConfig.defaultBeaconName,
            rssiThreshold: parsedRssi,
          );
        } else if (mounted && _sessionStartedAt == null && started != null) {
          setState(() => _sessionStartedAt = started);
          _syncUiClock();
        }

        final alreadyMarked = await _db.hasStudentMarkedAttendance(
          sessionId: newId,
          studentId: widget.studentId,
        );
        if (mounted && _attended != alreadyMarked) {
          setState(() => _attended = alreadyMarked);
        }
      } else {
        if (_sessionActive) {
          _ble.stopProximityScanning();
          _uiClockTimer?.cancel();
          _uiClockTimer = null;
          setState(() {
            _sessionActive = false;
            _inRange = false;
            _sessionId = null;
            _beaconUuid = null;
            _beaconAdvertisedName = null;
            _sessionStartedAt = null;
          });
        }
      }
    } catch (e) {
      debugPrint('Session error: $e');
    }
  }

  Future<void> _scanNearby() async {
    setState(() {
      _scanningNearby = true;
      _nearbyDevices = {};
    });

    final found = await _ble.scanAllDevices(seconds: 8);

    if (mounted) {
      setState(() {
        _nearbyDevices = found;
        _scanningNearby = false;
      });
    }
  }

  Future<void> _markAttendance() async {
    if (!_inRange || !_sessionActive || _attended || _sessionId == null) return;

    setState(() => _loading = true);

    try {
      final identity = await _identity.getDeviceIdentity();
      final ok = await _db.markAttendanceSecure(
        sessionId: _sessionId!,
        studentId: widget.studentId,
        studentName: widget.studentName,
        identity: identity,
      );

      setState(() {
        _attended = ok ? true : _attended;
        _loading = false;
      });

      _toast(
        ok ? 'Attendance marked!' : 'Attendance already marked',
      );
    } on PostgrestException catch (e) {
      setState(() => _loading = false);
      final msg = e.message;
      if (msg.contains('Attendance blocked') ||
          msg.contains('not your registered attendance device')) {
        _toast(
          'Attendance blocked. This is not your registered attendance device.',
        );
      } else if (msg.contains('Attendance session has ended')) {
        _toast('Attendance session has ended.');
      } else {
        _toast('Error: $msg');
      }
    } catch (e) {
      setState(() => _loading = false);
      _toast('Error: $e');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openHowItWorks() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Theme(
        data: StudentAttendanceUi.themeOverlay(Theme.of(context)),
        child: AlertDialog(
          backgroundColor: StudentAttendanceUi.surfaceElevated,
          title: const Text('How it works'),
          content: const Text(
            'Your phone listens for the teacher’s Bluetooth beacon. '
            'Keep Bluetooth and Location on and stay within range to mark attendance.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: StudentAttendanceUi.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Theme(
        data: StudentAttendanceUi.themeOverlay(Theme.of(context)),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Permissions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  'Bluetooth and location access are required to verify you are near the class.',
                  style: TextStyle(
                    color: StudentAttendanceUi.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    openAppSettings();
                  },
                  child: const Text('Open system settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _elapsedLabel() {
    final start = _sessionStartedAt;
    if (start == null) return '00:00:00';
    final d = DateTime.now().difference(start);
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _startedTimeLabel() {
    final start = _sessionStartedAt;
    if (start == null) return '—';
    final h = start.hour > 12 ? start.hour - 12 : (start.hour == 0 ? 12 : start.hour);
    final ampm = start.hour >= 12 ? 'PM' : 'AM';
    final mm = start.minute.toString().padLeft(2, '0');
    return '$h:$mm $ampm';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionPollTimer?.cancel();
    _uiClockTimer?.cancel();
    _proximitySub?.cancel();
    _pulseController.dispose();
    _ble.stopProximityScanning();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final courseTitle =
        '${widget.offering.subjectCode} - ${widget.offering.subjectTitle}';
    final pad = AppBreakpoints.horizontalPadding(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final radarH = AppBreakpoints.sessionRadarHeight(context, max: 280);
    final maxBody = AppBreakpoints.historyContentMaxWidth(
      MediaQuery.sizeOf(context).width,
    );
    final teal = StudentAttendanceUi.accentTeal;
    final tealDark = StudentAttendanceUi.accentTealDark;
    final success = StudentAttendanceUi.success;
    final themed = StudentAttendanceUi.themeOverlay(Theme.of(context));

    return Theme(
      data: themed,
      child: Scaffold(
        backgroundColor: StudentAttendanceUi.background,
        appBar: AppBar(
          backgroundColor: StudentAttendanceUi.background,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Active Session',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              tooltip: 'Settings',
              onPressed: _openSettingsSheet,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, 16, pad, 28 + bottomInset),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBody),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_bleGranted)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: const Color(0xFF3D2A1F),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: Colors.orange.withValues(alpha: 0.45),
                          ),
                        ),
                        child: InkWell(
                          onTap: () => openAppSettings(),
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.orange.shade300,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Grant Bluetooth and Location in settings to use proximity.',
                                    style: TextStyle(
                                      color: Colors.orange.shade100,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  color: Colors.orange.shade200,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  _SessionHeroCard(
                    sessionActive: _sessionActive,
                    attended: _attended,
                    inRange: _inRange,
                    courseTitle: courseTitle,
                    section: widget.offering.section,
                    teacherName: widget.offering.teacherName,
                    subjectFallback: _subject ?? 'No active session',
                    elapsed: _elapsedLabel(),
                    purple: teal,
                    purpleDark: tealDark,
                    success: success,
                  ),
                  const SizedBox(height: 14),
                  _ProximityBanner(
                    purple: teal,
                    onHowItWorks: _openHowItWorks,
                  ),
                  const SizedBox(height: 16),
                  _StudentRadarPanel(
                    height: radarH,
                    pulse: _pulseController,
                    inRange: _inRange,
                    sessionActive: _sessionActive,
                    purple: teal,
                    success: success,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Stay near the teacher to stay in range. Bluetooth must be ON.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: StudentAttendanceUi.textSecondary,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _sessionActive
                        ? (_inRange
                            ? 'You are within range of the class beacon.'
                            : 'Move closer until you are in range.')
                        : 'Waiting for your teacher to start a session.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: StudentAttendanceUi.textSecondary.withValues(
                        alpha: 0.85,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _MarkAttendanceButton(
                    enabled: _inRange && _sessionActive && !_attended,
                    loading: _loading,
                    onPressed: _markAttendance,
                    purple: teal,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap to record your attendance',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: StudentAttendanceUi.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shield_outlined, size: 16, color: teal),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'You can only mark once per session',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: TextStyle(
                            fontSize: 12,
                            color: teal.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SessionHowItWorksInline(onTap: _openHowItWorks),
                  const SizedBox(height: 16),
                  _SessionInfoCard(
                    startedLabel: _startedTimeLabel(),
                    purple: teal,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _scanningNearby ? null : _scanNearby,
                    icon: _scanningNearby
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bluetooth_searching_rounded),
                    label: Text(
                      _scanningNearby
                          ? 'Scanning nearby…'
                          : 'Scan nearby devices',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: StudentAttendanceUi.mint,
                      side: BorderSide(
                        color: StudentAttendanceUi.mint.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  if (_nearbyDevices.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Nearby (debug)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: StudentAttendanceUi.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...(_nearbyDevices.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value)))
                        .map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    e.key,
                                    style: const TextStyle(
                                      color: StudentAttendanceUi.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${e.value} dBm',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionHowItWorksInline extends StatelessWidget {
  const _SessionHowItWorksInline({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: StudentAttendanceUi.surfaceElevated,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: StudentAttendanceUi.accentTeal,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'How it works',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your phone listens for the teacher’s Bluetooth beacon. '
                      'Keep Bluetooth and Location on and stay within range.',
                      style: TextStyle(
                        color: StudentAttendanceUi.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionHeroCard extends StatelessWidget {
  const _SessionHeroCard({
    required this.sessionActive,
    required this.attended,
    required this.inRange,
    required this.courseTitle,
    required this.section,
    required this.teacherName,
    required this.subjectFallback,
    required this.elapsed,
    required this.purple,
    required this.purpleDark,
    required this.success,
  });

  final bool sessionActive;
  final bool attended;
  final bool inRange;
  final String courseTitle;
  final String section;
  final String teacherName;
  final String subjectFallback;
  final String elapsed;
  final Color purple;
  final Color purpleDark;
  final Color success;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: purpleDark,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: purpleDark.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: sessionActive
                      ? success.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: sessionActive
                        ? success.withValues(alpha: 0.5)
                        : Colors.white24,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.wifi_tethering,
                      size: 16,
                      color: sessionActive ? success : Colors.white54,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      sessionActive ? 'Active Session' : 'No active session',
                      style: TextStyle(
                        color: sessionActive ? success : Colors.white60,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Icon(Icons.schedule_rounded,
                  color: Colors.white.withValues(alpha: 0.7), size: 18),
              const SizedBox(width: 4),
              Text(
                sessionActive ? elapsed : '—',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.menu_book_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sessionActive ? courseTitle : subjectFallback,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Section $section',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Teacher $teacherName',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: Colors.white.withValues(alpha: 0.12)),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: attended
                      ? success
                      : (inRange && sessionActive ? success : Colors.white38),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  !sessionActive
                      ? 'Session not started'
                      : attended
                          ? 'Attendance recorded'
                          : inRange
                              ? 'You are in range'
                              : 'Out of range — move closer',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              Icon(
                Icons.signal_cellular_alt_rounded,
                color: sessionActive && inRange ? success : Colors.white38,
                size: 20,
              ),
              const SizedBox(width: 4),
              Text(
                !sessionActive
                    ? '—'
                    : inRange
                        ? 'Strong'
                        : 'Weak',
                style: TextStyle(
                  color: sessionActive && inRange ? success : Colors.white54,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProximityBanner extends StatelessWidget {
  const _ProximityBanner({
    required this.purple,
    required this.onHowItWorks,
  });

  final Color purple;
  final VoidCallback onHowItWorks;

  @override
  Widget build(BuildContext context) {
    final howBtn = TextButton.icon(
      onPressed: onHowItWorks,
      icon: Icon(Icons.info_outline, size: 18, color: purple),
      label: Text('How it works', style: TextStyle(color: purple)),
    );
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 360;
        final iconCircle = Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: purple.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.near_me_rounded, color: purple, size: 22),
        );
        final copy = Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stay near the teacher to stay in range',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Bluetooth must be ON',
                style: TextStyle(
                  fontSize: 12,
                  color: StudentAttendanceUi.textSecondary,
                ),
              ),
            ],
          ),
        );
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: StudentAttendanceUi.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: StudentAttendanceUi.borderSubtle,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        iconCircle,
                        const SizedBox(width: 12),
                        copy,
                      ],
                    ),
                    Align(alignment: Alignment.centerRight, child: howBtn),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    iconCircle,
                    const SizedBox(width: 12),
                    copy,
                    howBtn,
                  ],
                ),
        );
      },
    );
  }
}

class _StudentRadarPanel extends StatelessWidget {
  const _StudentRadarPanel({
    required this.height,
    required this.pulse,
    required this.inRange,
    required this.sessionActive,
    required this.purple,
    required this.success,
  });

  final double height;
  final Animation<double> pulse;
  final bool inRange;
  final bool sessionActive;
  final Color purple;
  final Color success;

  Widget _signalCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: StudentAttendanceUi.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
          ),
        ],
        border: Border.all(color: StudentAttendanceUi.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.signal_cellular_alt_rounded,
                color: inRange && sessionActive
                    ? success
                    : StudentAttendanceUi.textSecondary,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                sessionActive && inRange ? 'Strong' : '—',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: inRange && sessionActive
                      ? success
                      : StudentAttendanceUi.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            sessionActive && inRange ? 'In range' : 'No lock',
            style: TextStyle(
              fontSize: 11,
              color: StudentAttendanceUi.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            sessionActive && inRange ? 'Excellent' : 'Move closer',
            style: TextStyle(
              fontSize: 11,
              color: StudentAttendanceUi.textSecondary.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hub = (height * 0.29).clamp(64.0, 84.0);
    final iconSz = (hub * 0.52).clamp(30.0, 42.0);
    final topPad = (height * 0.1).clamp(18.0, 32.0);

    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 400;
        final stackHeight = narrow ? height * 0.82 : height;

        final radarStack = SizedBox(
          height: stackHeight,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: StudentAttendanceUi.surfaceElevated,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: StudentAttendanceUi.borderSubtle),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: CustomPaint(
                    painter: _StudentRadarRingsPainter(
                      active: sessionActive && inRange,
                      purple: purple,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              Positioned(
                top: topPad,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: (hub * 0.52).clamp(36.0, 44.0),
                      height: (hub * 0.52).clamp(36.0, 44.0),
                      decoration: BoxDecoration(
                        color: success,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: success.withValues(alpha: 0.35),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Icon(Icons.school_rounded,
                          color: Colors.white, size: iconSz * 0.55),
                    ),
                    const SizedBox(height: 4),
                    CustomPaint(
                      size: Size(2, (stackHeight * 0.12).clamp(24.0, 40.0)),
                      painter: _DottedLinePainter(
                          color: purple.withValues(alpha: 0.35)),
                    ),
                  ],
                ),
              ),
              AnimatedBuilder(
                animation: pulse,
                builder: (context, child) {
                  final scale =
                      inRange && sessionActive ? 1.0 + pulse.value * 0.06 : 1.0;
                  return Transform.scale(
                    scale: scale,
                    child: child,
                  );
                },
                child: Container(
                  width: hub,
                  height: hub,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF1F5F9),
                    boxShadow: [
                      BoxShadow(
                        color: purple.withValues(alpha: inRange ? 0.45 : 0.2),
                        blurRadius: 22,
                        spreadRadius: 2,
                      ),
                    ],
                    border: Border.all(color: purple.withValues(alpha: 0.35)),
                  ),
                  child: Icon(Icons.person_rounded, color: purple, size: iconSz),
                ),
              ),
              if (!narrow)
                Positioned(
                  right: (c.maxWidth * 0.06).clamp(12.0, 28.0),
                  top: stackHeight * 0.38,
                  child: _signalCard(),
                ),
            ],
          ),
        );

        if (narrow) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              radarStack,
              const SizedBox(height: 10),
              Center(child: _signalCard()),
            ],
          );
        }

        return SizedBox(height: height, child: radarStack);
      },
    );
  }
}

class _StudentRadarRingsPainter extends CustomPainter {
  _StudentRadarRingsPainter({required this.active, required this.purple});

  final bool active;
  final Color purple;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2 + 10);
    final maxR = size.shortestSide * 0.38;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = purple.withValues(alpha: active ? 0.22 : 0.10);
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(c, maxR * i / 4, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StudentRadarRingsPainter oldDelegate) {
    return oldDelegate.active != active;
  }
}

class _DottedLinePainter extends CustomPainter {
  _DottedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 4.0;
    const gap = 4.0;
    double y = 0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(0, y + dash), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DottedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _MarkAttendanceButton extends StatelessWidget {
  const _MarkAttendanceButton({
    required this.enabled,
    required this.loading,
    required this.onPressed,
    required this.purple,
  });

  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;
  final Color purple;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [
              purple,
              StudentAttendanceUi.mint,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: StudentAttendanceUi.accentTeal.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled && !loading ? onPressed : null,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (loading)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else
                    const Icon(Icons.check_circle_outline_rounded,
                        color: Colors.white, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    loading ? 'Marking…' : 'Mark Attendance',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionInfoCard extends StatelessWidget {
  const _SessionInfoCard({
    required this.startedLabel,
    required this.purple,
  });

  final String startedLabel;
  final Color purple;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StudentAttendanceUi.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: StudentAttendanceUi.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_note_rounded, color: purple),
              const SizedBox(width: 8),
              const Text(
                'Session Info',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 20,
                color: StudentAttendanceUi.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                'Started at',
                style: TextStyle(
                  color: StudentAttendanceUi.textSecondary,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Text(
                startedLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
