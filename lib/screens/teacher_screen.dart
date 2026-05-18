import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/ble_service.dart';
import '../services/supabase_service.dart';
import '../ui/responsive.dart';
import '../util/db_timestamptz.dart';

class TeacherScreen extends StatefulWidget {
  const TeacherScreen({
    super.key,
    required this.teacherName,
    required this.offering,
  });

  final String teacherName;
  final SubjectOffering offering;

  @override
  State<TeacherScreen> createState() => _TeacherScreenState();
}

class _TeacherScreenState extends State<TeacherScreen>
    with TickerProviderStateMixin {
  final _db = SupabaseService();
  final _ble = BleService();

  bool _active = false;
  bool _loading = false;
  String? _sessionId;
  List<Map<String, dynamic>> _attendees = [];
  List<AttendanceAnomaly> _anomalies = const [];
  Timer? _pollTimer;

  late AnimationController _radarController;

  static const _bg = Color(0xFF0B1220);
  static const _card = Color(0xFF151E32);
  static const _accent = Color(0xFF7C3AED);
  static const _accent2 = Color(0xFFA855F7);
  static const _success = Color(0xFF4ADE80);

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  Future<void> _startSession() async {
    setState(() => _loading = true);
    try {
      // Beacon UUID/name and RSSI come from the admin-configured offering (not typed by teacher).
      const sessionRssi = -100;
      final uuid = widget.offering.beaconUuid.trim();
      final advertisedName = _effectiveAdvertisedBeaconName();
      if (uuid.isEmpty) {
        setState(() => _loading = false);
        _toast(
          'This class has no beacon UUID on file. Ask your administrator to set the beacon on this subject offering.',
        );
        return;
      }

      final granted = await _ble.requestPermissions();
      if (!granted) {
        throw Exception('Bluetooth permissions are required');
      }

      final btOn = await _ble.isBluetoothOn();
      if (!btOn) {
        throw Exception('Please turn on Bluetooth first');
      }

      await _ble.startTeacherBeacon(
        beaconUuid: uuid,
        localName: advertisedName,
      );

      final session = await _db.startSession(
        teacherId: widget.offering.teacherId,
        offeringId: widget.offering.id,
        subject: widget.offering.label,
        beaconUuid: uuid,
        beaconName: advertisedName,
        rssiThreshold: sessionRssi,
      );
      setState(() {
        _sessionId = session['id'];
        _active = true;
        _loading = false;
      });
      _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
      await _refresh();
    } catch (e) {
      setState(() => _loading = false);
      _toast('Error starting session: $e');
    }
  }

  Future<void> _endSession() async {
    if (_sessionId == null) return;
    setState(() => _loading = true);
    _pollTimer?.cancel();
    try {
      await _db.endSession(_sessionId!);
      await _ble.stopTeacherBeacon();
      setState(() {
        _active = false;
        _loading = false;
        _sessionId = null;
        _attendees = [];
      });
    } catch (e) {
      setState(() => _loading = false);
      _toast('Error ending session: $e');
    }
  }

  Future<void> _refresh() async {
    if (_sessionId == null) return;
    final list = await _db.getAttendees(_sessionId!);
    if (mounted) {
      setState(() {
        _attendees = list;
        _anomalies = _db.detectSharedDeviceAnomalies(list);
      });
    }
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  /// BLE local name when starting a session (matches DB session `beacon_name`).
  String _effectiveAdvertisedBeaconName() {
    final configured = widget.offering.beaconName.trim();
    if (configured.isNotEmpty) return configured;
    final code = widget.offering.subjectCode.trim();
    if (code.isNotEmpty) return code;
    return 'Attendance';
  }

  void _openSessionSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Session',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Beacon UUID (from subject offering)\n'
                '${widget.offering.beaconUuid.isEmpty ? 'Not set' : widget.offering.beaconUuid}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Advertised name (BLE)\n${_effectiveAdvertisedBeaconName()}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
              ),
              const SizedBox(height: 8),
              Text(
                'RSSI threshold for this session is −100. Students must be in range of this beacon.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _radarController.dispose();
    _ble.stopTeacherBeacon();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final courseTitle =
        '${widget.offering.subjectCode} - ${widget.offering.subjectTitle}';
    final subline =
        '${widget.teacherName} • Section ${widget.offering.section}';
    final hPad = AppBreakpoints.horizontalPadding(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final radarH = AppBreakpoints.sessionRadarHeight(context);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Teacher Session',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Session details',
            onPressed: _openSessionSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 28 + bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CourseHeroCard(
              courseTitle: courseTitle,
              subline: subline,
              active: _active,
              accent: _accent,
              success: _success,
              cardColor: _card,
            ),
            const SizedBox(height: 20),
            _loading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(color: _accent),
                    ),
                  )
                : _GradientSessionButton(
                    active: _active,
                    onPressed: _active ? _endSession : _startSession,
                  ),
            const SizedBox(height: 8),
            Text(
              'Students can only join when session is active',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, c) {
                final narrow = c.maxWidth < 380;
                final studentCard = _StatMiniCard(
                  icon: Icons.groups_rounded,
                  value: '${_attendees.length}',
                  title: 'Students',
                  subtitle: 'Connected',
                  accent: _accent,
                  card: _card,
                );
                final proximityCard = _StatMiniCard(
                  icon: Icons.near_me_rounded,
                  value: '',
                  title: 'Proximity',
                  subtitle: _active
                      ? 'Scanning for nearby students'
                      : 'Start session to scan',
                  accent: _accent,
                  card: _card,
                  footer: _active
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: _success,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Active',
                              style: TextStyle(
                                color: _success,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          'Idle',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 12,
                          ),
                        ),
                );
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      studentCard,
                      const SizedBox(height: 12),
                      proximityCard,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: studentCard),
                    const SizedBox(width: 12),
                    Expanded(child: proximityCard),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              _active
                  ? 'Scanning for nearby students...'
                  : 'Proximity radar is idle',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Make sure students are within proximity',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 16),
            _TeacherRadar(
              height: radarH,
              animation: _radarController,
              active: _active,
              dotCount: _attendees.length,
              accent: _accent,
              accent2: _accent2,
            ),
            const SizedBox(height: 20),
            _AttendeesExpansion(
              count: _attendees.length,
              cardColor: _card,
              accent: _accent,
              active: _active,
              attendees: _attendees,
              anomalies: _anomalies,
            ),
            const SizedBox(height: 16),
            _HowItWorksCard(card: _card, accent: _accent),
          ],
        ),
      ),
    );
  }
}

