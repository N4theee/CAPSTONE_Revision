import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../ui/responsive.dart';
import '../ui/student_attendance_ui.dart';
import 'student_attendance_detail_screen.dart';

class StudentHistoryScreen extends StatefulWidget {
  const StudentHistoryScreen({
    super.key,
    required this.studentId,
  });

  final String studentId;

  @override
  State<StudentHistoryScreen> createState() => _StudentHistoryScreenState();
}

class _StudentHistoryScreenState extends State<StudentHistoryScreen> {
  final _db = SupabaseService();
  bool _loading = true;
  String? _error;
  List<StudentAttendanceHistoryItem> _history = [];
  DateTimeRange? _dateRange;
  String? _subjectFilter;

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
      final rows = await _db.getStudentAttendanceHistory(widget.studentId);
      if (!mounted) return;
      setState(() {
        _history = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _fmt(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String _fmtDateOnly(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final y = dt.year.toString();
    return '$y-$m-$d';
  }

  List<StudentAttendanceHistoryItem> get _filteredHistory {
    return _history.where((item) {
      if (_dateRange != null) {
        final end = _dateRange!.end.add(const Duration(days: 1));
        if (item.markedAt.isBefore(_dateRange!.start) ||
            !item.markedAt.isBefore(end)) {
          return false;
        }
      }
      if (_subjectFilter != null && _subjectFilter!.isNotEmpty) {
        if (item.subjectCode != _subjectFilter) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final base = Theme.of(context);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _dateRange,
      builder: (ctx, child) {
        return Theme(
          data: base.copyWith(
            colorScheme: ColorScheme.dark(
              primary: StudentAttendanceUi.accentTeal,
              onPrimary: Colors.white,
              surface: StudentAttendanceUi.surface,
              onSurface: Colors.white,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: StudentAttendanceUi.surface,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _dateRange = picked);
  }

  Future<void> _clearHistory() async {
    final themed = StudentAttendanceUi.themeOverlay(Theme.of(context));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: themed,
        child: AlertDialog(
          backgroundColor: StudentAttendanceUi.surfaceElevated,
          title: const Text('Clear History'),
          content: const Text(
            'Delete all your attendance history? This cannot be undone.',
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
      await _db.clearStudentHistory(widget.studentId);
      if (!mounted) return;
      setState(() {
        _subjectFilter = null;
        _dateRange = null;
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('History cleared.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not clear history: $e')),
      );
      await _load();
    }
  }

  void _openDetail(StudentAttendanceHistoryItem item) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (ctx) => StudentAttendanceDetailScreen(item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themed = StudentAttendanceUi.themeOverlay(Theme.of(context));

    return Theme(
      data: themed,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Attendance History'),
          actions: [
            IconButton(
              tooltip: 'Filter by date',
              onPressed: _pickDateRange,
              icon: const Icon(Icons.calendar_month_rounded),
            ),
            IconButton(
              tooltip: 'Clear history',
              onPressed: _history.isEmpty ? null : _clearHistory,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Failed to load history.\n$_error',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: StudentAttendanceUi.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : _history.isEmpty
                    ? const Center(
                        child: Text(
                          'No attendance history yet.',
                          style: TextStyle(
                            color: StudentAttendanceUi.textSecondary,
                          ),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final screenW = MediaQuery.sizeOf(context).width;
                          final hPad = AppBreakpoints.horizontalPadding(context);
                          final maxContent =
                              AppBreakpoints.historyContentMaxWidth(screenW);
                          final rawInner =
                              (constraints.maxWidth < maxContent
                                      ? constraints.maxWidth
                                      : maxContent) -
                                  hPad * 2;
                          final inner = rawInner < 0 ? 0.0 : rawInner;
                          final compactDate =
                              AppBreakpoints.historyUseCompactFilters(inner);

                          final subjectField = DropdownButtonFormField<String>(
                            key: ValueKey<String>('sub_${_subjectFilter ?? ''}'),
                            initialValue: _subjectFilter ?? '',
                            decoration: const InputDecoration(
                              labelText: 'Subject',
                              hintText: 'All Subjects',
                            ),
                            isExpanded: true,
                            dropdownColor: StudentAttendanceUi.surface,
                            style: const TextStyle(color: Colors.white),
                            items: [
                              const DropdownMenuItem<String>(
                                value: '',
                                child: Text('All Subjects'),
                              ),
                              ..._history
                                  .map((e) => e.subjectCode)
                                  .toSet()
                                  .map(
                                    (code) => DropdownMenuItem(
                                      value: code,
                                      child: Text(
                                        code,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                            ],
                            onChanged: (v) => setState(
                              () => _subjectFilter =
                                  (v == null || v.isEmpty) ? null : v,
                            ),
                          );

                          final datePanel = _StudentHistoryDatePanel(
                            dateRange: _dateRange,
                            compact: compactDate,
                            onPick: _pickDateRange,
                            onClear: () => setState(() => _dateRange = null),
                            fmtDateOnly: _fmtDateOnly,
                            fmtDateTime: _fmt,
                          );

                          final list = _filteredHistory;

                          return Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: maxContent),
                              child: CustomScrollView(
                                slivers: [
                                  SliverPadding(
                                    padding: EdgeInsets.fromLTRB(
                                      hPad,
                                      12,
                                      hPad,
                                      8,
                                    ),
                                    sliver: SliverToBoxAdapter(
                                      child: subjectField,
                                    ),
                                  ),
                                  SliverPadding(
                                    padding: EdgeInsets.fromLTRB(
                                      hPad,
                                      0,
                                      hPad,
                                      10,
                                    ),
                                    sliver: SliverToBoxAdapter(
                                      child: datePanel,
                                    ),
                                  ),
                                  if (list.isEmpty)
                                    SliverFillRemaining(
                                      hasScrollBody: false,
                                      child: Center(
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: hPad,
                                          ),
                                          child: const Text(
                                            'No records match your filters.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: StudentAttendanceUi
                                                  .textSecondary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    SliverPadding(
                                      padding: EdgeInsets.fromLTRB(
                                        hPad,
                                        0,
                                        hPad,
                                        16,
                                      ),
                                    sliver: SliverList(
                                      delegate: SliverChildBuilderDelegate(
                                        childCount: list.length,
                                        (context, i) {
                                          return Padding(
                                            padding: EdgeInsets.only(
                                              bottom:
                                                  i < list.length - 1 ? 10 : 0,
                                            ),
                                            child: _HistoryListCard(
                                              item: list[i],
                                              formatDate: _fmt,
                                              onTap: () =>
                                                  _openDetail(list[i]),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

class _StudentHistoryDatePanel extends StatelessWidget {
  const _StudentHistoryDatePanel({
    required this.dateRange,
    required this.compact,
    required this.onPick,
    required this.onClear,
    required this.fmtDateOnly,
    required this.fmtDateTime,
  });

  final DateTimeRange? dateRange;
  final bool compact;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final String Function(DateTime) fmtDateOnly;
  final String Function(DateTime) fmtDateTime;

  @override
  Widget build(BuildContext context) {
    final has = dateRange != null;
    final summary =
        has ? '${fmtDateOnly(dateRange!.start)} → ${fmtDateOnly(dateRange!.end)}' : 'All dates';
    final sub = has
        ? '${fmtDateTime(dateRange!.start)} — ${fmtDateTime(dateRange!.end)}'
        : 'Filter by the day you marked attendance. Tap to choose a range.';

    final iconBox = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: StudentAttendanceUi.accentTeal.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: StudentAttendanceUi.mint.withValues(alpha: 0.35),
        ),
      ),
      child: const Icon(
        Icons.date_range_rounded,
        color: StudentAttendanceUi.mint,
        size: 22,
      ),
    );

    final clearBtn = has
        ? IconButton(
            tooltip: 'Clear date filter',
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded),
            color: StudentAttendanceUi.textSecondary,
          )
        : null;

    final pickBtn = FilledButton.tonalIcon(
      onPressed: onPick,
      icon: const Icon(Icons.edit_calendar_outlined, size: 20),
      label: Text(compact ? 'Dates' : 'Select range'),
      style: FilledButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor:
            StudentAttendanceUi.accentTeal.withValues(alpha: 0.35),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: 10,
        ),
      ),
    );

    return Material(
      color: StudentAttendanceUi.surfaceElevated,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPick,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        iconBox,
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Date filter',
                                style: TextStyle(
                                  color: StudentAttendanceUi.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                summary,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        ?clearBtn,
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      sub,
                      style: TextStyle(
                        color: StudentAttendanceUi.textSecondary.withValues(
                          alpha: 0.95,
                        ),
                        fontSize: 11,
                        height: 1.35,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Row(children: [Expanded(child: pickBtn)]),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    iconBox,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Date filter',
                            style: TextStyle(
                              color: StudentAttendanceUi.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            summary,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sub,
                            style: TextStyle(
                              color: StudentAttendanceUi.textSecondary
                                  .withValues(alpha: 0.95),
                              fontSize: 11,
                              height: 1.35,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    ?clearBtn,
                    const SizedBox(width: 4),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: pickBtn,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _HistoryListCard extends StatelessWidget {
  const _HistoryListCard({
    required this.item,
    required this.formatDate,
    required this.onTap,
  });

  final StudentAttendanceHistoryItem item;
  final String Function(DateTime) formatDate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: StudentAttendanceUi.surfaceElevated,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: StudentAttendanceUi.accentTeal.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: StudentAttendanceUi.mint.withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(
                  Icons.school_rounded,
                  color: StudentAttendanceUi.mint,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.subjectCode} - ${item.subjectTitle}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Section ${item.section} • ${item.teacherName}',
                      style: const TextStyle(
                        color: StudentAttendanceUi.textSecondary,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    _TinyMetaRow(
                      icon: Icons.calendar_today_outlined,
                      text: 'Class started: ${formatDate(item.sessionStartedAt)}',
                    ),
                    const SizedBox(height: 4),
                    _TinyMetaRow(
                      icon: Icons.check_circle_outline_rounded,
                      text: 'You attended: ${formatDate(item.markedAt)}',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: StudentAttendanceUi.textSecondary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TinyMetaRow extends StatelessWidget {
  const _TinyMetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: StudentAttendanceUi.accentTeal),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: StudentAttendanceUi.textSecondary,
              fontSize: 11,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
