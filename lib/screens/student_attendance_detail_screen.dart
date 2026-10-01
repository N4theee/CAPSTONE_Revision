import '../ui/adaptive_layout.dart';
import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../ui/responsive.dart';
import '../ui/student_attendance_ui.dart';

class StudentAttendanceDetailScreen extends StatelessWidget {
  const StudentAttendanceDetailScreen({super.key, required this.item});

  final StudentAttendanceHistoryItem item;

  String _fmt(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppBreakpoints.horizontalPadding(context);
    final maxW = AppBreakpoints.historyContentMaxWidth(
      MediaQuery.sizeOf(context).width,
    );
    final overlay = StudentAttendanceUi.themeOverlay(Theme.of(context));

    return Theme(
      data: overlay,
      child: Scaffold(
        appBar: AppBar(title: const Text('Attendance Details')),
        body: ResponsivePage(
          maxWidth: 1040,
          child: LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 400;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  pad,
                  12,
                  pad,
                  24 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxW),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _CourseHeaderCard(
                          title: '${item.subjectCode} - ${item.subjectTitle}',
                          sectionLine: 'Section ${item.section}',
                          teacherLine: item.teacherName,
                          narrow: narrow,
                        ),
                        const SizedBox(height: 14),
                        narrow
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _TimeSummaryTile(
                                    icon: Icons.calendar_month_rounded,
                                    label: 'Class started',
                                    value: _fmt(item.sessionStartedAt),
                                  ),
                                  const SizedBox(height: 10),
                                  _TimeSummaryTile(
                                    icon: Icons.check_circle_outline_rounded,
                                    label: 'You attended',
                                    value: _fmt(item.markedAt),
                                  ),
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _TimeSummaryTile(
                                      icon: Icons.calendar_month_rounded,
                                      label: 'Class started',
                                      value: _fmt(item.sessionStartedAt),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _TimeSummaryTile(
                                      icon: Icons.check_circle_outline_rounded,
                                      label: 'You attended',
                                      value: _fmt(item.markedAt),
                                    ),
                                  ),
                                ],
                              ),
                        const SizedBox(height: 16),
                        Text(
                          'Attendance summary',
                          style: TextStyle(
                            color: StudentAttendanceUi.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Attendance recorded as present. Historical Bluetooth signal strength is not stored with this record.',
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _HowItWorksCard(onMore: () => _showHowDialog(context)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showHowDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Theme(
        data: StudentAttendanceUi.themeOverlay(Theme.of(context)),
        child: AlertDialog(
          backgroundColor: StudentAttendanceUi.surfaceElevated,
          title: const Text('How it works'),
          content: const Text(
            'Your phone listens for the teacher’s Bluetooth beacon. '
            'Keep Bluetooth and Location on and stay within range to mark attendance.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseHeaderCard extends StatelessWidget {
  const _CourseHeaderCard({
    required this.title,
    required this.sectionLine,
    required this.teacherLine,
    required this.narrow,
  });

  final String title;
  final String sectionLine;
  final String teacherLine;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: StudentAttendanceUi.surfaceElevated,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: EdgeInsets.all(narrow ? 14 : 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: narrow ? 52 : 58,
              height: narrow ? 52 : 58,
              decoration: BoxDecoration(
                color: StudentAttendanceUi.accentTeal.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: StudentAttendanceUi.mint.withValues(alpha: 0.35),
                ),
              ),
              child: Icon(
                Icons.menu_book_rounded,
                color: StudentAttendanceUi.mint,
                size: narrow ? 26 : 30,
              ),
            ),
            SizedBox(width: narrow ? 12 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      height: 1.25,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    sectionLine,
                    style: const TextStyle(
                      color: StudentAttendanceUi.textSecondary,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    teacherLine,
                    style: const TextStyle(
                      color: StudentAttendanceUi.textSecondary,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeSummaryTile extends StatelessWidget {
  const _TimeSummaryTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: StudentAttendanceUi.surfaceElevated,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: StudentAttendanceUi.accentTeal, size: 22),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                color: StudentAttendanceUi.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard({required this.onMore});

  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: StudentAttendanceUi.surfaceElevated,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onMore,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: StudentAttendanceUi.accentTeal,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'How it works',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your phone listens for the teacher’s Bluetooth beacon. '
                      'Stay in range with Bluetooth on to verify attendance.',
                      style: TextStyle(
                        color: StudentAttendanceUi.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap for details',
                      style: TextStyle(
                        color: StudentAttendanceUi.mint.withValues(alpha: 0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