class _CourseHeroCard extends StatelessWidget {
  const _CourseHeroCard({
    required this.courseTitle,
    required this.subline,
    required this.active,
    required this.accent,
    required this.success,
    required this.cardColor,
  });

  final String courseTitle;
  final String subline;
  final bool active;
  final Color accent;
  final Color success;
  final Color cardColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -8,
            bottom: -8,
            child: Icon(
              Icons.circle,
              size: 80,
              color: Colors.white.withValues(alpha: 0.03),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent, accent.withValues(alpha: 0.7)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.menu_book_rounded, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      courseTitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subline,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: active
                            ? success.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: active
                              ? success.withValues(alpha: 0.45)
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.wifi_tethering,
                            size: 16,
                            color: active ? success : Colors.white38,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            active ? 'Session live' : 'Ready to start',
                            style: TextStyle(
                              color: active ? success : Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      active
                          ? 'Students can join while this session is running.'
                          : 'You can start the session anytime.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GradientSessionButton extends StatelessWidget {
  const _GradientSessionButton({
    required this.active,
    required this.onPressed,
  });

  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (active) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.stop_circle_outlined),
        label: const Text('End Session'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFDC2626),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF6366F1)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.play_circle_fill_rounded,
                    color: Colors.white, size: 26),
                SizedBox(width: 10),
                Text(
                  'Start Session',
                  style: TextStyle(
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
    );
  }
}

class _StatMiniCard extends StatelessWidget {
  const _StatMiniCard({
    required this.icon,
    required this.value,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.card,
    this.footer,
  });

