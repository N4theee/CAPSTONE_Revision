import 'dart:async';

import 'package:flutter/material.dart';

import '../services/exam_service.dart';
import '../services/supabase_service.dart';
import '../ui/responsive.dart';
import '../ui/teacher_attendance_ui.dart';

class TeacherExamMonitoringScreen extends StatefulWidget {
  const TeacherExamMonitoringScreen({
    super.key,
    required this.offering,
    required this.session,
  });

  final SubjectOffering offering;
  final ExamSession session;

  @override
  State<TeacherExamMonitoringScreen> createState() =>
      _TeacherExamMonitoringScreenState();
}

class _TeacherExamMonitoringScreenState extends State<TeacherExamMonitoringScreen> {
  final _exam = ExamService();
  List<ExamAttemptMonitorRow> _attempts = [];
  final List<ExamAlertItem> _liveAlertFeed = [];
  StreamSubscription<List<ExamAlertItem>>? _alertSub;
  Timer? _pollTimer;
  bool _loading = true;

  final _seenAlertIds = <String>{};
  var _alertsInitialized = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    _alertSub = _exam.listenToExamAlerts(widget.session.id).listen(
      (items) {
        if (!mounted) return;
        _onAlertsUpdated(items);
      },
      onError: (e) => debugPrint('[monitor] alerts: $e'),
    );
  }

  void _onAlertsUpdated(List<ExamAlertItem> items) {
    if (!_alertsInitialized) {
      _alertsInitialized = true;
      _seenAlertIds.addAll(items.map((a) => a.id));
      setState(() {
        _liveAlertFeed
          ..clear()
          ..addAll(items.take(8));
      });
      return;
    }

    final newlyArrived = <ExamAlertItem>[];
    for (final a in items) {
      if (_seenAlertIds.contains(a.id)) continue;
      _seenAlertIds.add(a.id);
      newlyArrived.add(a);
    }

    if (newlyArrived.isEmpty) return;

    newlyArrived.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    setState(() {
      for (final a in newlyArrived) {
        _liveAlertFeed.insert(0, a);
      }
      while (_liveAlertFeed.length > 12) {
        _liveAlertFeed.removeLast();
      }
    });

    for (final a in newlyArrived) {
      _showRealtimeAlertNotice(a);
    }
    unawaited(_refresh());
  }

  void _showRealtimeAlertNotice(ExamAlertItem alert) {
    final text = _alertDisplayText(alert);
    final style = _alertStyle(alert.alertType);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: style.background,
          duration: const Duration(seconds: 5),
          content: Row(
            children: [
              Icon(style.icon, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
  }

  String _alertDisplayText(ExamAlertItem alert) {
    final fromDb = alert.message.trim();
    if (fromDb.isNotEmpty) return fromDb;
    return ExamService.teacherAlertMessage(
      alertType: alert.alertType,
      studentName: alert.studentName ?? 'A student',
    );
  }

  _AlertStyle _alertStyle(String alertType) {
    switch (alertType) {
      case 'out_of_range':
        return const _AlertStyle(
          background: TeacherAttendanceUi.anomalyRed,
          accent: TeacherAttendanceUi.anomalyRed,
          icon: Icons.warning_amber_rounded,
        );
      case 'returned_in_range':
        return const _AlertStyle(
          background: TeacherAttendanceUi.presentGreen,
          accent: TeacherAttendanceUi.presentGreen,
          icon: Icons.check_circle_outline,
        );
      case 'auto_ended':
        return const _AlertStyle(
          background: TeacherAttendanceUi.absentOrange,
          accent: TeacherAttendanceUi.absentOrange,
          icon: Icons.stop_circle_outlined,
        );
      default:
        return const _AlertStyle(
          background: TeacherAttendanceUi.accentPurple,
          accent: TeacherAttendanceUi.accentPurpleMuted,
          icon: Icons.info_outline,
        );
    }
  }

  Future<void> _refresh() async {
    try {
      final rows = await _exam.getExamAttemptMonitorRows(widget.session.id);
      if (!mounted) return;
      setState(() {
        _attempts = rows;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _alertSub?.cancel();
    super.dispose();
  }

  String _fmtTime(DateTime dt) {
    final l = dt.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Color _statusColor(ExamAttemptMonitorRow row) {
    final label = ExamService.studentMonitorStatusLabel(row);
    switch (label) {
      case 'In Range':
        return TeacherAttendanceUi.presentGreen;
      case 'Out of Range':
        return TeacherAttendanceUi.anomalyRed;
      case 'Auto Ended':
        return TeacherAttendanceUi.absentOrange;
      case 'Completed':
        return TeacherAttendanceUi.accentPurple;
      default:
        return TeacherAttendanceUi.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hPad = AppBreakpoints.horizontalPadding(context);
    final latestLive = _liveAlertFeed.isNotEmpty ? _liveAlertFeed.first : null;

    return Theme(
      data: TeacherAttendanceUi.themeOverlay(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Monitor Exam'),
          actions: [
            IconButton(
              tooltip: 'Refresh students',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await _refresh();
            final items = await _exam.fetchExamAlerts(widget.session.id);
            if (mounted) _onAlertsUpdated(items);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.session.examTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.session.examCode,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${widget.offering.subjectCode} • Section ${widget.offering.section}',
                        style: const TextStyle(
                          color: TeacherAttendanceUi.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Status: ${widget.session.status} • '
                        'RSSI ${widget.session.rssiThreshold} • '
                        'Grace ${widget.session.gracePeriodSeconds}s',
                        style: const TextStyle(
                          color: TeacherAttendanceUi.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (latestLive != null) ...[
                const SizedBox(height: 12),
                _LiveAlertCard(
                  alert: latestLive,
                  displayText: _alertDisplayText(latestLive),
                  style: _alertStyle(latestLive.alertType),
                  timeLabel: _fmtTime(latestLive.createdAt),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.notifications_active_outlined,
                      size: 18, color: TeacherAttendanceUi.accentPurple),
                  const SizedBox(width: 6),
                  const Text(
                    'Live proximity alerts',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const Spacer(),
                  if (_alertSub != null)
                    Text(
                      'Realtime',
                      style: TextStyle(
                        color: TeacherAttendanceUi.presentGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Updates when students leave or return to BLE range.',
                style: TextStyle(
                  color: TeacherAttendanceUi.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              if (_liveAlertFeed.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'No proximity alerts yet. Alerts appear when a student goes out of exam range.',
                      style: TextStyle(color: TeacherAttendanceUi.textSecondary),
                    ),
                  ),
                )
              else
                ..._liveAlertFeed.map(
                  (a) => _AlertHistoryTile(
                    alert: a,
                    displayText: _alertDisplayText(a),
                    style: _alertStyle(a.alertType),
                    timeLabel: _fmtTime(a.createdAt),
                    compact: a.id != latestLive?.id,
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text(
                    'Joined students',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_attempts.length}',
                    style: const TextStyle(
                      color: TeacherAttendanceUi.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_attempts.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No students have joined this exam yet.',
                      style: TextStyle(color: TeacherAttendanceUi.textSecondary),
                    ),
                  ),
                )
              else
                ..._attempts.map(
                  (row) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            _statusColor(row).withValues(alpha: 0.18),
                        child: Icon(
                          _statusIcon(row),
                          color: _statusColor(row),
                          size: 20,
                        ),
                      ),
                      title: Text(
                        row.studentName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Violations: ${row.violationCount}'
                        '${row.startedAt != null ? ' • Joined ${_fmtTime(row.startedAt!)}' : ''}',
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(row).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _statusColor(row)),
                        ),
                        child: Text(
                          ExamService.studentMonitorStatusLabel(row),
                          style: TextStyle(
                            color: _statusColor(row),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _statusIcon(ExamAttemptMonitorRow row) {
    switch (ExamService.studentMonitorStatusLabel(row)) {
      case 'In Range':
        return Icons.sensors_rounded;
      case 'Out of Range':
        return Icons.sensors_off_rounded;
      case 'Auto Ended':
        return Icons.stop_circle_outlined;
      case 'Completed':
        return Icons.task_alt_rounded;
      default:
        return Icons.person_outline;
    }
  }
}

class _AlertStyle {
  const _AlertStyle({
    required this.background,
    required this.accent,
    required this.icon,
  });

  final Color background;
  final Color accent;
  final IconData icon;
}

class _LiveAlertCard extends StatelessWidget {
  const _LiveAlertCard({
    required this.alert,
    required this.displayText,
    required this.style,
    required this.timeLabel,
  });

  final ExamAlertItem alert;
  final String displayText;
  final _AlertStyle style;
  final String timeLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(14),
      color: style.accent.withValues(alpha: 0.12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: style.accent, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(style.icon, color: style.accent, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Latest alert',
                    style: TextStyle(
                      color: style.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    displayText,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    timeLabel,
                    style: const TextStyle(
                      color: TeacherAttendanceUi.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertHistoryTile extends StatelessWidget {
  const _AlertHistoryTile({
    required this.alert,
    required this.displayText,
    required this.style,
    required this.timeLabel,
    this.compact = true,
  });

  final ExamAlertItem alert;
  final String displayText;
  final _AlertStyle style;
  final String timeLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: compact ? 6 : 10),
      color: compact ? null : style.accent.withValues(alpha: 0.06),
      child: ListTile(
        dense: compact,
        leading: Icon(style.icon, color: style.accent),
        title: Text(
          displayText,
          style: TextStyle(
            fontWeight: compact ? FontWeight.w500 : FontWeight.w600,
            fontSize: compact ? 13 : 14,
          ),
        ),
        trailing: Text(
          timeLabel,
          style: const TextStyle(
            fontSize: 11,
            color: TeacherAttendanceUi.textSecondary,
          ),
        ),
      ),
    );
  }
}
