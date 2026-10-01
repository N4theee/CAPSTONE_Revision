import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../ui/exam_ui.dart';
import '../ui/adaptive_layout.dart';
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
    final themed = ExamUi.studentThemeOverlay(Theme.of(context));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Exam history cleared.')));
    } on ExamServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not clear history: $e')));
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

  Color _statusColor(String statusKey) {
    switch (statusKey) {
      case 'completed':
        return StudentAttendanceUi.success;
      case 'auto_ended':
      case 'session_ended':
        return Colors.orangeAccent;
      case 'flagged':
      case 'cancelled':
        return Colors.redAccent;
      default:
        return StudentAttendanceUi.accentTeal;
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: ExamUi.studentThemeOverlay(Theme.of(context)),
    child: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: const Text('Exam history'),
          actions: [
            IconButton(
              tooltip: 'Clear exam history',
              onPressed: _history.isEmpty || _loading ? null : _clearHistory,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: ResponsivePage(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${widget.offering.subjectCode} — ${widget.offering.subjectTitle}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text('Section ${widget.offering.section}'),
                const SizedBox(height: 20),
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_error != null)
                  LoadError(
                    message: 'Could not load your exam history.',
                    onRetry: _load,
                  )
                else if (_history.isEmpty)
                  const DetailCard(
                    title: 'No exam attempts yet',
                    details: ['You haven’t taken any exams for this subject.'],
                  )
                else
                  for (final item in _history)
                    DetailCard(
                      title: item.examTitle,
                      badge: StatusBadge(
                        label: item.displayStatus,
                        color: _statusColor(
                          ExamService.studentExamStatusKey(
                            attemptStatus: item.status,
                            sessionStatus: item.sessionStatus,
                          ),
                        ),
                      ),
                      details: [
                        'Exam code: ${item.examCode}',
                        'Started: ${ExamUi.formatExamDateTime(item.startedAt)}',
                        if (item.finishedAt != null)
                          '${item.status == 'completed' ? 'Submitted' : 'Ended'}: ${ExamUi.formatExamDateTime(item.finishedAt)}',
                        if (item.status == 'completed' &&
                            item.percentageScore != null)
                          'Score: ${item.percentageScore!.toStringAsFixed(1)}%'
                        else
                          'Not submitted',
                        if (item.status == 'completed' &&
                            item.completionSeconds != null)
                          'Completion time: ${ExamService.formatCompletionTime(item.completionSeconds)}',
                        'Proximity violations: ${item.violationCount}',
                      ],
                    ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
