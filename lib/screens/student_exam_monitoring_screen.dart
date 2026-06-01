import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../services/ble_service.dart';
import '../services/supabase_service.dart';
import '../ui/responsive.dart';
import '../ui/student_attendance_ui.dart';
import 'take_exam_screen.dart';

class StudentExamMonitoringScreen extends StatefulWidget {
  const StudentExamMonitoringScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.offering,
    required this.session,
    required this.attempt,
  });

  final String studentId;
  final String studentName;
  final SubjectOffering offering;
  final ExamSession session;
  final ExamAttempt attempt;

  @override
  State<StudentExamMonitoringScreen> createState() =>
      _StudentExamMonitoringScreenState();
}

class _StudentExamMonitoringScreenState extends State<StudentExamMonitoringScreen>
    with WidgetsBindingObserver {
  final _exam = ExamService();
  final _ble = BleService();

  bool _inRange = false;
  int? _rssi;
  DateTime? _lastSeenInRangeAt;
  bool _monitoring = true;
  bool _ended = false;
  String _attemptStatus = 'in_progress';
  int _violationCount = 0;
  bool _submittedMcq = false;
  int? _questionCount;

  Timer? _sessionPollTimer;
  bool _warningDialogOpen = false;
  bool _autoEndInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attemptStatus = widget.attempt.status;
    _violationCount = widget.attempt.violationCount;
    _submittedMcq = widget.attempt.status == 'completed';
    unawaited(_loadQuestionCount());
    _initMonitoring();
  }

  String _beaconAdvertisedName() {
    final configured = widget.offering.beaconName.trim();
    if (configured.isNotEmpty) return configured;
    final code = widget.offering.subjectCode.trim();
    if (code.isNotEmpty) return code;
    return AppConfig.defaultBeaconName;
  }

  String get _beaconUuid => ExamService.resolveBeaconUuid(
        session: widget.session,
        offeringBeaconUuid: widget.offering.beaconUuid,
      );

  int get _rssiThreshold => widget.session.rssiThreshold;

  Future<void> _initMonitoring() async {
    final permissionIssue = await _ble.examBlePermissionIssue();
    if (permissionIssue != null && mounted) {
      await _showInfoDialog('Permissions required', permissionIssue);
      return;
    }

    await _startBleMonitor();

    _sessionPollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_checkSessionAndAttempt());
    });
    await _checkSessionAndAttempt();
  }

  Future<void> _loadQuestionCount() async {
    try {
      final n = await _exam.countExamQuestions(widget.session.id);
      if (mounted) setState(() => _questionCount = n);
    } catch (_) {}
  }

  Future<void> _openTakeExam() async {
    if (_ended && _attemptStatus != 'in_progress') return;
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TakeExamScreen(
          session: widget.session,
          attempt: widget.attempt,
          offering: widget.offering,
        ),
      ),
    );
    if (submitted == true && mounted) {
      final fresh = await _exam.getExamAttemptById(widget.attempt.id);
      setState(() {
        _submittedMcq = true;
        if (fresh != null) {
          _attemptStatus = fresh.status;
        }
      });
    }
  }

  Future<void> _checkSessionAndAttempt() async {
    if (!_monitoring || _ended) return;

    final sessionRow = await _exam.getExamSessionById(widget.session.id);
    if (sessionRow != null && sessionRow.isTerminal) {
      await _finishMonitoring(
        status: _attemptStatus,
        message: 'The exam session is no longer active (${sessionRow.status}).',
      );
      return;
    }

    final fresh = await _exam.getExamAttemptById(widget.attempt.id);
    if (fresh != null &&
        (fresh.status == 'auto_ended' || fresh.status == 'flagged')) {
      await _finishMonitoring(
        status: fresh.status,
        message: 'Exam ended (${fresh.status}).',
      );
    }
  }

  Future<void> _persistProximityLog({
    required int rssi,
    required bool isInRange,
  }) async {
    try {
      await _exam.saveProximityLog(
        examAttemptId: widget.attempt.id,
        studentId: widget.studentId,
        examSessionId: widget.session.id,
        isInRange: isInRange,
        rssi: isInRange ? rssi : null,
      );
    } catch (e) {
      debugPrint('[exam] proximity log error: $e');
    }
  }

  Future<void> _handleOutOfRange() async {
    if (_ended) return;
    _violationCount += 1;
    try {
      await _exam.updateExamAttemptStatus(
        attemptId: widget.attempt.id,
        status: 'in_progress',
        violationCount: _violationCount,
      );
      await _exam.createExamAlert(
        examSessionId: widget.session.id,
        studentId: widget.studentId,
        examAttemptId: widget.attempt.id,
        alertType: 'out_of_range',
        message: ExamService.teacherAlertMessage(
          alertType: 'out_of_range',
          studentName: widget.studentName,
        ),
      );
    } catch (e) {
      debugPrint('[exam] out_of_range alert error: $e');
    }
    if (mounted) {
      setState(() {});
      await _showOutOfRangeWarning();
    }
  }

  Future<void> _handleReturnedInRange() async {
    if (_ended) return;
    try {
      await _exam.createExamAlert(
        examSessionId: widget.session.id,
        studentId: widget.studentId,
        examAttemptId: widget.attempt.id,
        alertType: 'returned_in_range',
        message: ExamService.teacherAlertMessage(
          alertType: 'returned_in_range',
          studentName: widget.studentName,
        ),
      );
    } catch (e) {
      debugPrint('[exam] returned_in_range alert error: $e');
    }
  }

  Future<void> _handleAutoEndRequired() async {
    if (_ended || _autoEndInProgress) return;
    _autoEndInProgress = true;
    final now = DateTime.now();
    try {
      await _exam.updateExamAttemptStatus(
        attemptId: widget.attempt.id,
        status: 'auto_ended',
        endedAt: now,
        violationCount: _violationCount,
      );
      await _exam.createExamAlert(
        examSessionId: widget.session.id,
        studentId: widget.studentId,
        examAttemptId: widget.attempt.id,
        alertType: 'auto_ended',
        message: ExamService.teacherAlertMessage(
          alertType: 'auto_ended',
          studentName: widget.studentName,
        ),
      );
    } catch (e) {
      debugPrint('[exam] auto_end error: $e');
    }
    await _finishMonitoring(
      status: 'auto_ended',
      message:
          'Your exam was auto-ended because you were out of range for more than '
          '${widget.session.gracePeriodSeconds} seconds.',
    );
  }

  Future<void> _showOutOfRangeWarning() async {
    if (_warningDialogOpen || !mounted || _ended) return;
    _warningDialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudentAttendanceUi.surfaceElevated,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Text('Out of range'),
          ],
        ),
        content: Text(
          'You left the exam proximity zone. Return within '
          '${widget.session.gracePeriodSeconds} seconds or your attempt will end automatically.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    _warningDialogOpen = false;
  }

  Future<void> _finishMonitoring({
    required String status,
    required String message,
  }) async {
    _monitoring = false;
    _ended = true;
    _attemptStatus = status;
    _sessionPollTimer?.cancel();
    _ble.stopExamProximityMonitoring();
    if (!mounted) return;
    setState(() {});
    await _showInfoDialog('Exam ended', message);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _showInfoDialog(String title, String body) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudentAttendanceUi.surfaceElevated,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _startBleMonitor() async {
    await _ble.monitorExamProximity(
      expectedBleUuid: _beaconUuid,
      beaconName: _beaconAdvertisedName(),
      rssiThreshold: _rssiThreshold,
      gracePeriodSeconds: widget.session.gracePeriodSeconds,
      smoothingSeconds: AppConfig.examProximitySmoothingSeconds,
      onReading: (rssi, inRange) {
        if (!mounted || _ended) return;
        setState(() {
          _inRange = inRange;
          _rssi = rssi;
          if (inRange) {
            _lastSeenInRangeAt = DateTime.now();
          }
        });
        unawaited(_persistProximityLog(rssi: rssi, isInRange: inRange));
      },
      onOutOfRange: () {
        if (!mounted || _ended) return;
        unawaited(_handleOutOfRange());
      },
      onReturnedInRange: () {
        if (!mounted || _ended) return;
        unawaited(_handleReturnedInRange());
      },
      onAutoEndRequired: () {
        if (!mounted || _ended || _autoEndInProgress) return;
        unawaited(_handleAutoEndRequired());
      },
    );
  }

  Future<void> _resumeExamBleMonitor() async {
    if (_ended || !_monitoring) return;
    await _startBleMonitor();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_ended) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeExamBleMonitor());
    } else if (state == AppLifecycleState.paused) {
      _ble.stopExamProximityMonitoring();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionPollTimer?.cancel();
    _ble.stopExamProximityMonitoring();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hPad = AppBreakpoints.horizontalPadding(context);
    final subjectLabel =
        '${widget.offering.subjectCode} - ${widget.offering.subjectTitle}';
    final statusLabel = _inRange ? 'In Range' : 'Out of Range';
    final statusColor =
        _inRange ? StudentAttendanceUi.success : Colors.orangeAccent;

    return PopScope(
      canPop: _ended,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _ended) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: StudentAttendanceUi.surfaceElevated,
            title: const Text('Leave exam?'),
            content: const Text(
              'Proximity monitoring is still active. Leaving may count as out of range.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Stay'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Leave'),
              ),
            ],
          ),
        );
        if (leave == true && context.mounted) {
          _monitoring = false;
          _sessionPollTimer?.cancel();
          _ble.stopExamProximityMonitoring();
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Theme(
        data: StudentAttendanceUi.themeOverlay(Theme.of(context)),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Exam in progress'),
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 32),
            children: [
              Text(
                widget.session.examTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subjectLabel,
                style: const TextStyle(
                  color: StudentAttendanceUi.textSecondary,
                  fontSize: 14,
                ),
              ),
              Text(
                'Code ${widget.session.examCode} • Section ${widget.offering.section}',
                style: const TextStyle(
                  color: StudentAttendanceUi.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        _inRange
                            ? Icons.sensors_rounded
                            : Icons.sensors_off_rounded,
                        size: 48,
                        color: statusColor,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                      if (_rssi != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'RSSI $_rssi (threshold $_rssiThreshold)',
                          style: const TextStyle(
                            color: StudentAttendanceUi.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Attempt: $_attemptStatus • Violations: $_violationCount',
                        style: const TextStyle(
                          color: StudentAttendanceUi.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Grace period: ${widget.session.gracePeriodSeconds}s out of range before auto-end',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: StudentAttendanceUi.textSecondary
                              .withValues(alpha: 0.85),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_questionCount != null && _questionCount! > 0) ...[
                if (_submittedMcq)
                  Card(
                    color: StudentAttendanceUi.success.withValues(alpha: 0.12),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'Exam answers submitted. Proximity monitoring continues until the session ends.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed: _openTakeExam,
                    icon: const Icon(Icons.edit_note_rounded),
                    label: Text(
                      'Answer exam ($_questionCount questions)',
                    ),
                  ),
                const SizedBox(height: 12),
              ] else if (_questionCount == 0)
                const Text(
                  'Waiting for exam questions from your teacher.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: StudentAttendanceUi.textSecondary,
                    fontSize: 12,
                  ),
                ),
              Text(
                'Stay near the teacher device. Brief signal drops are ignored for '
                '${AppConfig.examProximitySmoothingSeconds}s. '
                'Grace period: ${widget.session.gracePeriodSeconds}s out of range before auto-end.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: StudentAttendanceUi.textOnField,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              if (AppConfig.showExamBleDebugPanel) ...[
                const SizedBox(height: 16),
                _examBleDebugPanel(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _examBleDebugPanel() {
    final detectedRssi = _rssi;
    final threshold = _rssiThreshold;
    final inRangeNow = detectedRssi != null && detectedRssi >= threshold;
    final match = _ble.lastExamBeaconMatch;

    return Card(
      color: StudentAttendanceUi.surface.withValues(alpha: 0.6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BLE debug (dev)',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: StudentAttendanceUi.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            _debugRow('Expected UUID', _beaconUuid),
            _debugRow('Expected beacon name', _beaconAdvertisedName()),
            _debugRow('Current threshold', '$threshold'),
            _debugRow('Last detected RSSI', detectedRssi?.toString() ?? '—'),
            _debugRow(
              'Found UUIDs',
              (match?.foundServiceUuids ?? const []).isEmpty
                  ? '—'
                  : match!.foundServiceUuids.join(', '),
            ),
            _debugRow('Found beacon name', match?.beaconName ?? '—'),
            _debugRow(
              'UUID matched',
              (match?.uuidMatched ?? false) ? 'true' : 'false',
            ),
            _debugRow(
              'Name matched',
              (match?.nameMatched ?? false) ? 'true' : 'false',
            ),
            _debugRow('Final inRange', _inRange ? 'true' : 'false'),
            _debugRow(
              'Signal inRange (RSSI)',
              inRangeNow ? 'true' : 'false',
            ),
            _debugRow(
              'Last seen',
              _lastSeenInRangeAt?.toIso8601String() ?? '—',
            ),
          ],
        ),
      ),
    );
  }

  Widget _debugRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: StudentAttendanceUi.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
