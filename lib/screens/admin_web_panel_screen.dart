import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/admin_data_service.dart';
import '../services/supabase_service.dart';
import '../util/admin_export.dart';
import 'admin_operations_panel.dart';
import 'admin_record_picker.dart';
import 'admin_class_form.dart';
import 'home_screen.dart';

class AdminWebPanelScreen extends StatefulWidget {
  const AdminWebPanelScreen({super.key, this.user});
  final AppUser? user;
  @override
  State<AdminWebPanelScreen> createState() => _AdminWebPanelScreenState();
}

const _bg = Color(0xFF0C1325);
const _surface = Color(0xFF182338);
const _border = Color(0xFF2B3651);
const _muted = Color(0xFF9DAAC8);
const _violet = Color(0xFF8855FF);
const _teal = Color(0xFF24DDB5);
const _colors = [
  _teal,
  Color(0xFF29BDF1),
  _violet,
  Color(0xFFE553AF),
  Color(0xFFFFAB4B),
  Color(0xFF697CE5),
];
const _nav = <(String, String, IconData, String)>[
  ('dashboard', 'Dashboard', Icons.home_rounded, ''),
  ('students', 'Students', Icons.people_outline, 'User Management'),
  ('teachers', 'Teachers', Icons.person_outline, 'User Management'),
  ('admins', 'Admins', Icons.admin_panel_settings_outlined, 'User Management'),
  ('subjects', 'Subjects', Icons.menu_book_outlined, 'Academic Management'),
  ('classes', 'Class Sections', Icons.grid_view_rounded, 'Academic Management'),
  (
    'enrollments',
    'Enrollments',
    Icons.assignment_ind_outlined,
    'Academic Management',
  ),
  ('exams', 'Exams', Icons.description_outlined, 'Examination'),
  ('questions', 'Question Bank', Icons.quiz_outlined, 'Examination'),
  ('attempts', 'Attempt Logs', Icons.fact_check_outlined, 'Examination'),
  ('sessions', 'Attendance Sessions', Icons.sensors_outlined, 'Attendance'),
  (
    'records',
    'Attendance Records',
    Icons.event_available_outlined,
    'Attendance',
  ),
  ('reports', 'Analytics & Reports', Icons.bar_chart_rounded, 'Reports'),
  ('settings', 'Settings', Icons.settings_outlined, 'System'),
  ('activity', 'Activity Logs', Icons.history_rounded, 'System'),
];

String _value(dynamic row, String path, {String fallback = '—'}) {
  dynamic value = row;
  for (final part in path.split('.')) {
    if (value is List) value = value.isEmpty ? null : value.first;
    if (value is! Map) return fallback;
    value = value[part];
  }
  return value == null || '$value'.isEmpty ? fallback : '$value';
}

String _date(dynamic raw, {bool time = false}) {
  final dt = DateTime.tryParse('$raw')?.toLocal();
  if (dt == null) return '—';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}${time ? ' · ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}' : ''}';
}

List<(String, String)> _columns(String kind) => switch (kind) {
  'students' => [
    ('Name', 'full_name'),
    ('Student ID', 'student_number'),
    ('Username', 'email'),
    ('Registered', 'created_at'),
  ],
  'teachers' => [
    ('Name', 'full_name'),
    ('Username', 'email'),
    ('Capacity', 'max_students'),
    ('Registered', 'created_at'),
  ],
  'admins' => [
    ('Name', 'full_name'),
    ('Username', 'email'),
    ('Registered', 'created_at'),
  ],
  'subjects' => [
    ('Code', 'subject_code'),
    ('Subject title', 'subject_title'),
    ('Created', 'created_at'),
  ],
  'classes' => [
    ('Subject', 'subjects.subject_code'),
    ('Section', 'sections.section_name'),
    ('Teacher', 'teachers.full_name'),
    ('Beacon', 'beacon_name'),
    ('Active', 'is_active'),
  ],
  'enrollments' => [
    ('Student', 'students.full_name'),
    ('Subject', 'subject_offerings.subjects.subject_code'),
    ('Section', 'subject_offerings.sections.section_name'),
    ('Teacher', 'subject_offerings.teachers.full_name'),
    ('Enrolled', 'created_at'),
  ],
  'exams' => [
    ('Exam', 'exam_title'),
    ('Code', 'exam_code'),
    ('Subject', 'subject_offerings.subjects.subject_code'),
    ('Teacher', 'teachers.full_name'),
    ('Status', 'status'),
    ('Created', 'created_at'),
  ],
  'questions' => [
    ('Question', 'question_text'),
    ('Exam', 'exam_sessions.exam_title'),
    ('Points', 'points'),
    ('Order', 'question_order'),
  ],
  'attempts' => [
    ('Student', 'students.full_name'),
    ('Exam', 'exam_sessions.exam_title'),
    ('Score', 'percentage_score'),
    ('Duration (seconds)', 'completion_seconds'),
    ('Violations', 'violation_count'),
    ('Status', 'status'),
    ('Started', 'started_at'),
  ],
  'sessions' => [
    ('Subject', 'subject_offerings.subjects.subject_code'),
    ('Section', 'subject_offerings.sections.section_name'),
    ('Teacher', 'subject_offerings.teachers.full_name'),
    ('Started', 'started_at'),
    ('Active', 'is_active'),
  ],
  'records' => [
    ('Student', 'students.full_name'),
    ('Subject', 'attendance_sessions.subject_offerings.subjects.subject_code'),
    ('Section', 'attendance_sessions.subject_offerings.sections.section_name'),
    ('Status', 'status'),
    ('Recorded', 'marked_at'),
    ('Device', 'device_name'),
  ],
  'alerts' => [
    ('Student', 'students.full_name'),
    ('Exam', 'exam_sessions.exam_title'),
    ('Event', 'alert_type'),
    ('Message', 'message'),
    ('Recorded', 'created_at'),
  ],
  _ => [('Name', 'full_name')],
};

