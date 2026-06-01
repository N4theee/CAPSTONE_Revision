import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../ui/exam_ui.dart';
import '../ui/responsive.dart';
import '../ui/teacher_attendance_ui.dart';

class ExamRankingsScreen extends StatefulWidget {
  const ExamRankingsScreen({
    super.key,
    required this.offering,
    required this.session,
  });

  final SubjectOffering offering;
  final ExamSession session;

  @override
  State<ExamRankingsScreen> createState() => _ExamRankingsScreenState();
}

class _ExamRankingsScreenState extends State<ExamRankingsScreen> {
  final _exam = ExamService();
  bool _loading = true;
  String? _error;
  List<ExamRankingRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _deleteExamSession() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TeacherAttendanceUi.surface,
        title: Text('Delete exam session?', style: ExamUi.titleMedium(ctx)),
        content: Text(
          'Are you sure you want to delete this exam? This will remove the exam '
          'session, questions, choices, attempts, answers, proximity logs, alerts, '
          'and rankings.',
          style: ExamUi.body(ctx),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: TeacherAttendanceUi.anomalyRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Exam Session'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _exam.deleteExamSessionCompletely(widget.session.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exam session deleted.')),
      );
      Navigator.pop(context, true);
    } on ExamServiceException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete exam: $e')),
      );
    }
  }

  Future<void> _clearAllRankingsForClass() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TeacherAttendanceUi.surface,
        title: Text('Clear all class rankings?', style: ExamUi.titleMedium(ctx)),
        content: Text(
          'Delete rankings for every exam session in ${widget.offering.subjectCode} '
          'Section ${widget.offering.section}? This cannot be undone.',
          style: ExamUi.body(ctx),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _exam.clearAllExamRankingsForOffering(widget.offering.id);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All exam rankings for this class cleared.')),
      );
    } on ExamServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not clear rankings: $e')),
      );
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _exam.getExamRankings(widget.session.id);
      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  @override
  Widget build(BuildContext context) {
    final hPad = AppBreakpoints.horizontalPadding(context);

    return Theme(
      data: TeacherAttendanceUi.themeOverlay(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Exam Rankings'),
          actions: [
            IconButton(
              tooltip: 'Delete exam session',
              onPressed: _loading ? null : _deleteExamSession,
              icon: const Icon(Icons.delete_forever_outlined),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) {
                if (v == 'clear_all') _clearAllRankingsForClass();
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'clear_all',
                  child: Text('Clear all rankings for this class'),
                ),
              ],
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
                widget.session.examTitle,
                style: ExamUi.titleMedium(context),
              ),
              Text(
                '${widget.session.examCode} • ${widget.offering.subjectCode}',
                style: ExamUi.bodySecondary(context),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: TeacherAttendanceUi.anomalyRed,
                    side: const BorderSide(color: TeacherAttendanceUi.anomalyRed),
                  ),
                  onPressed: _loading ? null : _deleteExamSession,
                  icon: const Icon(Icons.delete_forever_outlined, size: 18),
                  label: const Text('Delete Exam Session'),
                ),
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.redAccent))
              else if (_rows.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No rankings yet. Rankings are recorded when exam attempts are scored.',
                      style: TextStyle(color: TeacherAttendanceUi.textSecondary),
                    ),
                  ),
                )
              else
                ..._rows.asMap().entries.map((entry) {
                  final i = entry.key;
                  final r = entry.value;
                  final rank = r.rankNumber ?? (i + 1);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            TeacherAttendanceUi.accentPurple.withValues(
                          alpha: 0.25,
                        ),
                        child: Text(
                          '$rank',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(
                        r.studentName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      subtitle: Text(
                        'Score ${r.examScore.toStringAsFixed(1)}% • '
                        'Time ${ExamService.formatCompletionTime(r.completionSeconds)} • '
                        'Violations ${r.violationCount}'
                        '${r.remarks != null && r.remarks!.isNotEmpty ? '\n${r.remarks}' : ''}',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${r.examScore.toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: TeacherAttendanceUi.accentPurple,
                            ),
                          ),
                        ],
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
