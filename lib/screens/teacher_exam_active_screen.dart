import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/ble_service.dart';
import '../services/exam_service.dart';
import '../services/supabase_service.dart';
import '../ui/exam_ui.dart';
import '../ui/responsive.dart';
import '../ui/teacher_attendance_ui.dart';
import 'teacher_exam_monitoring_screen.dart';

class TeacherExamActiveScreen extends StatefulWidget {
  const TeacherExamActiveScreen({
    super.key,
    required this.offering,
    required this.session,
    this.onSessionChanged,
  });

  final SubjectOffering offering;
  final ExamSession session;
  final VoidCallback? onSessionChanged;

  @override
  State<TeacherExamActiveScreen> createState() => _TeacherExamActiveScreenState();
}

class _TeacherExamActiveScreenState extends State<TeacherExamActiveScreen> {
  final _exam = ExamService();
  final _ble = BleService();

  late ExamSession _session;
  bool _beaconOn = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    if (_session.isActive || _session.isPaused) {
      unawaited(_ensureBeacon());
    }
  }

  @override
  void dispose() {
    unawaited(_ble.stopExamBeaconAdvertising());
    super.dispose();
  }

  String _beaconAdvertisedName() {
    final configured = widget.offering.beaconName.trim();
    if (configured.isNotEmpty) return configured;
    final code = widget.offering.subjectCode.trim();
    if (code.isNotEmpty) return code;
    return AppConfig.defaultBeaconName;
  }

  String get _beaconUuid {
    return ExamService.resolveBeaconUuid(
      session: _session,
      offeringBeaconUuid: widget.offering.beaconUuid,
    );
  }

  Future<void> _ensureBeacon() async {
    final uuid = _beaconUuid;
    if (uuid.isEmpty) {
      if (mounted) setState(() => _beaconOn = false);
      return;
    }
    try {
      final permissionIssue = await _ble.examBlePermissionIssue();
      if (permissionIssue != null) {
        debugPrint('[exam] beacon permissions: $permissionIssue');
        if (mounted) setState(() => _beaconOn = false);
        return;
      }
      if (!await _ble.isBluetoothOn()) {
        if (mounted) setState(() => _beaconOn = false);
        return;
      }
      await _ble.startExamBeaconAdvertising(
        bleUuid: uuid,
        beaconName: _beaconAdvertisedName(),
      );
      if (mounted) setState(() => _beaconOn = true);
    } catch (e) {
      debugPrint('[exam] teacher beacon: $e');
      if (mounted) setState(() => _beaconOn = false);
    }
  }

  Future<void> _reloadSession() async {
    final fresh = await _exam.getExamSessionById(_session.id);
    if (fresh != null && mounted) {
      setState(() => _session = fresh);
      widget.onSessionChanged?.call();
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirmAction({
    required String title,
    required String body,
    required String confirmLabel,
    required Future<void> Function() action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TeacherAttendanceUi.surface,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(
          body,
          style: const TextStyle(color: TeacherAttendanceUi.textOnField),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await action();
      await _reloadSession();
    } on ExamServiceException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startExamNow() async {
    setState(() => _busy = true);
    try {
      await _exam.activateExamSession(_session.id);
      await _reloadSession();
      await _ensureBeacon();
      _toast('Exam is now active. Share the code with students.');
    } on ExamServiceException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fmt(DateTime? dt) => ExamUi.formatExamDateTime(dt);

  @override
  Widget build(BuildContext context) {
    final hPad = AppBreakpoints.horizontalPadding(context);
    final canJoin = _session.isJoinable;
    final isPaused = _session.isPaused;
    final isTerminal = _session.isTerminal;

    return Theme(
      data: TeacherAttendanceUi.themeOverlay(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(title: const Text('Exam Active')),
        body: _busy
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 32),
                children: [
                  Card(
                    color: canJoin
                        ? TeacherAttendanceUi.presentGreen.withValues(alpha: 0.12)
                        : TeacherAttendanceUi.textSecondary.withValues(alpha: 0.08),
                    child: ListTile(
                      leading: Icon(
                        _beaconOn ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                        color: _beaconOn
                            ? TeacherAttendanceUi.presentGreen
                            : TeacherAttendanceUi.absentOrange,
                      ),
                      title: const Text(
                        'Exam Active',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      subtitle: Text(
                        'BLE Broadcasting: ${_beaconOn ? 'ON' : 'OFF'}',
                        style: const TextStyle(
                          color: TeacherAttendanceUi.textOnField,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (!_beaconOn && canJoin && _beaconUuid.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton.icon(
                        onPressed: _ensureBeacon,
                        icon: const Icon(Icons.bluetooth_searching),
                        label: const Text('Start BLE broadcasting'),
                      ),
                    ),
                  if (_beaconUuid.isEmpty)
                    Card(
                      color: TeacherAttendanceUi.anomalyRed.withValues(alpha: 0.12),
                      child: const ListTile(
                        leading: Icon(Icons.warning_amber_rounded,
                            color: TeacherAttendanceUi.anomalyRed),
                        title: Text('No beacon UUID on this class'),
                        subtitle: Text(
                          'Set beacon UUID on the subject offering before students can join.',
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _session.examTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${widget.offering.subjectCode} • Section ${widget.offering.section}',
                            style: const TextStyle(
                              color: TeacherAttendanceUi.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _DetailRow(
                            label: 'Advertising UUID',
                            value: _beaconUuid.isEmpty ? '—' : _beaconUuid,
                            mono: true,
                          ),
                          const SizedBox(height: 8),
                          _DetailRow(
                            label: 'Beacon name',
                            value: _beaconAdvertisedName(),
                          ),
                          const SizedBox(height: 8),
                          _DetailRow(
                            label: 'RSSI threshold',
                            value: '${_session.rssiThreshold} dBm',
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Exam code',
                            style: TextStyle(
                              color: TeacherAttendanceUi.textOnField,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _session.examCode,
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Copy code',
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: _session.examCode),
                                  );
                                  _toast('Exam code copied.');
                                },
                                icon: const Icon(Icons.copy_outlined),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DetailRow(label: 'Status', value: _session.status),
                  _DetailRow(label: 'Starts', value: _fmt(_session.startsAt)),
                  _DetailRow(label: 'Ends', value: _fmt(_session.endsAt)),
                  _DetailRow(
                    label: 'RSSI (monitor)',
                    value: '${_session.rssiThreshold} dBm',
                  ),
                  _DetailRow(
                    label: 'RSSI (student join)',
                    value:
                        '${ExamService.examJoinProximityRssi(_session.rssiThreshold)} dBm',
                  ),
                  _DetailRow(
                    label: 'Grace period',
                    value: '${_session.gracePeriodSeconds}s',
                  ),
                  _DetailRow(label: 'Created', value: _fmt(_session.createdAt)),
                  const SizedBox(height: 20),
                  if (_session.status == 'scheduled') ...[
                    FilledButton.icon(
                      onPressed: _startExamNow,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Start exam now'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (canJoin) ...[
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TeacherExamMonitoringScreen(
                              offering: widget.offering,
                              session: _session,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.monitor_heart_outlined),
                      label: const Text('Open live monitor'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _confirmAction(
                        title: 'Pause exam?',
                        body:
                            'Students cannot join while paused. In-progress attempts stay open until you resume or end.',
                        confirmLabel: 'Pause',
                        action: () => _exam.pauseExamSession(_session.id),
                      ),
                      icon: const Icon(Icons.pause_circle_outline),
                      label: const Text('Pause exam'),
                    ),
                  ],
                  if (isPaused) ...[
                    FilledButton.icon(
                      onPressed: () async {
                        setState(() => _busy = true);
                        try {
                          await _exam.resumeExamSession(_session.id);
                          await _reloadSession();
                          await _ensureBeacon();
                          _toast('Exam resumed.');
                        } on ExamServiceException catch (e) {
                          _toast(e.message);
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Resume exam'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (!isTerminal) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: TeacherAttendanceUi.absentOrange,
                        side: const BorderSide(color: TeacherAttendanceUi.absentOrange),
                      ),
                      onPressed: () => _confirmAction(
                        title: 'End exam?',
                        body:
                            'Marks the session ended. Students can no longer join; in-progress attempts are notified.',
                        confirmLabel: 'End exam',
                        action: () async {
                          await _exam.endExamSession(_session.id);
                          await _ble.stopExamBeaconAdvertising();
                          if (mounted) setState(() => _beaconOn = false);
                        },
                      ),
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('End exam now'),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: TeacherAttendanceUi.anomalyRed,
                      ),
                      onPressed: () => _confirmAction(
                        title: 'Cancel exam?',
                        body:
                            'Force-cancels this session. Use if the exam should not continue.',
                        confirmLabel: 'Cancel exam',
                        action: () async {
                          await _exam.cancelExamSession(_session.id);
                          await _ble.stopExamBeaconAdvertising();
                          if (mounted) setState(() => _beaconOn = false);
                        },
                      ),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Force cancel exam'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: TeacherAttendanceUi.textOnField,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    fontFamily: mono ? 'monospace' : null,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