String _cell(AdminRow row, String path) {
  if (path == 'percentage_score') {
    if (row['status'] == 'in_progress') return 'Pending';
    return '${row['percentage_score'] ?? row['exam_score'] ?? 0}%';
  }
  final value = _value(row, path);
  if (path.endsWith('_at')) return _date(value);
  if (path == 'is_active') return value == 'true' ? 'Active' : 'Inactive';
  return value;
}

Widget _panel(Widget child) => Container(
  padding: const EdgeInsets.all(20),
  decoration: BoxDecoration(
    gradient: const LinearGradient(
      colors: [_surface, Color(0xFF1D2540)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    border: Border.all(color: _border),
    borderRadius: BorderRadius.circular(14),
  ),
  child: child,
);

Widget _badge(String label) {
  final color = ['active', 'in_progress', 'Present', 'Active'].contains(label)
      ? _teal
      : label == 'scheduled'
      ? const Color(0xFFFFAB4B)
      : _violet;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      border: Border.all(color: color.withValues(alpha: .25)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label.replaceAll('_', ' '),
      style: TextStyle(color: color, fontSize: 10),
    ),
  );
}

class _AdminWebPanelScreenState extends State<AdminWebPanelScreen> {
  final _data = AdminDataService();
  final _db = SupabaseService();
  final _search = TextEditingController();
  final _school = TextEditingController(text: 'New Era High School');
  final _year = TextEditingController();
  String _selected = 'dashboard', _reportKind = 'records';
  bool _collapsed = false, _loading = true, _exporting = false;
  String? _error, _chartError, _status;
  AdminRow? _filterTeacher, _filterSubject, _filterExam;
  DateTimeRange? _range;
  List<AdminRow> _rows = [], _recentEnrollments = [], _recentExams = [];
  Map<String, int> _totals = {};
  AdminRow _summary = {};
  int _page = 0, _request = 0;
  AdminRow? _enrollmentSubject, _enrollmentClass, _questionExam;
  String get _kind => _selected == 'reports'
      ? _reportKind
      : _selected == 'enrollments'
      ? (_enrollmentSubject == null
            ? 'enrollmentSubjects'
            : _enrollmentClass == null
            ? 'classes'
            : 'enrollments')
      : _selected == 'questions'
      ? (_questionExam == null ? 'exams' : 'questions')
      : _selected;

  void _openGroup(AdminRow row) {
    setState(() {
      if (_selected == 'enrollments' && _enrollmentSubject == null) {
        _enrollmentSubject = row;
      } else if (_selected == 'enrollments' && _enrollmentClass == null) {
        _enrollmentClass = row;
      } else if (_selected == 'questions' && _questionExam == null) {
        _questionExam = row;
      }
      _page = 0;
      _range = null;
      _status = null;
      _search.clear();
      _rows = [];
    });
    _load();
  }

  void _backGroup() {
    setState(() {
      if (_enrollmentClass != null) {
        _enrollmentClass = null;
      } else {
        _enrollmentSubject = null;
      }
      _questionExam = null;
      _page = 0;
      _range = null;
      _status = null;
      _search.clear();
      _rows = [];
    });
    _load();
  }

  String get _title => _nav.firstWhere((d) => d.$1 == _selected).$2;

  @override
  void initState() {
    super.initState();
    _year.text = '${DateTime.now().year} – ${DateTime.now().year + 1}';
    _loadPreferences();
    _load();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _school.text = prefs.getString('admin_school_name') ?? _school.text;
      _year.text = prefs.getString('admin_school_year') ?? _year.text;
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _school.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    final kind = _kind;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (kind == 'activity') {
        final summary = await _data.summary();
        if (!mounted || request != _request) return;
        setState(() => _summary = summary);
      } else if (kind == 'dashboard') {
        AdminRow summary = {};
        String? chartError;
        final summaryFuture = _data
            .summary()
            .then((v) {
              summary = v;
            })
            .catchError((Object e) {
              chartError = 'Summary charts and activity could not be loaded.';
            });
        final values = await Future.wait<dynamic>([
          _data.totals(),
          _data.page('enrollments', size: 5),
          _data.page('exams', size: 5),
          summaryFuture,
        ]);
        if (!mounted || request != _request) return;
        setState(() {
          _totals = values[0] as Map<String, int>;
          _recentEnrollments = values[1] as List<AdminRow>;
          _recentExams = values[2] as List<AdminRow>;
          _summary = summary;
          _chartError = chartError;
        });
      } else if (kind != 'settings') {
        final rows = await _data.page(
          kind,
          page: _page,
          status: _status,
          teacherId: _filterTeacher?['id'] as String?,
          subjectId: _filterSubject?['id'] as String?,
          examId: (_questionExam ?? _filterExam)?['id'] as String?,
          filterColumn: _selected == 'enrollments' && _enrollmentSubject != null
              ? (_enrollmentClass == null
                    ? 'subject_id'
                    : 'subject_offering_id')
              : null,
          filterValue:
              (_enrollmentClass ?? _enrollmentSubject)?['id'] as String?,
          from: _range?.start,
          to: _range?.end.add(const Duration(days: 1)),
        );
        if (!mounted || request != _request) return;
        setState(() => _rows = rows);
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(() => _error = 'Could not load $_title. Please retry. $e');
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _navigate(String key) {
    setState(() {
      _selected = key;
      _enrollmentSubject = _enrollmentClass = _questionExam = null;
      _page = 0;
      _status = null;
      _filterTeacher = _filterSubject = _filterExam = null;
      _range = null;
      _rows = [];
      _search.clear();
    });
    _load();
  }

  void _toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Widget _sidebar({bool compact = false, bool drawer = false}) => Container(
    width: compact ? 80 : 242,
    color: const Color(0xFF121A30),
    child: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Image.asset(
                  'assets/branding/app-logo.png',
                  width: 36,
                  height: 45,
                ),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Admin Panel',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _school.text,
                          style: const TextStyle(color: _muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              key: const ValueKey('admin-navigation'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              children: [
                for (var i = 0; i < _nav.length; i++) ...[
                  if (!compact &&
                      _nav[i].$4.isNotEmpty &&
                      (i == 0 || _nav[i].$4 != _nav[i - 1].$4))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 22, 0, 8),
                      child: Text(
                        _nav[i].$4,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ),
                  Tooltip(
                    message: _nav[i].$2,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: _selected == _nav[i].$1
                            ? const LinearGradient(
                                colors: [Color(0xFF7E3CF5), Color(0xFF47318C)],
                              )
                            : null,
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: compact ? 13 : 12,
                        ),
                        leading: Icon(
                          _nav[i].$3,
                          size: 21,
                          color: _selected == _nav[i].$1
                              ? Colors.white
                              : _muted,
                        ),
                        title: compact
                            ? null
                            : Text(
                                _nav[i].$2,
                                style: const TextStyle(fontSize: 13),
                              ),
                        onTap: () {
                          if (drawer) Navigator.pop(context);
                          _navigate(_nav[i].$1);
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final theme = ThemeData.dark(useMaterial3: true).copyWith(
      textTheme: Theme.of(
        context,
      ).textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
      scaffoldBackgroundColor: _bg,
      colorScheme: const ColorScheme.dark(
        primary: _violet,
        secondary: _teal,
        surface: _surface,
      ),
      dividerColor: _border,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF202B42),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: _border),
        ),
      ),
      dataTableTheme: const DataTableThemeData(
        headingTextStyle: TextStyle(color: _muted, fontSize: 11),
        dataTextStyle: TextStyle(fontSize: 12),
      ),
    );
    return Theme(
      data: theme,
      child: Scaffold(
        drawer: wide ? null : Drawer(width: 260, child: _sidebar(drawer: true)),
        body: Row(
          children: [
            if (wide) _sidebar(compact: _collapsed),
            Expanded(
              child: Column(
                children: [
                  Builder(
                    builder: (context) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: _border)),
                        gradient: LinearGradient(
                          colors: [Color(0xFF211D47), _bg],
                        ),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Toggle navigation',
                            onPressed: () {
                              if (wide) {
                                setState(() => _collapsed = !_collapsed);
                              } else {
                                Scaffold.of(context).openDrawer();
                              }
                            },
                            icon: const Icon(Icons.menu),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'ProXamity',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Refresh',
                            onPressed: _loading ? null : _load,
                            icon: const Icon(Icons.refresh),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Administrator account',
                            onSelected: (v) {
                              if (v == 'settings') _navigate('settings');
                              if (v == 'logout') {
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const HomeScreen(),
                                  ),
                                  (_) => false,
                                );
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'settings',
                                child: Text('Display settings'),
                              ),
                              const PopupMenuItem(
                                value: 'logout',
                                child: Text('Sign out'),
                              ),
                            ],
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: _violet,
                                  child: Text(
                                    (widget.user?.fullName ?? 'Admin')
                                        .substring(0, 1)
                                        .toUpperCase(),
                                  ),
                                ),
                                if (wide) ...[
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.user?.fullName ??
                                            'Administrator',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const Text(
                                        'Administrator',
                                        style: TextStyle(
                                          color: _muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      key: ValueKey(_selected),
                      padding: EdgeInsets.all(wide ? 26 : 16),
                      children: [
                        _heading(),
                        const SizedBox(height: 22),
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 14),
                            child: LinearProgressIndicator(),
                          ),
                        if (_error != null)
                          _panel(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_error!),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: _load,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        else if (_selected == 'dashboard')
                          _dashboard()
                        else if (_selected == 'settings')
                          _settings()
                        else if (_selected == 'activity')
                          _activity()
                        else
                          _directory(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading() => Wrap(
    alignment: WrapAlignment.spaceBetween,
    runSpacing: 12,
    spacing: 24,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _selected == 'dashboard'
                ? 'Good day, ${widget.user?.fullName.split(' ').first ?? 'Administrator'}!'
                : _title,
            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(switch (_selected) {
            'dashboard' => 'Here’s an overview of your ProXamity system.',
            'questions' => 'Questions belonging to teacher-created exams.',
            'activity' =>
              'Recorded school events, rather than a complete audit trail.',
            'settings' => 'Customize the admin panel in this browser.',
            'attempts' => 'Review scores and Bluetooth monitoring history.',
            _ => 'Manage and review your school records.',
          }, style: const TextStyle(color: _muted, fontSize: 13)),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _date(DateTime.now().toIso8601String()),
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          Text(
            'School Year ${_year.text}',
            style: const TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ),
    ],
  );

  Widget _dashboard() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (_, c) {
          final count = c.maxWidth >= 850
              ? 4
              : c.maxWidth >= 450
              ? 2
              : 1;
          final width = (c.maxWidth - (count - 1) * 14) / count;
          const cards = [
            ('students', 'Total Students', Icons.person_outline),
            ('teachers', 'Total Teachers', Icons.groups_outlined),
            ('subjects', 'Total Subjects', Icons.menu_book_outlined),
            ('classes', 'Class Sections', Icons.grid_view_rounded),
          ];
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (var i = 0; i < cards.length; i++)
                SizedBox(
                  width: width,
                  child: InkWell(
                    onTap: () => _navigate(cards[i].$1),
                    child: _panel(
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: _colors[i].withValues(alpha: .18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              cards[i].$3,
                              color: _colors[i],
                              size: 29,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cards[i].$2,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_totals[cards[i].$1] ?? '—'}',
                                  style: const TextStyle(
                                    fontSize: 29,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'View records →',
                                  style: TextStyle(color: _teal, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 18),
      if (_chartError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            _chartError!,
            style: const TextStyle(color: Colors.orangeAccent),
          ),
        ),
      LayoutBuilder(
        builder: (_, c) {
          final width = c.maxWidth >= 950 ? (c.maxWidth - 28) / 3 : c.maxWidth;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              SizedBox(
                width: width,
                child: _donut(
                  'Class Enrollments',
                  _summary['enrollment_sections'],
                  'Registrations',
                  'enrollments',
                ),
              ),
              SizedBox(width: width, child: _attendanceChart()),
              SizedBox(
                width: width,
                child: _donut(
                  'Exam Activity',
                  _summary['exam_statuses'],
                  'Exams',
                  'exams',
                ),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 18),
      _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quick Actions',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _quick(
                  'Create Teacher',
                  Icons.person_add_alt,
                  _violet,
                  () => _operation(0),
                ),
                _quick(
                  'Create Subject',
                  Icons.menu_book,
                  const Color(0xFF2861CE),
                  () => _editSubject(),
                ),
                _quick(
                  'Create Class Section',
                  Icons.grid_view,
                  const Color(0xFF079E91),
                  () => _operation(1),
                ),
                _quick(
                  'Enroll Student',
                  Icons.group_add,
                  const Color(0xFFBF7724),
                  () => _operation(2),
                ),
                _quick(
                  'Generate Report',
                  Icons.bar_chart,
                  const Color(0xFF415697),
                  () => _navigate('reports'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      LayoutBuilder(
        builder: (_, c) {
          final width = c.maxWidth >= 1000 ? (c.maxWidth - 28) / 3 : c.maxWidth;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              SizedBox(
                width: width,
                child: _recent(
                  'Recent Enrollments',
                  'enrollments',
                  _recentEnrollments,
                ),
              ),
              SizedBox(
                width: width,
                child: _recent('Recent Exam Sessions', 'exams', _recentExams),
              ),
              SizedBox(width: width, child: _activity(compact: true)),
            ],
          );
        },
      ),
    ],
  );
  Widget _quick(
    String label,
    IconData icon,
    Color color,
    VoidCallback action,
  ) => FilledButton.icon(
    style: FilledButton.styleFrom(
      backgroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 19),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    onPressed: action,
    icon: Icon(icon, size: 20),
    label: Text(label, style: const TextStyle(fontSize: 12)),
  );
  List<AdminRow> _chartRows(dynamic value) =>
      value is List ? value.whereType<Map>().map(AdminRow.from).toList() : [];

  Widget _donut(
    String title,
    dynamic data,
    String caption,
    String destination,
  ) {
    final rows = _chartRows(data);
    final values = rows
        .map((r) => (r['value'] as num?)?.toDouble() ?? 0)
        .toList();
    final sum = values.fold<double>(0, (a, b) => a + b);
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'View $title',
                onPressed: () => _navigate(destination),
                icon: const Icon(Icons.arrow_outward, size: 17),
              ),
            ],
          ),
          const Text(
            'All recorded data',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
          const SizedBox(height: 20),
          if (rows.isEmpty)
            const SizedBox(
              height: 175,
              child: Center(
                child: Text(
                  'No summary available',
                  style: TextStyle(color: _muted),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (_, c) => Wrap(
                spacing: 18,
                runSpacing: 18,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: math.min(150, c.maxWidth),
                    height: 175,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _RingPainter(values, _colors),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${sum.toInt()}',
                              style: const TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(
                              width: 100,
                              child: Text(
                                caption,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: math.max(110, c.maxWidth - 168),
                    child: Column(
                      children: [
                        for (var i = 0; i < rows.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 10,
                                  color: _colors[i % _colors.length],
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${rows[i]['label']}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${values[i].toInt()}',
                                  style: const TextStyle(
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
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _attendanceChart() {
    final chartHeight =
        175.0 +
        math.max(0, MediaQuery.textScalerOf(context).scale(12) - 12) * 4;
    final rows = _chartRows(_summary['attendance_daily']);
    final max = rows.fold<double>(
      1,
      (a, r) => math.max(a, (r['value'] as num?)?.toDouble() ?? 0),
    );
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Attendance Overview',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'View attendance records',
                onPressed: () => _navigate('records'),
                icon: const Icon(Icons.arrow_outward, size: 17),
              ),
            ],
          ),
          const Text(
            'Recorded attendance · Last 7 days',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: chartHeight,
            child: rows.isEmpty
                ? const Center(
                    child: Text(
                      'No summary available',
                      style: TextStyle(color: _muted),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final r in rows)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  '${r['value']}',
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 10,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  height: math.max(
                                    4,
                                    ((r['value'] as num?)?.toDouble() ?? 0) /
                                        max *
                                        125,
                                  ),
                                  width: 24,
                                  decoration: BoxDecoration(
                                    color: _teal,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${r['day']}'.split('-').last,
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Days with recorded attendance',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _recent(String title, String kind, List<AdminRow> rows) => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _navigate(kind),
              child: const Text('View All', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('No records yet', style: TextStyle(color: _muted)),
          ),
        for (final r in rows) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              _value(r, kind == 'exams' ? 'exam_title' : 'students.full_name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _value(
                r,
                kind == 'exams'
                    ? 'exam_code'
                    : 'subject_offerings.subjects.subject_code',
              ),
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
            trailing: kind == 'exams'
                ? _badge(_value(r, 'status'))
                : Text(
                    _date(r['created_at']),
                    style: const TextStyle(color: _muted, fontSize: 10),
                  ),
            onTap: () => _details(kind, r),
          ),
          const Divider(height: 1),
        ],
      ],
    ),
  );
  Widget _activity({bool compact = false}) {
    final rows = _chartRows(_summary['activity']);
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  compact ? 'System Activity' : 'Recorded Activity',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (compact)
                TextButton(
                  onPressed: () => _navigate('activity'),
                  child: const Text('View All', style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
          if (_chartError != null && !compact)
            Text(
              _chartError!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No activity available',
                style: TextStyle(color: _muted),
              ),
            ),
          for (final r in rows.take(compact ? 5 : 12))
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const CircleAvatar(
                radius: 15,
                backgroundColor: Color(0xFF155C5A),
                child: Icon(Icons.check, size: 17, color: _teal),
              ),
              title: Text(
                _value(r, 'title'),
                style: const TextStyle(fontSize: 12),
              ),
              subtitle: Text(
                _value(r, 'detail'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
              trailing: Text(
                _date(r['event_at']),
                style: const TextStyle(color: _muted, fontSize: 10),
              ),
              onTap: () =>
                  _navigate(_value(r, 'destination', fallback: 'dashboard')),
            ),
        ],
      ),
    );
  }

  List<String> get _statuses => switch (_kind) {
    'exams' => ['scheduled', 'active', 'paused', 'ended', 'cancelled'],
    'attempts' => ['in_progress', 'completed', 'flagged', 'auto_ended'],
    'classes' || 'sessions' => ['Active', 'Inactive'],
    _ => [],
  };
  Widget _directory() {
    final kind = _kind;
    final grouped =
        (_selected == 'enrollments' && _enrollmentClass == null) ||
        (_selected == 'questions' && _questionExam == null);
    final cols = kind == 'enrollmentSubjects'
        ? <(String, String)>[
            ('Subject', 'subject_code'),
            ('Subject title', 'subject_title'),
            ('Sections enrolled', 'section_summary'),
            ('Teachers handling', 'teacher_summary'),
            ('Students enrolled', 'student_count'),
          ]
        : _selected == 'enrollments' && kind == 'classes'
        ? <(String, String)>[
            ('Section enrolled', 'sections.section_name'),
            ('Teacher handling', 'teachers.full_name'),
            ('Students enrolled', 'student_count'),
          ]
        : _columns(kind);
    final query = _search.text.trim().toLowerCase();
    final rows = _rows
        .where(
          (r) =>
              query.isEmpty ||
              cols.any((c) => _cell(r, c.$2).toLowerCase().contains(query)),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selected == 'enrollments' || _selected == 'questions')
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_enrollmentSubject != null || _questionExam != null)
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _backGroup,
                    icon: const Icon(Icons.arrow_back),
                    label: Text(
                      _enrollmentClass != null
                          ? 'Back to sections'
                          : _selected == 'enrollments'
                          ? 'Back to subjects'
                          : 'Back to exams',
                    ),
                  ),
                Text(
                  _selected == 'enrollments'
                      ? _enrollmentSubject == null
                            ? 'Subjects · Sections enrolled'
                            : '${_value(_enrollmentSubject, 'subject_code')} · ${_enrollmentClass == null ? 'Select a section to view students' : '${_value(_enrollmentClass, 'sections.section_name')} · Enrolled students'}'
                      : _questionExam == null
                      ? 'Select an exam to view its questions'
                      : '${_value(_questionExam, 'exam_title')} · Questions',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        if (_selected == 'reports')
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String>(
                    initialValue: _reportKind,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Report type'),
                    items: const [
                      DropdownMenuItem(
                        value: 'records',
                        child: Text('Attendance records'),
                      ),
                      DropdownMenuItem(
                        value: 'exams',
                        child: Text('Exam sessions'),
                      ),
                      DropdownMenuItem(
                        value: 'attempts',
                        child: Text('Exam results and attempts'),
                      ),
                      DropdownMenuItem(
                        value: 'alerts',
                        child: Text('Exam monitoring incidents'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _reportKind = v;
                        _page = 0;
                        _status = null;
                        _search.clear();
                      });
                      _load();
                    },
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _operation(3),
                  icon: const Icon(Icons.filter_alt_outlined),
                  label: const Text('Attendance report by class'),
                ),
              ],
            ),
          ),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search, size: 19),
                        hintText: 'Search this page…',
                      ),
                    ),
                  ),
                  if ((_selected == 'questions' && _questionExam == null) ||
                      kind == 'attempts') ...[
                    AdminRecordPicker(
                      kind: 'teachers',
                      label: 'Teacher',
                      value: _filterTeacher,
                      enabled: !_loading,
                      onChanged: (v) {
                        setState(() {
                          _filterTeacher = v;
                          _filterExam = null;
                          _page = 0;
                        });
                        _load();
                      },
                    ),
                    AdminRecordPicker(
                      kind: 'subjects',
                      label: 'Subject',
                      value: _filterSubject,
                      enabled: !_loading,
                      onChanged: (v) {
                        setState(() {
                          _filterSubject = v;
                          _filterExam = null;
                          _page = 0;
                        });
                        _load();
                      },
                    ),
                    AdminRecordPicker(
                      kind: 'exams',
                      label: 'Exam',
                      value: _filterExam,
                      teacherId: _filterTeacher?['id'] as String?,
                      subjectId: _filterSubject?['id'] as String?,
                      enabled: !_loading,
                      onChanged: (v) {
                        setState(() {
                          _filterExam = v;
                          _page = 0;
                        });
                        _load();
                      },
                    ),
                    if (_filterTeacher != null ||
                        _filterSubject != null ||
                        _filterExam != null)
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () {
                                setState(() {
                                  _filterTeacher = _filterSubject =
                                      _filterExam = null;
                                  _page = 0;
                                });
                                _load();
                              },
                        child: const Text('Clear exam filters'),
                      ),
                  ],
                  if (_statuses.isNotEmpty)
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('$kind-$_status'),
                        initialValue: _status,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('All statuses'),
                          ),
                          for (final s in _statuses)
                            DropdownMenuItem(
                              value: s,
                              child: Text(s.replaceAll('_', ' ')),
                            ),
                        ],
                        onChanged: (v) {
                          setState(() {
                            _status = v;
                            _page = 0;
                          });
                          _load();
                        },
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range, size: 18),
                    label: Text(
                      _range == null
                          ? 'Date range'
                          : '${_date(_range!.start)} – ${_date(_range!.end)}',
                    ),
                  ),
                  if (_range != null)
                    IconButton(
                      tooltip: 'Clear dates',
                      onPressed: () {
                        setState(() {
                          _range = null;
                          _page = 0;
                        });
                        _load();
                      },
                      icon: const Icon(Icons.close),
                    ),
                  if (kind == 'teachers')
                    FilledButton.icon(
                      onPressed: () => _operation(0),
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text('Create Teacher'),
                    ),
                  if (kind == 'subjects')
                    FilledButton.icon(
                      onPressed: () => _editSubject(),
                      icon: const Icon(Icons.add),
                      label: const Text('Create Subject'),
                    ),
                  if (kind == 'classes' && _selected != 'enrollments')
                    FilledButton.icon(
                      onPressed: () => _operation(1),
                      icon: const Icon(Icons.add),
                      label: const Text('Create Class Section'),
                    ),
                  if (_selected == 'enrollments')
                    FilledButton.icon(
                      onPressed: () => _operation(2),
                      icon: const Icon(Icons.group_add),
                      label: const Text('Manage Enrollments'),
                    ),
                  if (_selected == 'reports')
                    FilledButton.icon(
                      onPressed: _exporting ? null : _export,
                      icon: const Icon(Icons.download),
                      label: Text(_exporting ? 'Exporting…' : 'Export CSV'),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              if (rows.isEmpty && !_loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 45),
                  child: Column(
                    children: [
                      const Icon(Icons.inbox_outlined, size: 38, color: _muted),
                      const SizedBox(height: 12),
                      Text(
                        query.isEmpty
                            ? 'No records found.'
                            : 'No matches on this page.',
                        style: const TextStyle(color: _muted),
                      ),
                    ],
                  ),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    showCheckboxColumn: false,
                    columnSpacing: 25,
                    headingRowHeight: 42,
                    dataRowMinHeight: 52,
                    dataRowMaxHeight: 76,
                    columns: [
                      for (final c in cols)
                        DataColumn(label: Text(c.$1.toUpperCase())),
                      const DataColumn(label: Text('ACTIONS')),
                    ],
                    rows: [
                      for (final r in rows)
                        DataRow(
                          onSelectChanged: grouped
                              ? (_) => _openGroup(r)
                              : null,
                          cells: [
                            for (final c in cols)
                              DataCell(
                                c.$2 == 'status' || c.$2 == 'is_active'
                                    ? _badge(_cell(r, c.$2))
                                    : ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: c.$2 == 'question_text'
                                              ? 300
                                              : 210,
                                        ),
                                        child: Text(
                                          _cell(r, c.$2),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                              ),
                            DataCell(
                              Wrap(
                                spacing: 4,
                                children: [
                                  IconButton(
                                    tooltip: 'View details',
                                    onPressed: () => grouped
                                        ? _openGroup(r)
                                        : _details(kind, r),
                                    icon: const Icon(
                                      Icons.visibility_outlined,
                                      size: 18,
                                    ),
                                  ),
                                  if ([
                                    'students',
                                    'teachers',
                                    'admins',
                                  ].contains(kind))
                                    IconButton(
                                      tooltip: 'Edit name',
                                      onPressed: () => _editName(kind, r),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                      ),
                                    ),
                                  if (kind == 'subjects')
                                    IconButton(
                                      tooltip: 'Edit subject',
                                      onPressed: () => _editSubject(r),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                      ),
                                    ),
                                  if (kind == 'classes' &&
                                      _selected != 'enrollments')
                                    IconButton(
                                      tooltip: 'Edit class',
                                      onPressed: () => _editClass(r),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                      ),
                                    ),
                                  if (kind == 'enrollments')
                                    IconButton(
                                      tooltip: 'Remove enrollment',
                                      onPressed: () => _removeEnrollment(r),
                                      icon: const Icon(
                                        Icons.person_remove_outlined,
                                        size: 18,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(
                    'Page ${_page + 1} · ${rows.length} shown · 25 records per page',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _page == 0 || _loading
                            ? null
                            : () {
                                setState(() => _page--);
                                _load();
                              },
                        child: const Text('Previous'),
                      ),
                      OutlinedButton(
                        onPressed: _rows.length < 25 || _loading
                            ? null
                            : () {
                                setState(() => _page++);
                                _load();
                              },
                        child: const Text('Next'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range,
    );
    if (range == null || !mounted) return;
    setState(() {
      _range = range;
      _page = 0;
    });
    await _load();
  }

  Future<void> _operation(int section) async {
    if (section == 1 || section == 2) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
          child: SizedBox(
            width: 650,
            height: MediaQuery.sizeOf(context).height * .85,
            child: AdminClassForm(enrollment: section == 2),
          ),
        ),
      );
      if (mounted) await _load();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialog) => Dialog(
        child: SizedBox(
          width: 900,
          height: MediaQuery.sizeOf(context).height * .85,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(dialog),
                  icon: const Icon(Icons.close),
                ),
              ),
              Expanded(child: AdminOperationsPanel(section: section)),
            ],
          ),
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _form(
    String title,
    List<Widget> fields,
    Future<void> Function() save,
  ) async {
    bool saving = false;
    String? error;
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...fields,
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialog(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await save();
                        if (dialog.mounted) Navigator.pop(dialog);
                        if (mounted) await _load();
                      } catch (e) {
                        if (dialog.mounted) {
                          setDialog(() {
                            saving = false;
                            error = e.toString();
                          });
                        }
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
    await Navigator.of(context).push(route);
    await route.completed;
  }

  Widget _field(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
    ),
  );
  Future<void> _editName(String kind, AdminRow row) async {
    final name = TextEditingController(
      text: _value(row, 'full_name', fallback: ''),
    );
    await _form('Edit name', [_field(name, 'Full name')], () async {
      if (name.text.trim().isEmpty) throw Exception('Enter a full name.');
      await _db.updateDisplayName(
        role: kind == 'admins'
            ? 'admin'
            : kind == 'teachers'
            ? 'teacher'
            : 'student',
        linkedId: '${row['id']}',
        fullName: name.text,
      );
    });
    name.dispose();
  }

  Future<void> _editSubject([AdminRow? row]) async {
    final code = TextEditingController(
      text: row == null ? '' : _value(row, 'subject_code', fallback: ''),
    );
    final title = TextEditingController(
      text: row == null ? '' : _value(row, 'subject_title', fallback: ''),
    );
    await _form(
      row == null ? 'Create Subject' : 'Edit Subject',
      [_field(code, 'Subject code'), _field(title, 'Subject title')],
      () async {
        if (code.text.trim().isEmpty || title.text.trim().isEmpty) {
          throw Exception('Enter both code and title.');
        }
        await _data.saveSubject(
          id: row?['id'] as String?,
          code: code.text,
          title: title.text,
        );
      },
    );
    code.dispose();
    title.dispose();
  }

  Future<void> _editClass(AdminRow row) async {
    try {
      final teachers = await _db.getAllTeachers();
      if (!mounted) return;
      String teacherId = '${row['teacher_id']}';
      bool active = row['is_active'] == true;
      final uuid = TextEditingController(
        text: _value(row, 'beacon_uuid', fallback: ''),
      );
      final name = TextEditingController(
        text: _value(row, 'beacon_name', fallback: ''),
      );
      await _form(
        'Edit Class Section',
        [
          DropdownButtonFormField<String>(
            initialValue: teachers.any((t) => t.id == teacherId)
                ? teacherId
                : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Teacher'),
            items: teachers
                .map(
                  (t) => DropdownMenuItem(
                    value: t.id,
                    child: Text(
                      t.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) teacherId = v;
            },
          ),
          const SizedBox(height: 12),
          _field(uuid, 'Beacon UUID'),
          _field(name, 'Beacon name'),
          StatefulBuilder(
            builder: (_, setField) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Class active'),
              subtitle: const Text(
                'Inactive classes are hidden from student and teacher dashboards.',
              ),
              value: active,
              onChanged: (v) => setField(() => active = v),
            ),
          ),
        ],
        () async {
          if (!RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
          ).hasMatch(uuid.text.trim())) {
            throw Exception('Enter a valid beacon UUID.');
          }
          await _data.saveClass(
            '${row['id']}',
            teacherId: teacherId,
            beaconUuid: uuid.text,
            beaconName: name.text,
            active: active,
          );
        },
      );
      uuid.dispose();
      name.dispose();
    } catch (e) {
      _toast('Could not edit class: $e');
    }
  }

  Future<void> _removeEnrollment(AdminRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove enrollment?'),
        content: Text(
          'Remove ${_value(row, 'students.full_name')} from this class? Existing attendance and exam records remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _db.removeEnrollment(
        studentId: '${row['student_id']}',
        offeringId: '${row['subject_offering_id']}',
      );
      if (mounted) await _load();
    } catch (e) {
      _toast('Could not remove enrollment: $e');
    }
  }

  Future<void> _details(String kind, AdminRow row) async {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 850,
          height: MediaQuery.sizeOf(context).height * .82,
          child: _AdminDetails(kind: kind, row: row, data: _data),
        ),
      ),
    );
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    final kind = _kind;
    final status = _status;
    final range = _range;
    final query = _search.text.trim().toLowerCase();
    try {
      final all = <AdminRow>[];
      int page = 0;
      while (true) {
        final rows = await _data.page(
          kind,
          page: page++,
          size: 500,
          status: status,
          from: range?.start,
          to: range?.end.add(const Duration(days: 1)),
        );
        all.addAll(rows);
        if (rows.length < 500) break;
      }
      final cols = _columns(kind);
      String escape(String text) {
        if (RegExp(r'^[\s]*[=+@-]').hasMatch(text)) text = "'$text";
        return '"${text.replaceAll('"', '""')}"';
      }

      final rows = all.where(
        (r) =>
            query.isEmpty ||
            cols.any((c) => _cell(r, c.$2).toLowerCase().contains(query)),
      );
      final csv = [
        cols.map((c) => escape(c.$1)).join(','),
        ...rows.map((r) => cols.map((c) => escape(_cell(r, c.$2))).join(',')),
      ].join('\r\n');
      await downloadAdminCsv(
        'proxamity-$kind-${DateTime.now().millisecondsSinceEpoch}.csv',
        csv,
      );
      _toast('Report downloaded.');
    } catch (e) {
      _toast('Could not export report: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _settings() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Display preferences',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Saved for this browser. Beacon settings are under Class Sections; exam thresholds remain in teacher exam settings.',
          style: TextStyle(color: _muted),
        ),
        const SizedBox(height: 20),
        _field(_school, 'School name'),
        _field(_year, 'School year'),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () async {
              if (_school.text.trim().isEmpty || _year.text.trim().isEmpty) {
                _toast('Enter school name and year.');
                return;
              }
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('admin_school_name', _school.text.trim());
              await prefs.setString('admin_school_year', _year.text.trim());
              if (mounted) setState(() {});
              _toast('Display preferences saved.');
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save preferences'),
          ),
        ),
      ],
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.values, this.colors);
  final List<double> values;
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: math.min(size.width, size.height) / 2 - 15,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = _border);
    if (total == 0) return;
    double angle = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      canvas.drawArc(
        rect,
        angle,
        sweep,
        false,
        paint..color = colors[i % colors.length],
      );
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.values != values;
}

