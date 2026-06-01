import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/supabase_service.dart';
import '../ui/exam_ui.dart';
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
  final _durationCtrl = TextEditingController(text: '60');
  final _rssiCtrl = TextEditingController(
    text: '${AppConfig.rssiThreshold}',
  );
  final _graceCtrl = TextEditingController(text: '30');

  bool _saving = false;
  bool _useSchedule = false;
  DateTime? _startsAt;
  DateTime? _endsAt;
  final List<ExamQuestionDraft> _questions = [ExamQuestionDraft()];
  final List<GlobalKey<_QuestionEditorCardState>> _questionEditorKeys = [
    GlobalKey<_QuestionEditorCardState>(),
  ];

  void _syncAllQuestionDrafts() {
    for (final key in _questionEditorKeys) {
      key.currentState?.syncToDraft();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _durationCtrl.dispose();
    _rssiCtrl.dispose();
    _graceCtrl.dispose();
    super.dispose();
  }

  void _addQuestion() {
    setState(() {
      _questions.add(ExamQuestionDraft());
      _questionEditorKeys.add(GlobalKey<_QuestionEditorCardState>());
    });
  }

  void _removeQuestion(int index) {
    if (_questions.length <= 1) {
      _toast('At least one question is required.');
      return;
    }
    setState(() {
      _questions.removeAt(index);
      _questionEditorKeys.removeAt(index);
    });
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
        data: ExamUi.teacherThemeOverlay(Theme.of(ctx)),
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
        data: ExamUi.teacherThemeOverlay(Theme.of(ctx)),
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

    final duration = int.tryParse(_durationCtrl.text.trim());
    if (duration == null || duration < 1) {
      _toast('Duration must be at least 1 minute.');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    _syncAllQuestionDrafts();

    try {
      ExamService.validateQuestionDrafts(_questions);
    } on ExamServiceException catch (e) {
      _toast(e.message);
      return;
    }

    setState(() => _saving = true);
    try {
      final status = _resolveStatus();
      final session = await _exam.createExamWithQuestions(
        subjectOfferingId: widget.offering.id,
        teacherId: widget.offering.teacherId,
        examTitle: title,
        bleUuid: _bleUuid,
        rssiThreshold: rssi,
        gracePeriodSeconds: grace,
        durationMinutes: duration,
        status: status,
        startsAt: _useSchedule ? _startsAt : null,
        endsAt: _endsAt,
        questions: _questions,
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
      data: ExamUi.teacherThemeOverlay(Theme.of(context)),
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: _durationCtrl,
                    style: TeacherAttendanceUi.fieldTextStyle(),
                    cursorColor: TeacherAttendanceUi.accentPurple,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Duration (minutes)',
                      helperText: 'Suggested time limit for students',
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Schedule start time',
                      style: ExamUi.titleMedium(context),
                    ),
                    subtitle: Text(
                      'If off, exam is active immediately when created',
                      style: ExamUi.bodySecondary(context),
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
                      title: Text('Start time', style: ExamUi.titleMedium(context)),
                      subtitle: Text(
                        _startsAt == null
                            ? 'Not set'
                            : ExamUi.formatExamDateTime(_startsAt),
                        style: ExamUi.bodySecondary(context),
                      ),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () => _pickDateTime(isStart: true),
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'End time (optional)',
                      style: ExamUi.titleMedium(context),
                    ),
                    subtitle: Text(
                      _endsAt == null
                          ? 'Not set'
                          : ExamUi.formatExamDateTime(_endsAt),
                      style: ExamUi.bodySecondary(context),
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
                  const Divider(height: 32),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Multiple-choice questions',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addQuestion,
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(_questions.length, (qi) {
                    final draft = _questions[qi];
                    return _QuestionEditorCard(
                      key: _questionEditorKeys[qi],
                      index: qi,
                      draft: draft,
                      onRemove: () => _removeQuestion(qi),
                      onChanged: () => setState(() {}),
                    );
                  }),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _save,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text('Create exam & questions'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _QuestionEditorCard extends StatefulWidget {
  const _QuestionEditorCard({
    super.key,
    required this.index,
    required this.draft,
    required this.onRemove,
    required this.onChanged,
  });

  final int index;
  final ExamQuestionDraft draft;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  State<_QuestionEditorCard> createState() => _QuestionEditorCardState();
}

class _QuestionEditorCardState extends State<_QuestionEditorCard> {
  static const _labels = ['A', 'B', 'C', 'D'];

  late final TextEditingController _questionCtrl;
  late final TextEditingController _pointsCtrl;
  late final List<TextEditingController> _choiceCtrls;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _questionCtrl = TextEditingController(text: d.questionText);
    _pointsCtrl = TextEditingController(text: '${d.points}');
    _choiceCtrls = List.generate(
      4,
      (i) => TextEditingController(text: d.choices[i].text),
    );
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    _pointsCtrl.dispose();
    for (final c in _choiceCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  /// Copies text field values into [widget.draft] (called before save validation).
  void syncToDraft() {
    final d = widget.draft;
    d.questionText = _questionCtrl.text;
    d.points = int.tryParse(_pointsCtrl.text.trim()) ?? 1;
    for (var i = 0; i < 4; i++) {
      d.choices[i].text = _choiceCtrls[i].text;
    }
    widget.onChanged();
  }

  void _syncDraft() => syncToDraft();

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Question ${widget.index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Remove question',
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ],
            ),
            TextField(
              controller: _questionCtrl,
              style: TeacherAttendanceUi.fieldTextStyle(),
              decoration: const InputDecoration(
                labelText: 'Question text',
                isDense: true,
              ),
              onChanged: (_) => _syncDraft(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Points', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: _pointsCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TeacherAttendanceUi.fieldTextStyle(),
                    decoration: const InputDecoration(isDense: true),
                    onChanged: (_) => _syncDraft(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Choices (select correct answer)',
              style: TextStyle(
                fontSize: 12,
                color: TeacherAttendanceUi.textSecondary,
              ),
            ),
            ...List.generate(4, (ci) {
              final isCorrect = draft.correctChoiceIndex == ci;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    tooltip: 'Mark as correct answer',
                    onPressed: () {
                      setState(() => draft.correctChoiceIndex = ci);
                      _syncDraft();
                    },
                    icon: Icon(
                      isCorrect ? Icons.check_circle : Icons.circle_outlined,
                      color: isCorrect
                          ? TeacherAttendanceUi.accentPurple
                          : TeacherAttendanceUi.textSecondary,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: TextField(
                        controller: _choiceCtrls[ci],
                        style: TeacherAttendanceUi.fieldTextStyle(),
                        decoration: InputDecoration(
                          labelText: _labels[ci],
                          isDense: true,
                        ),
                        onChanged: (_) => _syncDraft(),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}
