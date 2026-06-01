import 'package:flutter/material.dart';

import '../services/exam_service.dart';
import '../services/supabase_service.dart';
import '../ui/exam_ui.dart';
import '../ui/responsive.dart';
import '../ui/teacher_attendance_ui.dart';
import 'create_exam_session_screen.dart';
import 'exam_rankings_screen.dart';
import 'teacher_exam_active_screen.dart';
import 'teacher_exam_monitoring_screen.dart';

/// Exam hub for one subject offering: create, view active, monitor, rankings.
class TeacherExamSessionsScreen extends StatefulWidget {
  const TeacherExamSessionsScreen({
    super.key,
    required this.teacherName,
    required this.offering,
  });

  final String teacherName;
  final SubjectOffering offering;

  @override
  State<TeacherExamSessionsScreen> createState() =>
      _TeacherExamSessionsScreenState();
}

class _TeacherExamSessionsScreenState extends State<TeacherExamSessionsScreen> {
  final _exam = ExamService();
  bool _loading = true;
  ExamSession? _activeOrScheduled;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final session =
        await _exam.getActiveExamSessionForOffering(widget.offering.id);
    if (!mounted) return;
    setState(() {
      _activeOrScheduled = session;
      _loading = false;
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openCreate() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateExamSessionScreen(
          offering: widget.offering,
        ),
      ),
    );
    if (created == true) await _load();
  }

  Future<void> _openActive() async {
    await _load();
    if (_activeOrScheduled == null) {
      _toast('No active or scheduled exam for this class.');
      return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeacherExamActiveScreen(
          offering: widget.offering,
          session: _activeOrScheduled!,
          onSessionChanged: _load,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openMonitor() async {
    await _load();
    final session = _activeOrScheduled;
    if (session == null) {
      _toast('No exam session to monitor.');
      return;
    }
    if (session.isTerminal) {
      _toast('This exam has ended or was cancelled.');
      return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeacherExamMonitoringScreen(
          offering: widget.offering,
          session: session,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openRankings() async {
    final sessions = await _exam.getExamSessionsForOffering(widget.offering.id);
    if (!mounted) return;
    if (sessions.isEmpty) {
      _toast('No exam sessions yet. Create one first.');
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
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExamRankingsScreen(
          offering: widget.offering,
          session: picked,
        ),
      ),
    );
    if (deleted == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final hPad = AppBreakpoints.horizontalPadding(context);
    final course =
        '${widget.offering.subjectCode} - ${widget.offering.subjectTitle}';

    return Theme(
      data: ExamUi.teacherThemeOverlay(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Exam Sessions'),
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 32),
            children: [
              Text(
                course,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              Text(
                'Section ${widget.offering.section}',
                style: const TextStyle(
                  color: TeacherAttendanceUi.textSecondary,
                  fontSize: 13,
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_activeOrScheduled != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.sensors_rounded,
                        color: TeacherAttendanceUi.accentPurple),
                    title: Text(
                      _activeOrScheduled!.examTitle,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${_activeOrScheduled!.examCode} • ${_activeOrScheduled!.status}',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _ExamActionTile(
                icon: Icons.add_circle_outline,
                title: 'Create Exam Session',
                subtitle: 'Set title, schedule, BLE, and proximity rules',
                onTap: _openCreate,
              ),
              _ExamActionTile(
                icon: Icons.visibility_outlined,
                title: 'View Active Exam Session',
                subtitle: 'Exam code, schedule, and session status',
                onTap: _openActive,
              ),
              _ExamActionTile(
                icon: Icons.monitor_heart_outlined,
                title: 'Monitor Exam',
                subtitle: 'Live students, proximity, and alerts',
                onTap: _openMonitor,
              ),
              _ExamActionTile(
                icon: Icons.leaderboard_outlined,
                title: 'View Exam Rankings',
                subtitle: 'Scores and ranks for completed exams',
                onTap: _openRankings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExamActionTile extends StatelessWidget {
  const _ExamActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: TeacherAttendanceUi.accentPurple),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: ExamUi.bodySecondary(context)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