  final IconData icon;
  final String value;
  final String title;
  final String subtitle;
  final Color accent;
  final Color card;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          if (value.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                height: 1,
              ),
            ),
          ] else
            const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.45),
              height: 1.3,
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 10),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _TeacherRadar extends StatelessWidget {
  const _TeacherRadar({
    required this.height,
    required this.animation,
    required this.active,
    required this.dotCount,
    required this.accent,
    required this.accent2,
  });

  final double height;
  final Animation<double> animation;
  final bool active;
  final int dotCount;
  final Color accent;
  final Color accent2;

  @override
  Widget build(BuildContext context) {
    final displayDots = active
        ? (dotCount > 0 ? math.min(dotCount, 6) : 3)
        : 0;
    final hub = (height * 0.27).clamp(52.0, 72.0);
    final iconSize = (hub * 0.48).clamp(26.0, 36.0);
    return SizedBox(
      height: height,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          return CustomPaint(
            painter: _RadarPainter(
              sweepAngle: active ? animation.value * math.pi * 2 : 0,
              active: active,
              dotCount: displayDots,
              accent: accent,
              accent2: accent2,
            ),
            child: Center(
              child: Container(
                width: hub,
                height: hub,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [accent, accent2],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(Icons.groups_rounded,
                    color: Colors.white, size: iconSize),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.sweepAngle,
    required this.active,
    required this.dotCount,
    required this.accent,
    required this.accent2,
  });

  final double sweepAngle;
  final bool active;
  final int dotCount;
  final Color accent;
  final Color accent2;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final maxR = size.shortestSide * 0.42;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: active ? 0.14 : 0.06);

    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(c, maxR * i / 4, ringPaint);
    }

    if (active) {
      final sweepPaint = Paint()
        ..shader = SweepGradient(
          colors: [
            accent2.withValues(alpha: 0),
            accent2.withValues(alpha: 0.25),
            accent2.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.5, 1.0],
          transform: GradientRotation(sweepAngle),
        ).createShader(Rect.fromCircle(center: c, radius: maxR));

      canvas.drawCircle(c, maxR, sweepPaint);
    }

    final rnd = math.Random(42);
    for (var i = 0; i < dotCount; i++) {
      final ang = rnd.nextDouble() * math.pi * 2;
      final rad = maxR * (0.35 + rnd.nextDouble() * 0.55);
      final p = c + Offset(math.cos(ang), math.sin(ang)) * rad;
      final glow = Paint()
        ..color = Colors.white.withValues(alpha: active ? 0.85 : 0.35);
      canvas.drawCircle(p, 5, glow);
      canvas.drawCircle(
        p,
        3,
        Paint()..color = accent.withValues(alpha: 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.sweepAngle != sweepAngle ||
        oldDelegate.active != active ||
        oldDelegate.dotCount != dotCount;
  }
}

class _AttendeesExpansion extends StatelessWidget {
  const _AttendeesExpansion({
    required this.count,
    required this.cardColor,
    required this.accent,
    required this.active,
    required this.attendees,
    required this.anomalies,
  });

  final int count;
  final Color cardColor;
  final Color accent;
  final bool active;
  final List<Map<String, dynamic>> attendees;
  final List<AttendanceAnomaly> anomalies;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        iconColor: Colors.white70,
        collapsedIconColor: Colors.white70,
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.25),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.groups_rounded, color: Colors.white, size: 20),
        ),
        title: const Text(
          'View Attendees',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const Icon(Icons.expand_more_rounded, color: Colors.white70),
          ],
        ),
        children: [
          if (anomalies.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                children: anomalies
                    .map(
                      (a) => Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7F1D1D).withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFFCA5A5).withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          'Possible shared device used by: ${a.students.join(' and ')}.',
                          style: const TextStyle(
                            color: Color(0xFFFECACA),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          if (!active)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'Start a session to see live attendance.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
              ),
            )
          else if (attendees.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Text(
                'Waiting for students...',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              itemCount: attendees.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: Colors.white.withValues(alpha: 0.06),
              ),
              itemBuilder: (_, i) {
                final a = attendees[i];
                final t = tryParseDbTimestamptzToLocal(a['marked_at']);
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: accent.withValues(alpha: 0.2),
                    child: Text(
                      (a['student_name'] as String)[0].toUpperCase(),
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    a['student_name'] as String,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    [
                      if ((a['device_name'] as String?)?.trim().isNotEmpty ?? false)
                        'Device: ${a['device_name']}',
                      if (!((a['device_name'] as String?)?.trim().isNotEmpty ?? false) &&
                          ((a['device_fingerprint'] as String?)?.trim().isNotEmpty ?? false))
                        'Device fingerprint on file',
                    ].join('\n'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                  trailing: t != null
                      ? Text(
                          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                        )
                      : null,
                );
              },
            ),
        ],
      ),
    );
  }
}

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard({required this.card, required this.accent});

  final Color card;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_user_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'How it works',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Students must be nearby with Bluetooth and Location enabled to join.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.5),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.smartphone_rounded,
              color: Colors.white.withValues(alpha: 0.2), size: 40),
        ],
      ),
    );
  }
}
