import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../ui/teacher_attendance_ui.dart';
import '../ui/responsive.dart';
import 'teacher_session_detail_screen.dart';

class TeacherHistoryScreen extends StatefulWidget {
  const TeacherHistoryScreen({
    super.key,
    required this.teacherId,
  });

  final String teacherId;

  @override
  State<TeacherHistoryScreen> createState() => _TeacherHistoryScreenState();
}

class _TeacherHistoryScreenState extends State<TeacherHistoryScreen> {
  final _db = SupabaseService();
  bool _loading = true;
  String? _error;
  List<TeacherSessionHistoryItem> _history = [];
  DateTimeRange? _dateRange;
  String? _subjectFilter;
  String? _sectionFilter;

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
      final rows = await _db.getTeacherSessionHistory(widget.teacherId);
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

  List<TeacherSessionHistoryItem> get _filteredHistory {
    return _history.where((item) {
      if (_dateRange != null) {
        final end = _dateRange!.end.add(const Duration(days: 1));
        if (item.startedAt.isBefore(_dateRange!.start) ||
            !item.startedAt.isBefore(end)) {
          return false;
        }
      }
      if (_subjectFilter != null && _subjectFilter!.isNotEmpty) {
        if (item.subjectCode != _subjectFilter) return false;
      }
      if (_sectionFilter != null && _sectionFilter!.isNotEmpty) {
        if (item.section != _sectionFilter) return false;
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
              primary: TeacherAttendanceUi.accentPurple,
              onPrimary: Colors.white,
              surface: TeacherAttendanceUi.surface,
              onSurface: Colors.white,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: TeacherAttendanceUi.surface,
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
    final themed = TeacherAttendanceUi.themeOverlay(Theme.of(context));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: themed,
        child: AlertDialog(
          backgroundColor: TeacherAttendanceUi.surface,
          title: const Text('Clear History'),
          content: const Text(
            'Delete all your session history? This cannot be undone.',
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
      await _db.clearTeacherHistory(widget.teacherId);
      if (!mounted) return;
      setState(() {
        _subjectFilter = null;
        _sectionFilter = null;
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

  void _openSessionDetail(TeacherSessionHistoryItem item) {
    if (item.sessionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session details unavailable for this record.'),
        ),
      );
      return;
    }
    final overlay = TeacherAttendanceUi.themeOverlay(Theme.of(context));
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (ctx) => Theme(
          data: overlay,
          child: TeacherSessionDetailScreen(
            teacherId: widget.teacherId,
            session: item,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final historyTheme = TeacherAttendanceUi.themeOverlay(baseTheme);

    return Theme(
      data: historyTheme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Session History'),
          actions: [
            IconButton(
              tooltip: 'Filter by date (picker)',
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
                    child: Scrollbar(
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
                                  color: TeacherAttendanceUi.textSecondary,
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
                    ),
                  )
                : _history.isEmpty
                    ? const Center(
                        child: Text(
                          'No session history yet.',
                          style: TextStyle(
                            color: TeacherAttendanceUi.textSecondary,
                          ),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final screenW = MediaQuery.sizeOf(context).width;
                          final hPad = AppBreakpoints.horizontalPadding(context);
                          final maxContent =
                              AppBreakpoints.historyContentMaxWidth(screenW);
                          final innerW = constraints.maxWidth < maxContent
                              ? constraints.maxWidth
                              : maxContent;
                          final contentInner =
                              (innerW - hPad * 2).clamp(0.0, double.infinity);
                          final cols = AppBreakpoints.historySessionGridColumns(
                            contentInner,
                          );
                          final tileExtent =
                              AppBreakpoints.historySessionTileExtent(
                            context,
                            cols,
                          );
                          final list = _filteredHistory;
                          final compactFilters =
                              AppBreakpoints.historyUseCompactFilters(
                            contentInner,
                          );
                          final cellW = cols > 0
                              ? (contentInner - (cols - 1) * 12) / cols
                              : contentInner;
                          final tightCell = cellW < 300;

                          final subjectField = DropdownButtonFormField<String>(
                            key: ValueKey<String>('sub_${_subjectFilter ?? ''}'),
                            initialValue: _subjectFilter ?? '',
                            decoration: const InputDecoration(
                              labelText: 'Subject',
                            ),
                            isExpanded: true,
                            dropdownColor: TeacherAttendanceUi.surface,
                            style: const TextStyle(color: Colors.white),
                            items: [
                              const DropdownMenuItem<String>(
                                value: '',
                                child: Text('All'),
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
                          final sectionField = DropdownButtonFormField<String>(
                            key: ValueKey<String>('sec_${_sectionFilter ?? ''}'),
                            initialValue: _sectionFilter ?? '',
                            decoration: const InputDecoration(
                              labelText: 'Section',
                            ),
                            isExpanded: true,
                            dropdownColor: TeacherAttendanceUi.surface,
                            style: const TextStyle(color: Colors.white),
                            items: [
                              const DropdownMenuItem<String>(
                                value: '',
                                child: Text('All'),
                              ),
                              ..._history
                                  .map((e) => e.section)
                                  .toSet()
                                  .map(
                                    (section) => DropdownMenuItem(
                                      value: section,
                                      child: Text(
                                        section,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                            ],
                            onChanged: (v) => setState(
                              () => _sectionFilter =
                                  (v == null || v.isEmpty) ? null : v,
                            ),
                          );

                          final filters = (!compactFilters) && cols >= 2
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: subjectField),
                                    SizedBox(width: innerW >= 720 ? 16 : 12),
                                    Expanded(child: sectionField),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    subjectField,
                                    const SizedBox(height: 12),
                                    sectionField,
                                  ],
                                );

                          final datePanel = _HistoryDateFilterPanel(
                            dateRange: _dateRange,
                            compact: compactFilters,
                            onPickRange: _pickDateRange,
                            onClearRange: () => setState(() => _dateRange = null),
                            formatDateOnly: _fmtDateOnly,
                            formatDateTime: _fmt,
                          );

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
                                      child: filters,
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
                                            'No sessions match your filters.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: TeacherAttendanceUi
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
                                      sliver: SliverGrid(
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: cols,
                                          mainAxisSpacing: 12,
                                          crossAxisSpacing: 12,
                                          mainAxisExtent: tileExtent,
                                        ),
                                        delegate: SliverChildBuilderDelegate(
                                          childCount: list.length,
                                          (context, i) {
                                            return _SessionHistoryCard(
                                              item: list[i],
                                              formatDate: _fmt,
                                              onTap: () => _openSessionDetail(
                                                list[i],
                                              ),
                                              tightLayout: tightCell,
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

/// In-screen date filter: always visible, adapts to narrow vs wide width.
class _HistoryDateFilterPanel extends StatelessWidget {
  const _HistoryDateFilterPanel({
    required this.dateRange,
    required this.compact,
    required this.onPickRange,
    required this.onClearRange,
    required this.formatDateOnly,
    required this.formatDateTime,
  });

  final DateTimeRange? dateRange;
  final bool compact;
  final VoidCallback onPickRange;
  final VoidCallback onClearRange;
  final String Function(DateTime) formatDateOnly;
  final String Function(DateTime) formatDateTime;

  @override
  Widget build(BuildContext context) {
    final hasRange = dateRange != null;
    final summary = hasRange
        ? '${formatDateOnly(dateRange!.start)}  →  ${formatDateOnly(dateRange!.end)}'
        : 'All dates';
    final sub = hasRange
        ? '${formatDateTime(dateRange!.start)} — ${formatDateTime(dateRange!.end)}'
        : 'Sessions are not filtered by start date. Tap to choose a range.';

    final iconBox = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: TeacherAttendanceUi.accentPurple.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: TeacherAttendanceUi.accentPurple.withValues(alpha: 0.45),
        ),
      ),
      child: const Icon(
        Icons.date_range_rounded,
        color: TeacherAttendanceUi.accentPurple,
        size: 22,
      ),
    );

    final textBlock = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Date filter',
            style: TextStyle(
              color: TeacherAttendanceUi.textSecondary,
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
              color: TeacherAttendanceUi.textSecondary.withValues(
                alpha: 0.95,
              ),
              fontSize: 11,
              height: 1.35,
            ),
            maxLines: compact ? 3 : 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    final pickButton = FilledButton.tonalIcon(
      onPressed: onPickRange,
      icon: const Icon(Icons.edit_calendar_outlined, size: 20),
      label: Text(compact ? 'Dates' : 'Select range'),
      style: FilledButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor:
            TeacherAttendanceUi.accentPurple.withValues(alpha: 0.35),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: 10,
        ),
      ),
    );

    final clearBtn = hasRange
        ? IconButton(
            tooltip: 'Clear date filter',
            onPressed: onClearRange,
            icon: const Icon(Icons.close_rounded),
            color: TeacherAttendanceUi.textSecondary,
          )
        : null;

    return Material(
      color: TeacherAttendanceUi.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPickRange,
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
                                  color: TeacherAttendanceUi.textSecondary,
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
                        color: TeacherAttendanceUi.textSecondary.withValues(
                          alpha: 0.95,
                        ),
                        fontSize: 11,
                        height: 1.35,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: pickButton),
                      ],
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    iconBox,
                    const SizedBox(width: 12),
                    textBlock,
                    ?clearBtn,
                    const SizedBox(width: 4),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: pickButton,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SessionHistoryCard extends StatelessWidget {
  const _SessionHistoryCard({
    required this.item,
    required this.formatDate,
    required this.onTap,
    this.tightLayout = false,
  });

  final TeacherSessionHistoryItem item;
  final String Function(DateTime) formatDate;
  final VoidCallback onTap;
  final bool tightLayout;

  @override
  Widget build(BuildContext context) {
    final ended = item.endedAt == null
        ? 'In progress'
        : formatDate(item.endedAt!);
    final titleLines = tightLayout ? 1 : 2;
    final timeStyle = TextStyle(
      color: TeacherAttendanceUi.textSecondary,
      fontSize: tightLayout ? 10 : 11,
    );

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: TeacherAttendanceUi.accentPurple.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: TeacherAttendanceUi.accentPurple.withValues(alpha: 0.55),
        ),
      ),
      child: Text(
        item.isActive ? 'Active' : 'Done',
        style: const TextStyle(
          color: TeacherAttendanceUi.accentPurple,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return Material(
      color: TeacherAttendanceUi.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            tightLayout ? 8 : 10,
            tightLayout ? 8 : 10,
            tightLayout ? 8 : 10,
            tightLayout ? 6 : 8,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: tightLayout ? 40 : 46,
                height: tightLayout ? 40 : 46,
                decoration: BoxDecoration(
                  color: TeacherAttendanceUi.accentPurple
                      .withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: TeacherAttendanceUi.accentPurple
                        .withValues(alpha: 0.45),
                  ),
                ),
                child: Icon(
                  Icons.event_available_rounded,
                  color: TeacherAttendanceUi.accentPurple,
                  size: tightLayout ? 22 : 24,
                ),
              ),
              SizedBox(width: tightLayout ? 8 : 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.subjectCode} - ${item.subjectTitle}',
                      maxLines: titleLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: tightLayout ? 12.5 : 13.5,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: tightLayout ? 2 : 3),
                    Text(
                      'Section ${item.section}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: TeacherAttendanceUi.textSecondary,
                        fontSize: tightLayout ? 10.5 : 11.5,
                      ),
                    ),
                    SizedBox(height: tightLayout ? 3 : 4),
                    Text(
                      'Started: ${formatDate(item.startedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: timeStyle,
                    ),
                    Text(
                      'Ended: $ended',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: timeStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: chip,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
