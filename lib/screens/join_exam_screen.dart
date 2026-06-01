import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/ble_service.dart';
import '../services/exam_service.dart';
import '../services/supabase_service.dart';
import '../ui/responsive.dart';
import '../ui/student_attendance_ui.dart';
import 'student_exam_monitoring_screen.dart';

enum _JoinLoadState {
  idle,
  validatingCode,
  checkingProximity,
  proximityFailed,
  proximityPassed,
}

class JoinExamScreen extends StatefulWidget {
  const JoinExamScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.offering,
  });

  final String studentId;
  final String studentName;
  final SubjectOffering offering;

  @override
  State<JoinExamScreen> createState() => _JoinExamScreenState();
}

class _JoinExamScreenState extends State<JoinExamScreen> {
  final _exam = ExamService();
  final _ble = BleService();
  final _codeCtrl = TextEditingController();

  _JoinLoadState _loadState = _JoinLoadState.idle;
  String? _statusLine;
  ExamSession? _validatedSession;
  JoinProximityDebug _proximityDebug = const JoinProximityDebug();

  @override
  void dispose() {
    _ble.stopJoinProximityScan();
    _codeCtrl.dispose();
    super.dispose();
  }

  bool get _busy =>
      _loadState == _JoinLoadState.validatingCode ||
      _loadState == _JoinLoadState.checkingProximity;

