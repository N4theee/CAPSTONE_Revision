import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
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

  Future<void> _clearRankings() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TeacherAttendanceUi.surface,
        title: const Text('Clear rankings'),
        content: Text(
          'Delete all ranking rows for "${widget.session.examTitle}" '
          '(${widget.session.examCode})? This cannot be undone.',
          style: const TextStyle(color: TeacherAttendanceUi.textOnField),
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
    );
    if (ok != true || !mounted) return;
    try {
      await _exam.clearExamRankingsForSession(widget.session.id);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rankings cleared.')),
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

  Future<void> _clearAllRankingsForClass() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TeacherAttendanceUi.surface,
        title: const Text('Clear all class rankings'),
        content: Text(
          'Delete rankings for every exam session in ${widget.offering.subjectCode} '
          'Section ${widget.offering.section}? This cannot be undone.',
          style: const TextStyle(color: TeacherAttendanceUi.textOnField),
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
              tooltip: 'Clear rankings for this exam',
              onPressed: _rows.isEmpty || _loading ? null : _clearRankings,
              icon: const Icon(Icons.delete_outline_rounded),
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
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              Text(
                '${widget.session.examCode} • ${widget.offering.subjectCode}',
                style: const TextStyle(
                  color: TeacherAttendanceUi.textSecondary,
                  fontSize: 13,
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
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
