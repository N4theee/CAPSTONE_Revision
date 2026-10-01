import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../ui/adaptive_layout.dart';
import '../ui/exam_ui.dart';
import 'exam_history_screen.dart';
import 'join_exam_screen.dart';
import 'student_history_screen.dart';
import 'student_screen.dart';

class StudentSubjectDetailsScreen extends StatefulWidget {
  const StudentSubjectDetailsScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.offering,
  });
  final String studentId;
  final String studentName;
  final SubjectOffering offering;
  @override
  State<StudentSubjectDetailsScreen> createState() =>
      _StudentSubjectDetailsScreenState();
}

class _StudentSubjectDetailsScreenState
    extends State<StudentSubjectDetailsScreen> {
  String? _studentNumber;
  bool _loading = true;
  bool _failed = false;
  DateTime? _updatedAt;
  List<StudentExamHistoryItem> _history = [];
  int _limit = 10;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final number = await SupabaseService().getStudentNumber(widget.studentId);
      final rows = await ExamService().getStudentExamHistory(
        widget.studentId,
        offeringId: widget.offering.id,
        subjectCode: widget.offering.subjectCode,
        subjectTitle: widget.offering.subjectTitle,
        section: widget.offering.section,
      );
      if (!mounted) return;
      setState(() {
        _studentNumber = number;
        _history = rows;
        _loading = false;
        _updatedAt = DateTime.now();
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    if (mounted) await _load();
  }

  void _openHistory() => _open(
    ExamHistoryScreen(studentId: widget.studentId, offering: widget.offering),
  );

  @override
  Widget build(BuildContext context) => Theme(
    data: ExamUi.studentThemeOverlay(Theme.of(context)),
    child: Builder(
      builder: (context) => SubjectLayout(
        title:
            '${widget.offering.subjectCode} — ${widget.offering.subjectTitle}',
        subtitle:
            '${widget.studentName}\nSection ${widget.offering.section}\nStudent number: ${_studentNumber ?? (_loading ? 'Loading…' : 'Unavailable')}',
        onRefresh: _load,
        actions: [
          SubjectAction(
            'Mark attendance',
            Icons.fact_check_outlined,
            () => _open(
              StudentScreen(
                studentId: widget.studentId,
                studentName: widget.studentName,
                offering: widget.offering,
              ),
            ),
          ),
          SubjectAction(
            'Join exam',
            Icons.quiz_outlined,
            () => _open(
              JoinExamScreen(
                studentId: widget.studentId,
                studentName: widget.studentName,
                offering: widget.offering,
              ),
            ),
          ),
          SubjectAction(
            'Attendance history',
            Icons.history,
            () => _open(
              StudentHistoryScreen(
                studentId: widget.studentId,
                initialSubjectCode: widget.offering.subjectCode,
              ),
            ),
          ),
          SubjectAction(
            'Exam history',
            Icons.assignment_outlined,
            _openHistory,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdaptiveHeading(
              title: Text(
                'Exam performance',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              action: DropdownButtonFormField<int>(
                initialValue: _limit,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Show results'),
                items: const [
                  DropdownMenuItem(value: 5, child: Text('Latest 5')),
                  DropdownMenuItem(value: 10, child: Text('Latest 10')),
                  DropdownMenuItem(value: 0, child: Text('All results')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _limit = value);
                },
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_failed)
              LoadError(
                message: 'Could not load your exam results.',
                onRetry: _load,
              )
            else
              _performance(context),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _openHistory,
              icon: const Icon(Icons.history),
              label: const Text('View full exam history'),
            ),
            if (_updatedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
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

  Widget _performance(BuildContext context) {
    final completed = _history
        .where((e) => e.status == 'completed' && e.percentageScore != null)
        .toList();
    final visible = (_limit == 0 ? completed : completed.take(_limit))
        .toList()
        .reversed
        .toList();
    if (visible.isEmpty) {
      return const DetailCard(
        title: 'No completed exams yet',
        details: ['Your scores will appear here after you submit an exam.'],
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Score (%) by exam • oldest to newest'),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, box) {
                final labelCount = (box.maxWidth / 80).floor().clamp(2, 8);
                final interval = (visible.length / labelCount)
                    .ceil()
                    .clamp(1, visible.length)
                    .toDouble();
                return Semantics(
                  label: 'Exam percentage chart. All values are listed below.',
                  child: SizedBox(
                    height:
                        220 +
                        40 *
                            (MediaQuery.textScalerOf(context).scale(1) - 1)
                                .clamp(0, 2),
                    child: LineChart(
                      LineChartData(
                        minY: 0,
                        maxY: 100,
                        minX: -0.2,
                        maxX: visible.length - 0.8,
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            fitInsideHorizontally: true,
                            fitInsideVertically: true,
                            maxContentWidth: box.maxWidth * 0.7,
                            getTooltipItems: (spots) => spots
                                .map(
                                  (spot) => LineTooltipItem(
                                    '${visible[spot.x.toInt()].examTitle}\n${spot.y.toStringAsFixed(1)}%',
                                    const TextStyle(color: Colors.white),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: 25,
                              reservedSize:
                                  48 *
                                  MediaQuery.textScalerOf(context).scale(1),
                              getTitlesWidget: (value, meta) => Text(
                                '${value.toInt()}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: interval,
                              reservedSize:
                                  36 *
                                  MediaQuery.textScalerOf(context).scale(1),
                              getTitlesWidget: (value, meta) {
                                if (value != value.roundToDouble() ||
                                    value < 0 ||
                                    value >= visible.length) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  'E${value.toInt() + 1}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                );
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        gridData: const FlGridData(drawVerticalLine: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (var i = 0; i < visible.length; i++)
                                FlSpot(
                                  i.toDouble(),
                                  visible[i].percentageScore!,
                                ),
                            ],
                            color: Colors.tealAccent,
                            barWidth: 3,
                            isCurved: false,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < visible.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'E${i + 1} · ${visible[i].examTitle}\n${visible[i].percentageScore!.toStringAsFixed(1)}% · ${ExamUi.formatExamDateTime(visible[i].finishedAt)}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
