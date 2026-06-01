import 'package:flutter/material.dart';

import '../services/exam_service.dart';
import '../services/supabase_service.dart';
import '../ui/exam_ui.dart';
import '../ui/responsive.dart';
import '../ui/student_attendance_ui.dart';

class ExamHistoryScreen extends StatefulWidget {
  const ExamHistoryScreen({
    super.key,
    required this.studentId,
    required this.offering,
  });

  final String studentId;
  final SubjectOffering offering;

  @override
  State<ExamHistoryScreen> createState() => _ExamHistoryScreenState();
}

class _ExamHistoryScreenState extends State<ExamHistoryScreen> {
  final _exam = ExamService();
  bool _loading = true;
  String? _error;
  List<StudentExamHistoryItem> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _clearHistory() async {
    final themed = StudentAttendanceUi.themeOverlay(Theme.of(context));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: themed,
        child: AlertDialog(
          backgroundColor: StudentAttendanceUi.surfaceElevated,
          title: const Text('Clear exam history'),
          content: Text(
            'Delete all your exam attempts for ${widget.offering.subjectCode} '
            '(Section ${widget.offering.section})? This cannot be undone.',
            style: const TextStyle(color: StudentAttendanceUi.textOnField),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _exam.clearStudentExamHistoryForOffering(
        studentId: widget.studentId,
        subjectOfferingId: widget.offering.id,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exam history cleared.')),
      );
    } on ExamServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not clear history: $e')),
      );
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _exam.getStudentExamHistory(
        widget.studentId,
        offeringId: widget.offering.id,
        subjectCode: widget.offering.subjectCode,
        subjectTitle: widget.offering.subjectTitle,
        section: widget.offering.section,
      );
      if (!mounted) return;
      setState(() {
        _history = rows;
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

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return StudentAttendanceUi.success;
      case 'auto_ended':
        return Colors.orangeAccent;
      case 'flagged':
        return Colors.redAccent;
      default:
        return StudentAttendanceUi.accentTeal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hPad = AppBreakpoints.horizontalPadding(context);

    return Theme(
      data: StudentAttendanceUi.themeOverlay(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Exam History'),
          actions: [
            IconButton(
              tooltip: 'Clear exam history',
              onPressed: _history.isEmpty || _loading ? null : _clearHistory,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 32),
            children: [
              Text(
                '${widget.offering.subjectCode} - ${widget.offering.subjectTitle}',
                style: ExamUi.titleMedium(context),
              ),
              Text(
                'Section ${widget.offering.section}',
                style: ExamUi.bodySecondary(context),
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.redAccent))
              else if (_history.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No exam attempts yet for this subject.',
                      style: TextStyle(color: StudentAttendanceUi.textSecondary),
                    ),
                  ),
                )
              else
                ..._history.map((item) {
                  final finished = item.finishedAt;
                  final scoreLine = item.percentageScore != null
                      ? 'Score: ${item.percentageScore!.toStringAsFixed(1)}%'
                      : null;
                  final timeLine = item.completionSeconds != null &&
                          item.completionSeconds! > 0
                      ? 'Time: ${ExamService.formatCompletionTime(item.completionSeconds)}'
                      : null;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      title: Text(
                        item.examTitle,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      subtitle: Text(
                        '${item.examCode}\n'
                        'Started ${ExamUi.formatExamDateTime(item.startedAt)}'
                        '${finished != null ? '\nSubmitted ${ExamUi.formatExamDateTime(finished)}' : ''}'
                        '${scoreLine != null ? '\n$scoreLine' : ''}'
                        '${timeLine != null ? ' • $timeLine' : ''}'
                        '\nViolations: ${item.violationCount}',
                        style: ExamUi.bodySecondary(context),
                      ),
                      isThreeLine: true,
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: _statusColor(item.status)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          item.status,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _statusColor(item.status),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}