class _AdminDetails extends StatefulWidget {
  const _AdminDetails({
    required this.kind,
    required this.row,
    required this.data,
  });
  final String kind;
  final AdminRow row;
  final AdminDataService data;
  @override
  State<_AdminDetails> createState() => _AdminDetailsState();
}

class _AdminDetailsState extends State<_AdminDetails> {
  bool _loading = true;
  String? _error;
  int _page = 0;
  int _request = 0;
  List<AdminRow> _related = [];
  String _relatedKind = '', _caption = 'Related records';
  String? _filterColumn;
  @override
  void initState() {
    super.initState();
    _configure();
    _load();
  }

  void _configure() {
    switch (widget.kind) {
      case 'students':
        _relatedKind = 'enrollments';
        _filterColumn = 'student_id';
        _caption = 'Class enrollments';
      case 'teachers':
        _relatedKind = 'classes';
        _filterColumn = 'teacher_id';
        _caption = 'Assigned classes';
      case 'subjects':
        _relatedKind = 'classes';
        _filterColumn = 'subject_id';
        _caption = 'Subject classes';
      case 'classes':
        _relatedKind = 'enrollments';
        _filterColumn = 'subject_offering_id';
        _caption = 'Enrolled students';
      case 'exams':
        _relatedKind = 'attempts';
        _filterColumn = 'exam_session_id';
        _caption = 'Student attempts';
      case 'questions':
        _relatedKind = 'choices';
        _caption = 'Answer choices';
      case 'attempts':
        _relatedKind = 'monitoring';
        _caption = 'Bluetooth monitoring history';
      case 'sessions':
        _relatedKind = 'records';
        _filterColumn = 'attendance_session_id';
        _caption = 'Attendance records';
      default:
        _relatedKind = '';
    }
  }

