import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/exam_service.dart';
import '../services/supabase_service.dart';
import '../ui/responsive.dart';
import '../ui/teacher_attendance_ui.dart';

class CreateExamSessionScreen extends StatefulWidget {
  const CreateExamSessionScreen({
    super.key,
    required this.offering,
  });

  final SubjectOffering offering;

  @override
  State<CreateExamSessionScreen> createState() =>
      _CreateExamSessionScreenState();
}

class _CreateExamSessionScreenState extends State<CreateExamSessionScreen> {
  final _exam = ExamService();
  final _titleCtrl = TextEditingController();
  final _rssiCtrl = TextEditingController(
    text: '${AppConfig.rssiThreshold}',
  );
  final _graceCtrl = TextEditingController(text: '30');

  bool _saving = false;
  bool _useSchedule = false;
  DateTime? _startsAt;
  DateTime? _endsAt;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _rssiCtrl.dispose();
    _graceCtrl.dispose();
    super.dispose();
  }

  String get _bleUuid => widget.offering.beaconUuid.trim();

  Future<void> _pickDateTime({required bool isStart}) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: isStart ? (_startsAt ?? now) : (_endsAt ?? now),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: TeacherAttendanceUi.themeOverlay(Theme.of(ctx)),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        isStart ? (_startsAt ?? now) : (_endsAt ?? now),
      ),
      builder: (ctx, child) => Theme(
        data: TeacherAttendanceUi.themeOverlay(Theme.of(ctx)),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (time == null || !mounted) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startsAt = dt;
      } else {
        _endsAt = dt;
      }
    });
  }

  String _resolveStatus() {
    if (!_useSchedule || _startsAt == null) return 'active';
    if (_startsAt!.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return 'scheduled';
    }
    return 'active';
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _toast('Enter an exam title.');
      return;
    }
    if (_bleUuid.isEmpty) {
      _toast(
        'This class has no beacon UUID. Ask your administrator to set it on the subject offering.',
      );
      return;
    }

    final rssi = int.tryParse(_rssiCtrl.text.trim());
    final grace = int.tryParse(_graceCtrl.text.trim());
    if (rssi == null) {
      _toast('RSSI threshold must be a number.');
      return;
    }
    if (grace == null || grace < 0) {
      _toast('Grace period must be a non-negative number of seconds.');
      return;
    }
    if (_endsAt != null && _startsAt != null && !_endsAt!.isAfter(_startsAt!)) {
      _toast('End time must be after start time.');
      return;
    }

    setState(() => _saving = true);
    try {
      final status = _resolveStatus();
      final session = await _exam.createExamSession(
        subjectOfferingId: widget.offering.id,
        teacherId: widget.offering.teacherId,
        examTitle: title,
        bleUuid: _bleUuid,
        rssiThreshold: rssi,
        gracePeriodSeconds: grace,
        status: status,
        startsAt: _useSchedule ? _startsAt : null,
        endsAt: _endsAt,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      await _showCreatedDialog(session.examCode);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ExamServiceException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not create exam: $e');
    }
  }

  Future<void> _showCreatedDialog(String examCode) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: TeacherAttendanceUi.surface,
        title: const Text(
          'Exam created',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Share this code with students:',
              style: TextStyle(color: TeacherAttendanceUi.textSecondary),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                color: TeacherAttendanceUi.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: TeacherAttendanceUi.accentPurple),
              ),
              child: Text(
                examCode,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: examCode));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Exam code copied.')),
              );
            },
            child: const Text('Copy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final hPad = AppBreakpoints.horizontalPadding(context);

    return Theme(
      data: TeacherAttendanceUi.themeOverlay(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(title: const Text('Create Exam Session')),
        body: _saving
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 32),
                children: [
                  Text(
                    widget.offering.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Offering is pre-selected for this class',
                    style: TextStyle(
                      color: TeacherAttendanceUi.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _titleCtrl,
                    style: TeacherAttendanceUi.fieldTextStyle(),
                    cursorColor: TeacherAttendanceUi.accentPurple,
                    decoration: const InputDecoration(
                      labelText: 'Exam title',
                      hintText: 'Midterm — Room 201',
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Schedule start time'),
                    subtitle: const Text(
                      'If off, exam is active immediately when created',
                    ),
                    value: _useSchedule,
                    onChanged: (v) => setState(() {
                      _useSchedule = v;
                      if (!v) _startsAt = null;
                    }),
                  ),
                  if (_useSchedule)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Start time'),
                      subtitle: Text(
                        _startsAt == null
                            ? 'Not set'
                            : _startsAt!.toString().substring(0, 16),
                      ),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () => _pickDateTime(isStart: true),
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('End time (optional)'),
                    subtitle: Text(
                      _endsAt == null
                          ? 'Not set'
                          : _endsAt!.toString().substring(0, 16),
                    ),
                    trailing: const Icon(Icons.event_outlined),
                    onTap: () => _pickDateTime(isStart: false),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'BLE UUID (from subject offering)',
                    style: TextStyle(
                      color: TeacherAttendanceUi.textSecondary.withValues(
                        alpha: 0.9,
                      ),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _bleUuid.isEmpty ? 'Not configured' : _bleUuid,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _rssiCtrl,
                    style: TeacherAttendanceUi.fieldTextStyle(),
                    cursorColor: TeacherAttendanceUi.accentPurple,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'RSSI threshold',
                      helperText:
                          'Matches attendance default (${AppConfig.rssiThreshold}). '
                          'More negative = farther range.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _graceCtrl,
                    style: TeacherAttendanceUi.fieldTextStyle(),
                    cursorColor: TeacherAttendanceUi.accentPurple,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Grace period (seconds)',
                      helperText: 'Default 30',
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _save,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text('Create exam session'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
