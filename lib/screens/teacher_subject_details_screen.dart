import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../ui/adaptive_layout.dart';
import '../ui/exam_ui.dart';
import '../ui/teacher_attendance_ui.dart';
import 'exam_rankings_screen.dart';
import 'teacher_exam_sessions_screen.dart';
import 'teacher_history_screen.dart';
import 'teacher_screen.dart';

class TeacherSubjectDetailsScreen extends StatefulWidget {
  const TeacherSubjectDetailsScreen({
    super.key,
    required this.teacherName,
    required this.offering,
  });
  final String teacherName;
  final SubjectOffering offering;
  @override
  State<TeacherSubjectDetailsScreen> createState() =>
      _TeacherSubjectDetailsScreenState();
}

class _TeacherSubjectDetailsScreenState
    extends State<TeacherSubjectDetailsScreen> {
  final _examService = ExamService();
  final _db = SupabaseService();
  bool _loadingRankings = false;
  bool _loadingPreview = true;
  bool _loadingRoster = true;
  bool _rosterFailed = false;
  bool _rankingsFailed = false;
  List<ExamRankingRow> _allRankings = [];
  ExamSession? _latestSession;
  List<ExamSession> _allSessions = [];
  List<Map<String, dynamic>> _enrolledStudents = [];
  DateTime? _updatedAt;
  final _searchController = TextEditingController();
  final _classRecordSearchController = TextEditingController();
  int _rankingRequest = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_redraw);
    _classRecordSearchController.addListener(_redraw);
    _loadPreview();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    _classRecordSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadRoster() async {
    setState(() {
      _loadingRoster = true;
      _rosterFailed = false;
    });
    try {
      final rows = await _db.getEnrolledStudents(widget.offering.id);
      rows.sort(
        (a, b) => a['full_name'].toString().toLowerCase().compareTo(
          b['full_name'].toString().toLowerCase(),
        ),
      );
      if (mounted) {
        setState(() {
          _enrolledStudents = rows;
          _loadingRoster = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingRoster = false;
          _rosterFailed = true;
        });
      }
    }
  }

  Future<void> _loadPreview() async {
    await _loadRoster();
    if (!mounted) return;
    setState(() {
      _loadingPreview = true;
      _rankingsFailed = false;
    });
    try {
      final sessions = await _examService.getExamSessionsForOffering(
        widget.offering.id,
      );
      if (!mounted) return;
      _allSessions = sessions;
      final previous = sessions.where((s) => s.id == _latestSession?.id);
      final terminal = sessions.where((s) => s.isTerminal);
      final selected = previous.isNotEmpty
          ? previous.first
          : terminal.isNotEmpty
          ? terminal.first
          : sessions.firstOrNull;
      if (selected != null) {
        await _fetchRankingsForSession(selected);
      } else {
        setState(() {
          _latestSession = null;
          _allRankings = [];
          _loadingPreview = false;
        });
      }
      if (mounted) setState(() => _updatedAt = DateTime.now());
    } catch (_) {
      if (mounted) {
        setState(() {
          _rankingsFailed = true;
          _loadingPreview = false;
        });
      }
    }
  }

  Future<void> _fetchRankingsForSession(ExamSession session) async {
    final request = ++_rankingRequest;
    setState(() {
      _latestSession = session;
      _loadingPreview = true;
      _rankingsFailed = false;
    });
    try {
      final rankings = await _examService.getExamRankings(session.id);
      if (mounted && request == _rankingRequest) {
        setState(() {
          _allRankings = rankings;
          _loadingPreview = false;
        });
      }
    } catch (_) {
      if (mounted && request == _rankingRequest) {
        setState(() {
          _rankingsFailed = true;
          _loadingPreview = false;
        });
      }
    }
  }

  void _toast(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    if (mounted) await _loadPreview();
  }

  Future<void> _openRankings() async {
    setState(() => _loadingRankings = true);
    try {
      final sessions = await _examService.getExamSessionsForOffering(
        widget.offering.id,
      );
      if (!mounted) return;
      if (sessions.isEmpty) {
        _toast('No exam sessions yet. Create one in Exam Sessions first.');
        return;
      }
      ExamSession picked = sessions.first;
      if (sessions.length > 1) {
        final choice = await showModalBottomSheet<ExamSession>(
          context: context,
          backgroundColor: TeacherAttendanceUi.surface,
          builder: (ctx) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Select exam for rankings',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                ...sessions.map(
                  (s) => ListTile(
                    title: Text(
                      s.examTitle,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '${s.examCode} • ${s.status}',
                      style: const TextStyle(
                        color: TeacherAttendanceUi.textSecondary,
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, s),
                  ),
                ),
              ],
            ),
          ),
        );
        if (choice == null || !mounted) return;
        picked = choice;
      }
      if (!mounted) return;
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ExamRankingsScreen(offering: widget.offering, session: picked),
        ),
      );
      if (mounted) {
        // Refresh the dashboard if an exam was deleted or cleared
        await _loadPreview();
      }
    } finally {
      if (mounted) setState(() => _loadingRankings = false);
    }
  }

  Widget _search(TextEditingController controller, String label) => TextField(
    controller: controller,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.search),
      suffixIcon: controller.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Clear search',
              onPressed: controller.clear,
              icon: const Icon(Icons.close),
            ),
    ),
  );

  Widget _roster(BuildContext context) {
    final query = _classRecordSearchController.text.trim().toLowerCase();
    final rows = _enrolledStudents
        .where(
          (s) => '${s['full_name']} ${s['student_number']}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdaptiveHeading(
              title: Text(
                'Class roster',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              action: Text('${_enrolledStudents.length} enrolled'),
            ),
            const SizedBox(height: 16),
            _search(
              _classRecordSearchController,
              'Search name or student number',
            ),
            const SizedBox(height: 12),
            if (_loadingRoster)
              const Center(child: CircularProgressIndicator())
            else if (_rosterFailed)
              LoadError(
                message: 'Could not load the class roster.',
                onRetry: _loadRoster,
              )
            else if (_enrolledStudents.isEmpty)
              const Text('No students are enrolled in this class yet.')
            else if (rows.isEmpty)
              const Text('No students match your search.')
            else
              for (final student in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${student['full_name']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text('Student number: ${student['student_number']}'),
                      const Divider(),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _rankings(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final rows = query.isEmpty
        ? _allRankings.take(5).toList()
        : _allRankings
              .where((r) => r.studentName.toLowerCase().contains(query))
              .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Top rankings', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (_allSessions.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                key: ValueKey(_latestSession?.id),
                initialValue: _latestSession?.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Exam'),
                items: _allSessions
                    .map(
                      (s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(
                          s.examTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (id) {
                  if (id != null) {
                    _fetchRankingsForSession(
                      _allSessions.firstWhere((s) => s.id == id),
                    );
                  }
                },
              ),
              if (_latestSession != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(_latestSession!.examTitle),
                ),
              _search(_searchController, 'Search student name'),
              const SizedBox(height: 12),
            ],
            if (_loadingPreview)
              const Center(child: CircularProgressIndicator())
            else if (_rankingsFailed)
              LoadError(
                message: 'Could not load exam rankings.',
                onRetry: _loadPreview,
              )
            else if (_allSessions.isEmpty)
              const Text('No exams yet. Open Exam sessions to create one.')
            else if (_allRankings.isEmpty)
              const Text('No completed results for this exam yet.')
            else if (rows.isEmpty)
              const Text('No students match your search.')
            else
              for (final row in rows)
                DetailCard(
                  title:
                      '${row.rankNumber ?? (_allRankings.indexOf(row) + 1)}. ${row.studentName}',
                  details: ['Score: ${row.examScore.toStringAsFixed(1)}%'],
                ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadingRankings ? null : _openRankings,
              icon: const Icon(Icons.leaderboard_outlined),
              label: Text(
                _loadingRankings ? 'Loading rankings…' : 'View full rankings',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: ExamUi.teacherThemeOverlay(Theme.of(context)),
    child: Builder(
      builder: (context) => SubjectLayout(
        title:
            '${widget.offering.subjectCode} — ${widget.offering.subjectTitle}',
        subtitle: '${widget.teacherName}\nSection ${widget.offering.section}',
        onRefresh: _loadPreview,
        actions: [
          SubjectAction(
            'Attendance sessions',
            Icons.fact_check_outlined,
            () => _open(
              TeacherScreen(
                teacherName: widget.teacherName,
                offering: widget.offering,
              ),
            ),
          ),
          SubjectAction(
            'Exam sessions',
            Icons.quiz_outlined,
            () => _open(
              TeacherExamSessionsScreen(
                teacherName: widget.teacherName,
                offering: widget.offering,
              ),
            ),
          ),
          SubjectAction(
            'Session history',
            Icons.history,
            () => _open(
              TeacherHistoryScreen(teacherId: widget.offering.teacherId),
            ),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, box) {
                if (box.maxWidth >= 800 &&
                    MediaQuery.textScalerOf(context).scale(1) <= 1.3) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _roster(context)),
                      const SizedBox(width: 16),
                      Expanded(child: _rankings(context)),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _roster(context),
                    const SizedBox(height: 16),
                    _rankings(context),
                  ],
                );
              },
            ),
            if (_updatedAt != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'Last updated: ${ExamUi.formatExamDateTime(_updatedAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
