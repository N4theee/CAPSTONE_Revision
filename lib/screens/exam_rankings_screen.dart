import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../ui/exam_ui.dart';
import '../ui/adaptive_layout.dart';
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _deleteExamSession() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TeacherAttendanceUi.surface,
        title: const Text(
          'Delete exam session?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Delete ${widget.session.examTitle} (${widget.session.examCode})? This will remove the exam '
          'session, questions, choices, attempts, answers, proximity logs, alerts, '
          'and rankings.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Exam session deleted.')));
      Navigator.pop(context, true);
    } on ExamServiceException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete exam: $e')));
    }
  }

  Future<void> _clearAllRankingsForClass() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TeacherAttendanceUi.surface,
        title: const Text(
          'Clear all class rankings?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Delete rankings for every exam session in ${widget.offering.subjectCode} '
          'Section ${widget.offering.section}? This cannot be undone.',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
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
        const SnackBar(
          content: Text('All exam rankings for this class cleared.'),
        ),
      );
    } on ExamServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not clear rankings: $e')));
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
  Widget build(BuildContext context) => Theme(
    data: ExamUi.teacherThemeOverlay(Theme.of(context)),
    child: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: const Text('Exam rankings'),
          actions: [
            IconButton(
              tooltip: 'Refresh rankings',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
            PopupMenuButton<String>(
              tooltip: 'Ranking actions',
              onSelected: (value) {
                if (value == 'clear_all') _clearAllRankingsForClass();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'clear_all',
                  enabled: !_loading,
                  child: const Text('Clear all class rankings'),
                ),
              ],
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
                  widget.session.examTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.session.examCode} · ${widget.offering.subjectCode} · Section ${widget.offering.section}',
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search student name',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: _searchController.clear,
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_error != null)
                  LoadError(message: 'Could not load rankings.', onRetry: _load)
                else if (_rows.isEmpty)
                  const DetailCard(
                    title: 'No results yet',
                    details: [
                      'Rankings appear after students submit their exams.',
                    ],
                  )
                else
                  Builder(
                    builder: (context) {
                      final filtered = _rows
                          .where(
                            (r) => r.studentName.toLowerCase().contains(
                              _searchQuery.trim().toLowerCase(),
                            ),
                          )
                          .toList();
                      if (filtered.isEmpty) {
                        return const Text('No students match your search.');
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final row in filtered)
                            DetailCard(
                              title:
                                  '${row.rankNumber ?? (_rows.indexOf(row) + 1)}. ${row.studentName}',
                              badge: StatusBadge(
                                label: '${row.examScore.toStringAsFixed(1)}%',
                                color: TeacherAttendanceUi.accentPurple,
                              ),
                              details: [
                                'Completion time: ${ExamService.formatCompletionTime(row.completionSeconds)}',
                                'Proximity violations: ${row.violationCount}',
                                if (row.startedAt != null)
                                  'Started: ${ExamUi.formatExamDateTime(row.startedAt)}',
                                if (row.finishedAt != null)
                                  'Submitted: ${ExamUi.formatExamDateTime(row.finishedAt)}',
                                if (row.remarks?.isNotEmpty == true)
                                  row.remarks!,
                              ],
                            ),
                        ],
                      );
                    },
                  ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 12),
                const Text(
                  'Permanent deletion removes this exam and its related records.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _deleteExamSession,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: TeacherAttendanceUi.anomalyRed,
                  ),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Delete exam session'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