  void _selectRelated(String kind) {
    setState(() {
      _relatedKind = kind;
      _page = 0;
      _related = [];
      _filterColumn = widget.kind == 'students'
          ? 'student_id'
          : widget.kind == 'teachers'
          ? 'teacher_id'
          : 'exam_session_id';
      _caption = switch (kind) {
        'enrollments' => 'Class enrollments',
        'records' => 'Attendance history',
        'attempts' => 'Student attempts',
        'classes' => 'Assigned classes',
        'exams' => 'Exams created',
        'questions' => 'Exam questions',
        'alerts' => 'Monitoring incidents',
        _ => 'Related records',
      };
    });
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      List<AdminRow> rows = [];
      if (_relatedKind == 'monitoring') {
        rows = await widget.data.monitoring('${widget.row['id']}', page: _page);
      } else if (_relatedKind == 'choices') {
        final questions = await ExamService().getExamQuestionsWithChoices(
          '${widget.row['exam_session_id']}',
          includeCorrectFlags: true,
        );
        final matching = questions.where((q) => q.id == widget.row['id']);
        if (matching.isNotEmpty) {
          rows = matching.first.choices
              .map((c) => {'choice': c.choiceText, 'correct': c.isCorrect})
              .toList();
        }
      } else if (_relatedKind.isNotEmpty) {
        rows = await widget.data.page(
          _relatedKind,
          page: _page,
          filterColumn: _filterColumn,
          filterValue: '${widget.row['id']}',
        );
      }
      if (mounted && request == _request) setState(() => _related = rows);
    } catch (e) {
      if (mounted && request == _request) {
        setState(() => _error = 'Could not load related records: $e');
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 10, 10),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Record details',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Close details',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            if (['students', 'teachers', 'exams'].contains(widget.kind)) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry
                      in widget.kind == 'students'
                          ? [
                              ('enrollments', 'Enrollments'),
                              ('records', 'Attendance'),
                              ('attempts', 'Exam attempts'),
                            ]
                          : widget.kind == 'teachers'
                          ? [('classes', 'Classes'), ('exams', 'Exams')]
                          : [
                              ('attempts', 'Attempts'),
                              ('questions', 'Questions'),
                              ('alerts', 'Incidents'),
                            ])
                    ChoiceChip(
                      label: Text(entry.$2),
                      selected: _relatedKind == entry.$1,
                      onSelected: (_) => _selectRelated(entry.$1),
                    ),
                ],
              ),
              const SizedBox(height: 18),
            ],
            for (final c in _columns(widget.kind))
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.$1,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(_cell(widget.row, c.$2)),
                  ],
                ),
              ),
            if (widget.kind == 'classes') ...[
              const Text(
                'Beacon UUID',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              SelectableText(_value(widget.row, 'beacon_uuid')),
            ],
            if (_relatedKind.isNotEmpty) ...[
              const Divider(),
              Text(
                _caption,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null) ...[
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
              if (!_loading && _error == null && _related.isEmpty)
                const Text('No related records found.'),
              for (final r in _related)
                Card(
                  child: ListTile(
                    title: Text(
                      _relatedKind == 'monitoring'
                          ? (r['is_in_range'] == true
                                ? 'In range'
                                : 'Out of range')
                          : _relatedKind == 'choices'
                          ? '${r['choice']}'
                          : _value(
                              r,
                              'students.full_name',
                              fallback: _value(
                                r,
                                'exam_sessions.exam_title',
                                fallback: _value(r, 'subjects.subject_code'),
                              ),
                            ),
                    ),
                    subtitle: Text(
                      _relatedKind == 'monitoring'
                          ? '${_date(r['created_at'], time: true)} · RSSI ${r['rssi'] ?? '—'}'
                          : _relatedKind == 'choices'
                          ? (r['correct'] == true
                                ? 'Correct answer'
                                : 'Answer option')
                          : _value(
                              r,
                              'status',
                              fallback: _value(
                                r,
                                'subject_offerings.subjects.subject_code',
                                fallback: _value(r, 'sections.section_name'),
                              ),
                            ),
                    ),
                    onTap: !['choices', 'monitoring'].contains(_relatedKind)
                        ? () => showDialog<void>(
                            context: context,
                            builder: (_) => Dialog(
                              child: SizedBox(
                                width: 800,
                                height: MediaQuery.sizeOf(context).height * .8,
                                child: _AdminDetails(
                                  kind: _relatedKind,
                                  row: r,
                                  data: widget.data,
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              if (_relatedKind != 'choices')
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _page == 0 || _loading
                          ? null
                          : () {
                              setState(() => _page--);
                              _load();
                            },
                      child: const Text('Previous'),
                    ),
                    TextButton(
                      onPressed: _related.length < 25 || _loading
                          ? null
                          : () {
                              setState(() => _page++);
                              _load();
                            },
                      child: const Text('Next'),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    ],
  );
}
