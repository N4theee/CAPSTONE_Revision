import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../ui/exam_ui.dart';
import '../ui/responsive.dart';
import '../ui/student_attendance_ui.dart';

/// Student MCQ exam — answer and submit (proximity monitoring runs on parent screen).
class TakeExamScreen extends StatefulWidget {
  const TakeExamScreen({
    super.key,
    required this.session,
    required this.attempt,
    required this.offering,
  });

  final ExamSession session;
  final ExamAttempt attempt;
  final SubjectOffering offering;

  @override
  State<TakeExamScreen> createState() => _TakeExamScreenState();
}

class _TakeExamScreenState extends State<TakeExamScreen> {
  final _exam = ExamService();
  bool _loading = true;
  String? _error;
  List<ExamQuestion> _questions = [];
  final Map<String, String> _selectedByQuestion = {};
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fresh = await _exam.getExamAttemptById(widget.attempt.id);
      if (fresh != null && fresh.isTerminal) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error =
              'This exam was already submitted (${fresh.status}). Score: '
              '${fresh.percentageScore.toStringAsFixed(1)}%';
        });
        return;
      }

      final questions = await _exam.getExamQuestionsWithChoices(
        widget.session.id,
      );
      if (!mounted) return;
      if (questions.isEmpty) {
        setState(() {
          _questions = [];
          _loading = false;
          _error =
              'No questions for this exam yet. Ask your teacher to add questions.';
        });
        return;
      }
      setState(() {
        _questions = questions;
        _loading = false;
      });
    } on ExamServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  int get _unansweredCount =>
      _questions.where((q) => !_selectedByQuestion.containsKey(q.id)).length;

  Future<void> _confirmSubmit() async {
    if (!widget.attempt.canSubmitMcq) {
      _toast('This attempt can no longer be submitted.');
      return;
    }

    final unanswered = _unansweredCount;
    if (unanswered > 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: StudentAttendanceUi.surfaceElevated,
          title: Text(
            'Unanswered questions',
            style: ExamUi.titleMedium(ctx),
          ),
          content: Text(
            'You have $unanswered unanswered question(s). Submit anyway?',
            style: ExamUi.body(ctx),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Go back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Submit anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: StudentAttendanceUi.surfaceElevated,
          title: Text('Submit exam?', style: ExamUi.titleMedium(ctx)),
          content: Text(
            'You cannot change answers after submitting.',
            style: ExamUi.body(ctx),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Submit'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    await _submit();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final result = await _exam.submitExamAttempt(
        attemptId: widget.attempt.id,
        answersByQuestionId: Map.from(_selectedByQuestion),
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: StudentAttendanceUi.surfaceElevated,
          title: Text('Exam submitted', style: ExamUi.titleMedium(ctx)),
          content: Text(
            'Score: ${result.rawScore}/${result.totalPoints} '
            '(${result.percentageScore.toStringAsFixed(1)}%)\n'
            'Time: ${ExamService.formatCompletionTime(result.completionSeconds)}\n'
            'Submitted: ${ExamUi.formatExamDateTime(result.submittedAt)}',
            style: ExamUi.body(ctx),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ExamServiceException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast('Submit failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hPad = AppBreakpoints.horizontalPadding(context);
    final textTheme = Theme.of(context).textTheme;

    return Theme(
      data: StudentAttendanceUi.themeOverlay(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Take exam'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _questions.isEmpty
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(hPad),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              widget.session.examTitle,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${widget.session.examCode} • '
                              '${_questions.length} question(s)',
                              style: ExamUi.bodySecondary(context),
                            ),
                            if (widget.session.durationMinutes > 0)
                              Text(
                                'Suggested duration: ${widget.session.durationMinutes} min',
                                style: ExamUi.bodySecondary(context),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 100),
                          itemCount: _questions.length,
                          itemBuilder: (context, index) {
                            final q = _questions[index];
                            final selected = _selectedByQuestion[q.id];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Q${index + 1} (${q.points} pt${q.points == 1 ? '' : 's'})',
                                      style: textTheme.labelLarge?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: StudentAttendanceUi.mint,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      q.questionText,
                                      style: textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    ...q.choices.map((c) {
                                      final picked = selected == c.id;
                                      return ExamUi.mcqChoiceTile(
                                        context: context,
                                        letter: ExamUi.choiceLetterForOrder(
                                          c.choiceOrder,
                                        ),
                                        choiceText: c.choiceText,
                                        selected: picked,
                                        enabled: !_submitting,
                                        onTap: () {
                                          setState(() {
                                            _selectedByQuestion[q.id] = c.id;
                                          });
                                        },
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SafeArea(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_unansweredCount > 0)
                                Text(
                                  '$_unansweredCount unanswered',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 12,
                                  ),
                                ),
                              FilledButton(
                                onPressed:
                                    _submitting ? null : _confirmSubmit,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: _submitting
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Submit exam'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
