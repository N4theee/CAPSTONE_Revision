import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../services/ble_service.dart';
import '../services/supabase_service.dart';
import '../ui/exam_ui.dart';
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
  bool _sessionEnded = false;
  ExamSession? _liveSession;
  String _attemptStatus = 'in_progress';
  int _violationCount = 0;
  bool _submittedMcq = false;
  ExamAttempt? _submittedAttempt;
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
    _liveSession = widget.session;
    unawaited(_loadQuestionCount());
    unawaited(_initMonitoring());
  }

  String get _sessionStatus => _liveSession?.status ?? widget.session.status;

  String get _displayStatusLabel => ExamService.studentExamStatusLabel(
        attemptStatus: _attemptStatus,
        sessionStatus: _sessionStatus,
      );

  String get _appBarTitle {
    if (_sessionEnded || _liveSession?.isTerminal == true) {
      return 'Exam ended';
    }
    if (_attemptStatus == 'completed') return 'Exam submitted';
    return 'Exam in progress';
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

    _sessionPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
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
    if (_sessionEnded || _liveSession?.isTerminal == true) {
      _toast('This exam session has ended.');
      return;
    }
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
      try {
        final fresh = await _exam.getExamAttemptById(widget.attempt.id);
        if (!mounted) return;
        setState(() {
          _submittedMcq = true;
          if (fresh != null) {
            _attemptStatus = fresh.status;
            _submittedAttempt = fresh;
          }
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not refresh exam result: $e')),
        );
      }
    }
  }

  Future<void> _checkSessionAndAttempt() async {
    if (_ended) return;

    try {
      final sessionRow = await _exam.getExamSessionById(widget.session.id);
      if (sessionRow != null) {
        if (mounted) {
          setState(() => _liveSession = sessionRow);
        }
        if (sessionRow.isTerminal) {
          await _onSessionEnded(sessionRow);
          return;
        }
      }

      if (!_monitoring) return;

      final fresh = await _exam.getExamAttemptById(widget.attempt.id);
      if (fresh != null) {
        if (mounted) {
          setState(() {
            _attemptStatus = fresh.status;
            _violationCount = fresh.violationCount;
            if (fresh.status == 'completed') {
              _submittedMcq = true;
              _submittedAttempt = fresh;
            }
          });
        }
        if (fresh.status == 'auto_ended' || fresh.status == 'flagged') {
          await _finishMonitoring(
            status: fresh.status,
            message: 'Exam ended (${fresh.status}).',
          );
        }
      }
    } catch (e) {
      debugPrint('[exam] session/attempt poll: $e');
    }
  }

  Future<void> _onSessionEnded(ExamSession sessionRow) async {
    if (_ended) return;

    _monitoring = false;
    _sessionEnded = true;
    _sessionPollTimer?.cancel();
    _ble.stopExamProximityMonitoring();

    try {
      final fresh = await _exam.getExamAttemptById(widget.attempt.id);
      if (fresh != null && mounted) {
        setState(() {
          _attemptStatus = fresh.status;
          _violationCount = fresh.violationCount;
          if (fresh.status == 'completed') {
            _submittedMcq = true;
            _submittedAttempt = fresh;
          }
        });
      }
    } catch (e) {
      debugPrint('[exam] refresh attempt on session end: $e');
    }

    if (!mounted) return;
    setState(() {});

    final endedLabel = sessionRow.status == 'cancelled'
        ? 'cancelled'
        : 'ended by your teacher';
    await _finishMonitoring(
      status: _attemptStatus,
      message:
          'The exam session was $endedLabel. You can leave this screen.',
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
    if (_ended || _sessionEnded) return;
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
    if (_ended || _sessionEnded) return;
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
        content: Text(body, style: ExamUi.body(ctx)),
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
        data: ExamUi.studentThemeOverlay(Theme.of(context)),
        child: Scaffold(
          appBar: AppBar(
            title: Text(_appBarTitle),
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 32),
            children: [
              Text(
                widget.session.examTitle,
                style: ExamUi.titleMedium(context)?.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 6),
              Text(subjectLabel, style: ExamUi.bodySecondary(context)),
              Text(
                'Code ${widget.session.examCode} • Section ${widget.offering.section}',
                style: ExamUi.bodySecondary(context),
              ),
              if (_sessionEnded || _liveSession?.isTerminal == true) ...[
                Card(
                  color: Colors.orangeAccent.withValues(alpha: 0.12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.event_busy_rounded,
                          color: Colors.orangeAccent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Session $_sessionStatus. '
                            'Status: $_displayStatusLabel',
                            style: ExamUi.body(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        _sessionEnded
                            ? Icons.event_busy_rounded
                            : (_inRange
                                ? Icons.sensors_rounded
                                : Icons.sensors_off_rounded),
                        size: 48,
                        color: _sessionEnded
                            ? Colors.orangeAccent
                            : statusColor,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _sessionEnded ? _displayStatusLabel : statusLabel,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: _sessionEnded
                              ? Colors.orangeAccent
                              : statusColor,
                        ),
                      ),
                      if (_rssi != null && !_sessionEnded) ...[
                        const SizedBox(height: 8),
                        Text(
                          'RSSI $_rssi (threshold $_rssiThreshold)',
                          style: ExamUi.bodySecondary(context),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Exam: $_displayStatusLabel • Violations: $_violationCount',
                        style: ExamUi.bodySecondary(context),
                      ),
                      if (!_sessionEnded) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Grace period: ${widget.session.gracePeriodSeconds}s out of range before auto-end',
                          textAlign: TextAlign.center,
                          style: ExamUi.bodySecondary(context),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_questionCount != null && _questionCount! > 0) ...[
                if (_submittedMcq)
                  Card(
                    color: StudentAttendanceUi.success.withValues(alpha: 0.12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Exam answers submitted. Proximity monitoring continues until the session ends.',
                            style: ExamUi.body(context),
                          ),
                          if (_submittedAttempt != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Score: ${_submittedAttempt!.percentageScore.toStringAsFixed(1)}% • '
                              'Time: ${ExamService.formatCompletionTime(_submittedAttempt!.completionSeconds)}',
                              style: ExamUi.bodySecondary(context),
                            ),
                            Text(
                              'Submitted: ${ExamUi.formatExamDateTime(
                                ExamService.resolveAttemptSubmittedAt(
                                  submittedAt: _submittedAttempt!.submittedAt,
                                  endedAt: _submittedAttempt!.endedAt,
                                ),
                              )}',
                              style: ExamUi.bodySecondary(context),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else if (!_sessionEnded)
                  FilledButton.icon(
                    onPressed: _openTakeExam,
                    icon: const Icon(Icons.edit_note_rounded),
                    label: Text(
                      'Answer exam ($_questionCount questions)',
                    ),
                  ),
                const SizedBox(height: 12),
              ] else if (_questionCount == 0 && !_sessionEnded)
                Text(
                  'Waiting for exam questions from your teacher.',
                  textAlign: TextAlign.center,
                  style: ExamUi.bodySecondary(context),
                ),
              if (!_sessionEnded)
                Text(
                  'Stay near the teacher device. Brief signal drops are ignored for '
                  '${AppConfig.examProximitySmoothingSeconds}s. '
                  'Grace period: ${widget.session.gracePeriodSeconds}s out of range before auto-end.',
                  textAlign: TextAlign.center,
                  style: ExamUi.bodySecondary(context)?.copyWith(height: 1.35),
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
            Text(
              'BLE debug (dev)',
              style: ExamUi.labelOnCard(context)?.copyWith(
                    fontWeight: FontWeight.w600,
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
              style: ExamUi.bodySecondary(context)?.copyWith(fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: ExamUi.bodySecondary(context)?.copyWith(
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
