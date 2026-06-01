import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/ble_service.dart';
import '../services/exam_service.dart';
import '../services/supabase_service.dart';
import '../ui/responsive.dart';
import '../ui/student_attendance_ui.dart';
import 'student_exam_monitoring_screen.dart';

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

  bool _joining = false;
  String? _statusLine;
  StreamSubscription<bool>? _proximitySub;

  @override
  void dispose() {
    _proximitySub?.cancel();
    _ble.stopProximityScanning();
    _codeCtrl.dispose();
    super.dispose();
  }

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

  Future<void> _joinExam() async {
    final code = ExamService.normalizeExamCode(_codeCtrl.text);
    if (code.isEmpty) {
      _toast('Enter the exam code from your teacher.');
      return;
    }

    setState(() {
      _joining = true;
      _statusLine = 'Validating exam code…';
    });

    try {
      final session = await _exam.validateExamCode(
        examCode: code,
        subjectOfferingId: widget.offering.id,
      );

      final enrolled = await _exam.isStudentEnrolledInOffering(
        widget.studentId,
        widget.offering.id,
      );
      if (!enrolled) {
        throw ExamServiceException(
          'You are not enrolled in this subject offering.',
        );
      }

      var attempt = await _exam.getStudentExamAttempt(
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
        setState(() => _joining = false);
        _navigateToMonitor(session: session, attempt: attempt);
        return;
      }

      setState(() => _statusLine = 'Checking Bluetooth permissions…');
      final granted = await _ble.requestPermissions();
      if (!granted) {
        throw Exception('Bluetooth and location permissions are required.');
      }
      final btOn = await _ble.isBluetoothOn();
      if (!btOn) {
        throw Exception('Please turn on Bluetooth first.');
      }

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

      final rssi = ExamService.effectiveProximityRssi(session.rssiThreshold);

      setState(() => _statusLine = 'Scanning for teacher beacon…');
      await _ble.startProximityScanning(
        beaconUuid,
        beaconName: _beaconAdvertisedName(),
        rssiThreshold: rssi,
      );

      final inRange = await _waitForInRange(timeout: const Duration(seconds: 60));
      if (!inRange) {
        _ble.stopProximityScanning();
        throw Exception(
          'Could not detect the teacher beacon. Ask your teacher to open the active exam '
          '(BLE beacon must be on), move closer, and keep Bluetooth and Location enabled.',
        );
      }

      setState(() => _statusLine = 'Starting exam attempt…');
      attempt = await _exam.createExamAttempt(
        examSessionId: session.id,
        studentId: widget.studentId,
      );

      if (!mounted) return;
      setState(() => _joining = false);
      _navigateToMonitor(session: session, attempt: attempt);
    } on ExamServiceException catch (e) {
      _ble.stopProximityScanning();
      if (!mounted) return;
      setState(() {
        _joining = false;
        _statusLine = null;
      });
      _toast(e.message);
    } catch (e) {
      _ble.stopProximityScanning();
      if (!mounted) return;
      setState(() {
        _joining = false;
        _statusLine = null;
      });
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<bool> _waitForInRange({required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    var inStreak = _ble.lastProximity.inRange ? 1 : 0;
    if (inStreak >= AppConfig.examJoinInRangeStreakRequired) return true;

    _proximitySub?.cancel();
    _proximitySub = _ble.proximityStream.listen((inRange) {
      if (inRange) {
        inStreak++;
      } else {
        inStreak = 0;
      }
    });

    while (DateTime.now().isBefore(deadline)) {
      if (inStreak >= AppConfig.examJoinInRangeStreakRequired) {
        await _proximitySub?.cancel();
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    await _proximitySub?.cancel();
    return inStreak >= AppConfig.examJoinInRangeStreakRequired;
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

  @override
  Widget build(BuildContext context) {
    final hPad = AppBreakpoints.horizontalPadding(context);

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
            if (_joining) ...[
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
            ] else
              FilledButton(
                onPressed: _joinExam,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('Join exam'),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Your teacher must open the active exam on their phone (beacon on). '
              'You must be in BLE range before joining. Keep Bluetooth and Location on.',
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