  String _beaconAdvertisedName() {
    final configured = widget.offering.beaconName.trim();
    if (configured.isNotEmpty) return configured;
    final code = widget.offering.subjectCode.trim();
    if (code.isNotEmpty) return code;
    return AppConfig.defaultBeaconName;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<ExamSession> validateExamCode() async {
    final code = ExamService.normalizeExamCode(_codeCtrl.text);
    if (code.isEmpty) {
      throw ExamServiceException('Enter the exam code from your teacher.');
    }
    return _exam.validateExamCode(
      examCode: code,
      subjectOfferingId: widget.offering.id,
    );
  }

  Future<void> _ensureEnrollmentAndAttemptRules(ExamSession session) async {
    final enrolled = await _exam.isStudentEnrolledInOffering(
      widget.studentId,
      widget.offering.id,
    );
    if (!enrolled) {
      throw ExamServiceException(
        'You are not enrolled in this subject offering.',
      );
    }

    final attempt = await _exam.getStudentExamAttempt(
      examSessionId: session.id,
      studentId: widget.studentId,
    );
    if (attempt != null && attempt.isTerminal) {
      throw ExamServiceException(
        'You already finished this exam (${attempt.status}).',
      );
    }

    if (attempt != null && attempt.status == 'in_progress') {
      if (!mounted) return;
      setState(() => _loadState = _JoinLoadState.idle);
      _navigateToMonitor(session: session, attempt: attempt);
      throw _ResumeExistingAttempt();
    }
  }

  Future<bool> checkTeacherProximityWithTimeout(ExamSession session) async {
    final beaconUuid = ExamService.resolveBeaconUuid(
      session: session,
      offeringBeaconUuid: widget.offering.beaconUuid,
    );
    if (beaconUuid.isEmpty) {
      throw Exception(
        'This class has no BLE beacon UUID. Ask your teacher to start the exam '
        'from a device with Bluetooth advertising enabled.',
      );
    }

    final permissionIssue = await _ble.examBlePermissionIssue();
    if (permissionIssue != null) {
      throw Exception(permissionIssue);
    }
    final btOn = await _ble.isBluetoothOn();
    if (!btOn) {
      throw Exception('Please turn on Bluetooth first.');
    }

    final rssi = ExamService.examJoinProximityRssi(session.rssiThreshold);
    final timeout = Duration(seconds: AppConfig.examJoinScanTimeoutSeconds);

    final result = await _ble.scanForExamBeacon(
      expectedBeaconUuid: beaconUuid,
      beaconName: _beaconAdvertisedName(),
      rssiThreshold: rssi,
      timeout: timeout,
      onProgress: (debug) {
        if (!mounted) return;
        setState(() => _proximityDebug = debug);
      },
    );

    if (!mounted) return false;
    setState(() => _proximityDebug = result.debug);
    return result.success;
  }

  Future<void> proceedToExam(ExamSession session) async {
    final existing = await _exam.getStudentExamAttempt(
      examSessionId: session.id,
      studentId: widget.studentId,
    );
    if (existing != null && existing.status == 'in_progress') {
      if (!mounted) return;
      setState(() {
        _loadState = _JoinLoadState.proximityPassed;
        _statusLine = null;
      });
      _navigateToMonitor(session: session, attempt: existing);
      return;
    }

    final attempt = await _exam.createExamAttempt(
      examSessionId: session.id,
      studentId: widget.studentId,
    );
    if (!mounted) return;
    setState(() {
      _loadState = _JoinLoadState.proximityPassed;
      _statusLine = null;
    });
    _navigateToMonitor(session: session, attempt: attempt);
  }

  void showRetryState() {
    if (!mounted) return;
    setState(() {
      _loadState = _JoinLoadState.proximityFailed;
      _statusLine =
          'Teacher device not detected. Please stay near the teacher and tap Retry.';
    });
  }

  Future<void> _joinExam() async {
    if (_busy) return;

    setState(() {
      _loadState = _JoinLoadState.validatingCode;
      _statusLine = 'Validating exam code…';
      _proximityDebug = const JoinProximityDebug();
      _validatedSession = null;
    });

    try {
      final session = await validateExamCode();
      await _ensureEnrollmentAndAttemptRules(session);

      if (!mounted) return;
      setState(() {
        _validatedSession = session;
        _loadState = _JoinLoadState.checkingProximity;
        _statusLine =
            'Exam code accepted. Checking teacher proximity…';
      });

      final inRange = await checkTeacherProximityWithTimeout(session);
      if (!mounted) return;

      if (!inRange) {
        showRetryState();
        return;
      }

      await proceedToExam(session);
    } on _ResumeExistingAttempt {
      // Navigation already handled.
    } on ExamServiceException catch (e) {
      _ble.stopJoinProximityScan();
      if (!mounted) return;
      setState(() {
        _loadState = _JoinLoadState.idle;
        _statusLine = null;
      });
      _toast(e.message);
    } catch (e) {
      _ble.stopJoinProximityScan();
      if (!mounted) return;
      setState(() {
        _loadState = _JoinLoadState.idle;
        _statusLine = null;
      });
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _retryProximityCheck() async {
    final session = _validatedSession;
    if (session == null || _busy) return;

    setState(() {
      _loadState = _JoinLoadState.checkingProximity;
      _statusLine = 'Checking teacher proximity…';
      _proximityDebug = const JoinProximityDebug();
    });

    try {
      final inRange = await checkTeacherProximityWithTimeout(session);
      if (!mounted) return;

      if (!inRange) {
        showRetryState();
        return;
      }

      await proceedToExam(session);
    } catch (e) {
      _ble.stopJoinProximityScan();
      if (!mounted) return;
      setState(() {
        _loadState = _JoinLoadState.proximityFailed;
        _statusLine =
            'Teacher device not detected. Please stay near the teacher and tap Retry.';
      });
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _navigateToMonitor({
    required ExamSession session,
    required ExamAttempt attempt,
  }) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => StudentExamMonitoringScreen(
          studentId: widget.studentId,
          studentName: widget.studentName,
          offering: widget.offering,
          session: session,
          attempt: attempt,
        ),
      ),
    );
  }

  Widget _debugPanel() {
    if (!AppConfig.showExamBleDebugPanel) return const SizedBox.shrink();
    if (_loadState != _JoinLoadState.checkingProximity &&
        _loadState != _JoinLoadState.proximityFailed) {
      return const SizedBox.shrink();
    }

    final d = _proximityDebug;
    final session = _validatedSession;
    final expectedUuid = session != null
        ? ExamService.resolveBeaconUuid(
            session: session,
            offeringBeaconUuid: widget.offering.beaconUuid,
          )
        : (d.expectedUuid ?? '—');
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
            _debugRow('Expected UUID', expectedUuid),
            _debugRow(
              'Expected beacon name',
              d.expectedBeaconName ?? _beaconAdvertisedName(),
            ),
            _debugRow(
              'Current threshold',
              d.currentThreshold?.toString() ??
                  ExamService.examJoinProximityRssi(
                    session?.rssiThreshold ?? AppConfig.examJoinRssiThreshold,
                  ).toString(),
            ),
            _debugRow('Last detected RSSI', d.rssi?.toString() ?? '—'),
            _debugRow(
              'Found UUIDs',
              d.foundServiceUuids.isEmpty
                  ? '—'
                  : d.foundServiceUuids.join(', '),
            ),
            _debugRow('Found beacon name', d.detectedBeaconName ?? '—'),
            _debugRow('UUID matched', d.uuidMatched ? 'true' : 'false'),
            _debugRow('Name matched', d.nameMatched ? 'true' : 'false'),
            _debugRow('Final inRange', d.finalInRange ? 'true' : 'false'),
            _debugRow(
              'Last seen',
              d.lastSeenAt?.toIso8601String() ?? '—',
            ),
            _debugRow('Scanning', d.scanning ? 'yes' : 'no'),
            _debugRow('Elapsed', '${d.elapsed.inMilliseconds} ms'),
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
            width: 110,
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

  @override
  Widget build(BuildContext context) {
    final hPad = AppBreakpoints.horizontalPadding(context);
    final showRetry = _loadState == _JoinLoadState.proximityFailed;

    return Theme(
      data: StudentAttendanceUi.themeOverlay(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(title: const Text('Join Exam')),
        body: ListView(
          padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 32),
          children: [
            Text(
              widget.offering.label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 4),
            const Text(
              'Exam must be active for this class',
              style: TextStyle(
                color: StudentAttendanceUi.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _codeCtrl,
              enabled: !_busy,
              style: StudentAttendanceUi.fieldTextStyle(),
              cursorColor: StudentAttendanceUi.mint,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Exam code',
                hintText: 'EXM-7K92Q',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
            ),
            const SizedBox(height: 20),
            if (_busy) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 12),
              if (_statusLine != null)
                Text(
                  _statusLine!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: StudentAttendanceUi.textSecondary,
                  ),
                ),
            ] else if (showRetry) ...[
              Icon(
                Icons.bluetooth_searching,
                size: 48,
                color: StudentAttendanceUi.textOnField.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 12),
              Text(
                _statusLine ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: StudentAttendanceUi.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _retryProximityCheck,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('Retry Proximity Check'),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  setState(() {
                    _loadState = _JoinLoadState.idle;
                    _statusLine = null;
                    _validatedSession = null;
                  });
                },
                child: const Text('Change exam code'),
              ),
            ] else
              FilledButton(
                onPressed: _joinExam,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('Join exam'),
                ),
              ),
            const SizedBox(height: 12),
            _debugPanel(),
            const SizedBox(height: 8),
            Text(
              'Your teacher must open the active exam on their phone (beacon on). '
              'After the code is accepted, we scan for up to '
              '${AppConfig.examJoinScanTimeoutSeconds} seconds. Keep Bluetooth and Location on.',
              style: TextStyle(
                color: StudentAttendanceUi.textOnField,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sentinel: student already has an in-progress attempt; navigated away.
class _ResumeExistingAttempt implements Exception {}
