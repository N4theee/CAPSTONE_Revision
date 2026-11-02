import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/admin_data_service.dart';
import '../services/section_enrollment_service.dart';
import 'admin_record_picker.dart';

String _nested(AdminRow row, String relation, String field) =>
    '${(row[relation] as Map?)?[field] ?? '—'}';

String _requestPlacementLabel(AdminRow row) {
  final placements =
      ((row['students'] as Map?)?['school_section_placements'] as List? ?? [])
          .cast<Map>();
  if (placements.isEmpty) return 'Awaiting placement';
  placements.sort(
    (a, b) => '${b['school_year']}'.compareTo('${a['school_year']}'),
  );
  final p = placements.first;
  return 'Assigned: ${((p['school_sections'] as Map?)?['sections'] as Map?)?['section_name'] ?? p['school_year']}';
}

/// Owns section placement only. Attendance/exam screens keep their offering IDs.
class AdminSectionEnrollment extends StatefulWidget {
  const AdminSectionEnrollment({
    super.key,
    this.adminUsername = '',
    this.readOnly = false,
    this.onLegacyClasses,
  });
  final VoidCallback? onLegacyClasses;
  final String adminUsername;
  final bool readOnly;
  @override
  State<AdminSectionEnrollment> createState() => _AdminSectionEnrollmentState();
}

class _AdminSectionEnrollmentState extends State<AdminSectionEnrollment> {
  final _service = SectionEnrollmentService();
  List<AdminRow> _rows = [],
      _subjects = [],
      _terms = [],
      _assignments = [],
      _students = [];
  AdminRow? _section, _curriculum, _term;
  AdminRow? _pendingEnrollment;
  int _tab = 0, _page = 0, _studentPage = 0, _request = 0;
  bool _busy = false;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_section != null) {
        final results = await Future.wait([
          _service.terms('${_section!['id']}'),
          _service.roster('${_section!['id']}', page: _studentPage),
        ]);
        if (!mounted || request != _request) return;
        _terms = results[0];
        _students = results[1];
        _term =
            _terms.where((t) => t['id'] == _term?['id']).firstOrNull ??
            _terms.firstOrNull;
        if (_term != null) {
          final data = await Future.wait([
            _service.curriculumSubjects('${_term!['curriculum_id']}'),
            _service.assignments('${_term!['id']}'),
          ]);
          if (!mounted || request != _request) return;
          _subjects = data[0]
              .where(
                (s) =>
                    s['semester'] == _term!['semester'] || s['semester'] == 0,
              )
              .toList();
          _assignments = data[1];
        } else {
          _subjects = [];
          _assignments = [];
        }
      } else if (_curriculum != null) {
        final subjects = await _service.curriculumSubjects(
          '${_curriculum!['id']}',
        );
        if (!mounted || request != _request) return;
        _subjects = subjects;
      } else {
        final rows = await (_tab == 0
            ? _service.sections(page: _page, search: _search)
            : _tab == 1
            ? _service.curricula(page: _page)
            : _service.requests(page: _page));
        if (!mounted || request != _request) return;
        _rows = rows;
      }
    } catch (e) {
      if (mounted && request == _request) {
        _error =
            e is PostgrestException &&
                (e.code == '42P01' || e.code == 'PGRST205')
            ? 'Section enrollment setup is missing. Apply section_enrollment.sql and section_curriculum_drafts.sql in Supabase.'
            : 'Could not load section enrollment. $e';
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<bool> _command(String action, AdminRow data) async {
    if (widget.readOnly) return false;
    final username = TextEditingController(text: widget.adminUsername);
    final password = TextEditingController();
    final credentials = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm administrator access'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Your administrator credentials authorize this section change.',
              ),
              TextField(
                controller: username,
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                  labelText: 'Admin username',
                ),
              ),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                  labelText: 'Admin password',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, (username.text.trim(), password.text)),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    // Controllers are released after the dialog's closing transition.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    username.dispose();
    password.dispose();
    if (credentials == null || !mounted) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.command(
        action,
        data,
        username: credentials.$1,
        password: credentials.$2,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved.')));
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is PostgrestException
              ? e.message
              : 'Could not save. Please retry.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<AdminRow?> _pickCurriculum({AdminRow? section}) async {
    return showDialog<AdminRow>(
      context: context,
      builder: (_) => _SchoolChoiceDialog(
        title: 'Select approved curriculum',
        load: (page) => _service.curricula(
          page: page,
          grade: section?['grade'] as int?,
          program: section?['program'] as String?,
          approved: true,
        ),
        label: (r) => 'Grade ${r['grade']} ${r['program']} · ${r['version']}',
      ),
    );
  }

  Future<void> _createSection() async {
    final name = TextEditingController();
    final year = TextEditingController(
      text: '${DateTime.now().year}-${DateTime.now().year + 1}',
    );
    final capacity = TextEditingController(text: '45');
    int grade = 11;
    String program = 'ICT';
    AdminRow? adviser;
    final data = await showDialog<AdminRow>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Create section'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 18),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Section name (e.g. ICT 11-A)',
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: year,
                    decoration: const InputDecoration(
                      labelText: 'School year (2026-2027)',
                    ),
                  ),
                  const SizedBox(height: 18),
                  _gradeDropdown(grade, (v) => update(() => grade = v)),
                  const SizedBox(height: 18),
                  _programDropdown(program, (v) => update(() => program = v)),
                  const SizedBox(height: 18),
                  TextField(
                    controller: capacity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Maximum students',
                    ),
                  ),
                  const SizedBox(height: 12),
                  AdminRecordPicker(
                    kind: 'teachers',
                    label: 'Section adviser (optional)',
                    value: adviser,
                    onChanged: (v) => update(() => adviser = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, {
                'name': name.text.trim(),
                'school_year': year.text.trim(),
                'grade': grade,
                'program': program,
                'capacity': int.tryParse(capacity.text) ?? 0,
                'adviser_id': adviser?['id'],
              }),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    name.dispose();
    year.dispose();
    capacity.dispose();
    if (data != null && await _command('create_section', data)) await _load();
  }

  Future<void> _createCurriculum({AdminRow? copy}) async {
    final version = TextEditingController();
    int grade = copy?['grade'] as int? ?? 11;
    String program = copy?['program'] as String? ?? 'ICT';
    final data = await showDialog<AdminRow>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(
            copy == null
                ? 'New curriculum draft'
                : 'Copy curriculum to a new draft',
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: version,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    labelText: 'Version name',
                  ),
                ),
                _gradeDropdown(grade, (v) => update(() => grade = v)),
                _programDropdown(program, (v) => update(() => program = v)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, {
                'version': version.text.trim(),
                'grade': grade,
                'program': program,
                'copy_id': copy?['id'],
              }),
              child: const Text('Create draft'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    version.dispose();
    if (data != null && await _command('create_curriculum', data)) {
      if (!mounted) return;
      setState(() {
        _curriculum = null;
        _page = 0;
      });
      await _load();
    }
  }

  Future<void> _addTerm() async {
    final curriculum = await _pickCurriculum(section: _section);
    if (curriculum == null || !mounted) return;
    final semester = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose semester'),
        children: [
          for (final n in [1, 2])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, n),
              child: Text('Semester $n'),
            ),
        ],
      ),
    );
    if (semester != null &&
        await _command('create_term', {
          'section_id': _section!['id'],
          'curriculum_id': curriculum['id'],
          'semester': semester,
        })) {
      await _load();
    }
  }

  Future<void> _enroll({AdminRow? student}) async {
    final data = await showDialog<AdminRow>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 700,
          height: MediaQuery.sizeOf(context).height * .85,
          child: _SectionPlacementForm(
            service: _service,
            initialSection: _section,
            initialStudent: student,
          ),
        ),
      ),
    );
    if (data != null) {
      _pendingEnrollment = data;
      if (await _command('enroll', data)) {
        _pendingEnrollment = null;
        await _load();
      }
    }
  }

  Future<void> _addSubject() async {
    AdminRow? subject;
    final picked = await showDialog<AdminRow>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Add curriculum subject'),
          content: AdminRecordPicker(
            kind: 'subjects',
            label: 'Subject',
            value: subject,
            onChanged: (v) => update(() => subject = v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: subject == null
                  ? null
                  : () => Navigator.pop(ctx, subject),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (picked != null &&
        await _command('curriculum_subject', {
          'curriculum_id': _curriculum!['id'],
          'subject_id': picked['id'],
          'semester': null,
          'add': true,
        })) {
      await _load();
    }
  }

  Widget _curriculumView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Grade ${_curriculum!['grade']} ${_curriculum!['program']} · ${_curriculum!['version']}',
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      Text(
        _curriculum!['approved'] == true
            ? 'Approved curriculum · Create a new version to make changes.'
            : 'Draft only. Confirm subjects and semesters with the school before approval. Full year includes both semesters.',
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          if (_curriculum!['approved'] != true)
            FilledButton(
              onPressed: _busy ? null : _addSubject,
              child: const Text('Add subject'),
            ),
          if (_curriculum!['approved'] != true)
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () async {
                      if (await _command('approve_curriculum', {
                        'id': _curriculum!['id'],
                      })) {
                        _curriculum!['approved'] = true;
                        await _load();
                      }
                    },
              child: const Text('Approve curriculum'),
            ),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _createCurriculum(copy: _curriculum),
            child: const Text('Copy to new version'),
          ),
        ],
      ),
      for (final s in _subjects)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_nested(s, 'subjects', 'subject_title')),
                DropdownButtonFormField<int>(
                  key: ValueKey('${s['subject_id']}-${s['semester']}'),
                  initialValue: s['semester'] as int?,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    labelText: 'Semester',
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Unconfirmed')),
                    DropdownMenuItem(value: 1, child: Text('Semester 1')),
                    DropdownMenuItem(value: 2, child: Text('Semester 2')),
                    DropdownMenuItem(value: 0, child: Text('Full year')),
                  ],
                  onChanged: _busy || _curriculum!['approved'] == true
                      ? null
                      : (v) async {
                          if (await _command('curriculum_subject', {
                            'curriculum_id': _curriculum!['id'],
                            'subject_id': s['subject_id'],
                            'semester': v,
                          })) {
                            await _load();
                          }
                        },
                ),
                if (_curriculum!['approved'] != true)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            if (await _command('remove_curriculum_subject', {
                              'curriculum_id': _curriculum!['id'],
                              'subject_id': s['subject_id'],
                            })) {
                              await _load();
                            }
                          },
                    child: const Text('Exclude from this curriculum'),
                  ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _sectionView() => DefaultTabController(
    length: 2,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _nested(_section!, 'sections', 'section_name'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(
          'Grade ${_section!['grade']} · ${_section!['program']} · ${_section!['school_year']} · Capacity ${_section!['capacity']}',
        ),
        Text('Adviser: ${_nested(_section!, 'teachers', 'full_name')}'),
        const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'Students'),
            Tab(text: 'Subjects & Teachers'),
          ],
        ),
        SizedBox(
          height: 640,
          child: TabBarView(
            children: [
              ListView(
                children: [
                  if (!widget.readOnly)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: FilledButton.icon(
                        onPressed: _busy ? null : () => _enroll(),
                        icon: const Icon(Icons.group_add),
                        label: const Text(
                          'Enroll students / enroll next semester',
                        ),
                      ),
                    ),
                  const Text(
                    'Students keep one section per school year. Enroll existing members again for a new ready semester; duplicates are prevented.',
                  ),
                  if (_students.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('No students placed in this section.'),
                    ),
                  for (final s in _students)
                    Card(
                      child: ListTile(
                        title: Text(_nested(s, 'students', 'full_name')),
                        subtitle: Text(
                          _nested(s, 'students', 'student_number'),
                        ),
                      ),
                    ),
                  _pager(_studentPage, _students.length, (p) {
                    setState(() => _studentPage = p);
                    _load();
                  }),
                ],
              ),
              ListView(
                children: [
                  if (!widget.readOnly)
                    OutlinedButton(
                      onPressed: _busy ? null : _addTerm,
                      child: const Text('Set up semester'),
                    ),
                  if (_terms.isEmpty)
                    Text(
                      widget.readOnly
                          ? 'No semesters have been set up.'
                          : 'Choose an approved curriculum to set up the first semester.',
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final t in _terms)
                        ChoiceChip(
                          label: Text(
                            'Semester ${t['semester']} · ${t['closed'] == true
                                ? 'Closed'
                                : t['ready'] == true
                                ? 'Ready'
                                : 'Draft'}',
                          ),
                          selected: _term?['id'] == t['id'],
                          onSelected: _busy
                              ? null
                              : (_) {
                                  setState(() => _term = t);
                                  _load();
                                },
                        ),
                    ],
                  ),
                  if (!widget.readOnly &&
                      _term != null &&
                      _term!['ready'] != true)
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              if (await _command('ready_term', {
                                'id': _term!['id'],
                              })) {
                                await _load();
                              }
                            },
                      child: const Text('Make semester ready'),
                    ),
                  if (!widget.readOnly &&
                      _term?['ready'] == true &&
                      _term?['closed'] != true)
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Close this semester?'),
                                  content: const Text(
                                    'Its classes will leave the active dashboards. Attendance, exam and enrollment history will be preserved. Set up the next semester separately.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Close semester'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true &&
                                  await _command('close_term', {
                                    'id': _term!['id'],
                                  })) {
                                await _load();
                              }
                            },
                      child: const Text('Close semester'),
                    ),
                  if (_term?['ready'] == true)
                    const Text(
                      'Ready assignments are frozen to preserve attendance, beacon and exam ownership.',
                    ),
                  for (final s in _subjects)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_nested(s, 'subjects', 'subject_title')),
                            Builder(
                              builder: (context) {
                                final a = _assignments
                                    .where(
                                      (a) => a['subject_id'] == s['subject_id'],
                                    )
                                    .firstOrNull;
                                final offering =
                                    a?['subject_offerings'] as Map?;
                                final teacher = offering?['teachers'] as Map?;
                                if (widget.readOnly) {
                                  return Text(
                                    'Handling teacher: ${teacher?['full_name'] ?? 'Unassigned'}',
                                  );
                                }
                                return AdminRecordPicker(
                                  kind: 'teachers',
                                  label: 'Handling teacher',
                                  value: teacher == null
                                      ? null
                                      : {
                                          'id': offering!['teacher_id'],
                                          'full_name': teacher['full_name'],
                                        },
                                  allowClear: false,
                                  enabled: !_busy && _term?['ready'] != true,
                                  onChanged: (v) async {
                                    if (v != null &&
                                        await _command('assign_teacher', {
                                          'term_id': _term!['id'],
                                          'subject_id': s['subject_id'],
                                          'teacher_id': v['id'],
                                        })) {
                                      await _load();
                                    }
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _directory() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!widget.readOnly)
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            if (_tab == 0)
              FilledButton.icon(
                onPressed: _busy ? null : _createSection,
                icon: const Icon(Icons.add),
                label: const Text('Create section'),
              ),
            if (_tab == 1)
              FilledButton.icon(
                onPressed: _busy ? null : () => _createCurriculum(),
                icon: const Icon(Icons.add),
                label: const Text('New curriculum version'),
              ),
            FilledButton.icon(
              onPressed: _busy ? null : () => _enroll(),
              icon: const Icon(Icons.group_add),
              label: const Text('Enroll students'),
            ),
          ],
        ),
      const SizedBox(height: 12),
      if (_tab == 2)
        const Text(
          'Registration preferences are requests, not approved placement. Review each request before assigning a section.',
        ),
      if (_rows.isEmpty && !_busy)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('No records yet.'),
        ),
      for (final r in _rows)
        Card(
          child: ListTile(
            title: Text(
              _tab == 0
                  ? _nested(r, 'sections', 'section_name')
                  : _tab == 1
                  ? 'Grade ${r['grade']} ${r['program']} · ${r['version']}'
                  : _nested(r, 'students', 'full_name'),
            ),
            subtitle: Text(
              _tab == 0
                  ? 'Grade ${r['grade']} ${r['program']} · ${r['school_year']} · ${SectionEnrollmentService.occupied(r)}/${r['capacity']} seats · Adviser: ${_nested(r, 'teachers', 'full_name')}'
                  : _tab == 1
                  ? r['approved'] == true
                        ? 'Approved'
                        : 'Draft · semester assignments unconfirmed'
                  : 'Requested Grade ${r['requested_grade']} ${r['requested_program']} · ${_requestPlacementLabel(r)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy
                ? null
                : () {
                    if (_tab == 2) {
                      _enroll(
                        student: {
                          'id': r['student_id'],
                          'full_name': _nested(r, 'students', 'full_name'),
                          'requested_grade': r['requested_grade'],
                          'requested_program': r['requested_program'],
                        },
                      );
                      return;
                    }
                    setState(() {
                      if (_tab == 0) {
                        _section = r;
                        _studentPage = 0;
                      } else {
                        _curriculum = r;
                      }
                    });
                    _load();
                  },
          ),
        ),
      _pager(_page, _rows.length, (p) {
        setState(() => _page = p);
        _load();
      }),
    ],
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_section != null || _curriculum != null)
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () {
                      setState(() {
                        _section = _curriculum = _term = null;
                        _subjects = [];
                      });
                      _load();
                    },
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
          if (!widget.readOnly)
            for (final entry in [
              (0, 'Sections'),
              (1, 'Curricula'),
              (2, 'Student requests'),
            ])
              ChoiceChip(
                label: Text(entry.$2),
                selected: _tab == entry.$1,
                onSelected: _busy
                    ? null
                    : (_) {
                        setState(() {
                          _tab = entry.$1;
                          _page = 0;
                          _section = _curriculum = _term = null;
                          _rows = [];
                        });
                        _load();
                      },
              ),
          IconButton(
            onPressed: _busy ? null : _load,
            tooltip: 'Refresh section enrollment',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      if (!widget.readOnly && widget.onLegacyClasses != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.onLegacyClasses,
            icon: const Icon(Icons.history),
            label: const Text('Review legacy subject classes'),
          ),
        ),
      if (widget.readOnly && _section == null) ...[
        const Text(
          'View sections, students, subjects and teachers. Manage changes in Enrollments.',
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search sections',
            hintText: 'Enter section name and press Enter',
            prefixIcon: Icon(Icons.search),
          ),
          onSubmitted: (value) {
            setState(() {
              _search = value.trim();
              _page = 0;
            });
            _load();
          },
        ),
      ],
      const SizedBox(height: 16),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_error!),
                if (_pendingEnrollment != null)
                  TextButton.icon(
                    onPressed: _reviewEnrollments,
                    icon: const Icon(Icons.manage_search),
                    label: const Text(
                      'Review existing enrollments for selected students',
                    ),
                  ),
                if (_pendingEnrollment != null &&
                    !(_error ?? '').contains('conflict'))
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            if (await _command('enroll', _pendingEnrollment!)) {
                              _pendingEnrollment = null;
                              await _load();
                            }
                          },
                    child: Text(
                      'Retry selected batch (${(_pendingEnrollment!['student_ids'] as List).length} students)',
                    ),
                  ),
                TextButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      if (!_busy || _rows.isNotEmpty || _section != null || _curriculum != null)
        (_section != null
            ? _sectionView()
            : _curriculum != null
            ? _curriculumView()
            : _directory()),
    ],
  );

  Future<void> _reviewEnrollments() async {
    final ids =
        (_pendingEnrollment?['student_ids'] as List?)?.cast<String>() ?? [];
    if (ids.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Existing student enrollments'),
        content: SizedBox(
          width: 640,
          height: 400,
          child: FutureBuilder<List<AdminRow>>(
            future: _service.existingEnrollments(ids),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Could not load enrollments: ${snapshot.error}');
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(
                children: [
                  const Text(
                    'Placement is blocked when an active class belongs to a different section in the same school year, or has no school year. Review these assignments before changing placement. Existing attendance and exam history is preserved.',
                  ),
                  const SizedBox(height: 16),
                  for (final row in snapshot.data!)
                    ListTile(
                      title: Text(_nested(row, 'students', 'full_name')),
                      subtitle: Text(
                        '${((row['subject_offerings'] as Map?)?['subjects'] as Map?)?['subject_code']} · ${((row['subject_offerings'] as Map?)?['sections'] as Map?)?['section_name']}\n${((row['subject_offerings'] as Map?)?['teachers'] as Map?)?['full_name']} · ${(row['subject_offerings'] as Map?)?['school_year'] ?? 'School year not set'} · ${(row['subject_offerings'] as Map?)?['is_active'] == true ? 'Active' : 'Inactive'}',
                      ),
                      isThreeLine: true,
                    ),
                  if (snapshot.data!.isEmpty)
                    const Text('No existing subject enrollments found.'),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _pager(int page, int count, ValueChanged<int> change) => Wrap(
    spacing: 12,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text('Page ${page + 1} · $count shown'),
      OutlinedButton(
        onPressed: _busy || page == 0 ? null : () => change(page - 1),
        child: const Text('Previous'),
      ),
      OutlinedButton(
        onPressed: _busy || count < 25 ? null : () => change(page + 1),
        child: const Text('Next'),
      ),
    ],
  );
}

Widget _gradeDropdown(int grade, ValueChanged<int> change) =>
    DropdownButtonFormField<int>(
      initialValue: grade,
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        labelText: 'Grade level',
      ),
      items: [
        for (final n in [11, 12])
          DropdownMenuItem(value: n, child: Text('Grade $n')),
      ],
      onChanged: (v) {
        if (v != null) change(v);
      },
    );
Widget _programDropdown(String program, ValueChanged<String> change) =>
    DropdownButtonFormField<String>(
      initialValue: program,
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        labelText: 'Program / strand',
      ),
      items: [
        for (final p in schoolPrograms)
          DropdownMenuItem(value: p, child: Text(p)),
      ],
      onChanged: (v) {
        if (v != null) change(v);
      },
    );

class _SchoolChoiceDialog extends StatefulWidget {
  const _SchoolChoiceDialog({
    required this.title,
    required this.load,
    required this.label,
  });
  final String title;
  final Future<List<AdminRow>> Function(int) load;
  final String Function(AdminRow) label;
  @override
  State<_SchoolChoiceDialog> createState() => _SchoolChoiceDialogState();
}

class _SchoolChoiceDialogState extends State<_SchoolChoiceDialog> {
  int _page = 0;
  bool _busy = true;
  List<AdminRow> _rows = [];
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.load(_page);
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load choices: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 500,
      height: 360,
      child: _busy
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Column(
              children: [
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            )
          : ListView(
              children: [
                if (_rows.isEmpty) const Text('No matching records.'),
                for (final r in _rows)
                  ListTile(
                    title: Text(widget.label(r)),
                    onTap: () => Navigator.pop(context, r),
                  ),
              ],
            ),
    ),
    actions: [
      TextButton(
        onPressed: _busy || _page == 0
            ? null
            : () {
                _page--;
                _load();
              },
        child: const Text('Previous'),
      ),
      TextButton(
        onPressed: _busy || _rows.length < 25
            ? null
            : () {
                _page++;
                _load();
              },
        child: const Text('Next'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}

class _SectionPlacementForm extends StatefulWidget {
  const _SectionPlacementForm({
    required this.service,
    this.initialSection,
    this.initialStudent,
  });
  final SectionEnrollmentService service;
  final AdminRow? initialSection, initialStudent;
  @override
  State<_SectionPlacementForm> createState() => _SectionPlacementFormState();
}

class _SectionPlacementFormState extends State<_SectionPlacementForm> {
  final _year = TextEditingController();
  int _grade = 11;
  String _program = 'ICT';
  AdminRow? _section, _term;
  List<AdminRow> _terms = [], _assignments = [];
  final List<AdminRow> _students = [];
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _year.text =
        widget.initialSection?['school_year'] as String? ??
        '${DateTime.now().year}-${DateTime.now().year + 1}';
    _grade =
        (widget.initialSection?['grade'] ??
                widget.initialStudent?['requested_grade'] ??
                11)
            as int;
    _program =
        (widget.initialSection?['program'] ??
                widget.initialStudent?['requested_program'] ??
                'ICT')
            as String;
    if (widget.initialStudent != null) _students.add(widget.initialStudent!);
    if (widget.initialSection != null) _selectSection(widget.initialSection!);
  }

  @override
  void dispose() {
    _year.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _section = _term = null;
      _terms = [];
      _assignments = [];
    });
  }

  Future<void> _selectSection(AdminRow section) async {
    setState(() {
      _busy = true;
      _error = null;
      _section = section;
      _term = null;
      _assignments = [];
    });
    try {
      final terms = await widget.service.terms('${section['id']}');
      if (!mounted) return;
      setState(
        () => _terms = terms
            .where((t) => t['ready'] == true && t['closed'] != true)
            .toList(),
      );
      if (_terms.isNotEmpty) await _selectTerm(_terms.first);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load section: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectTerm(AdminRow term) async {
    setState(() {
      _busy = true;
      _error = null;
      _term = term;
      _assignments = [];
    });
    try {
      final rows = await widget.service.assignments('${term['id']}');
      if (mounted) setState(() => _assignments = rows);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load subjects: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Section enrollment')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Choose a school year, grade, program and section. Review the semester subjects and teachers before confirming.',
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _year,
          enabled: !_busy,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            labelText: 'School year',
          ),
          onChanged: (_) => _reset(),
        ),
        const SizedBox(height: 18),
        IgnorePointer(
          ignoring: _busy,
          child: _gradeDropdown(_grade, (v) {
            _grade = v;
            _reset();
          }),
        ),
        const SizedBox(height: 18),
        IgnorePointer(
          ignoring: _busy,
          child: _programDropdown(_program, (v) {
            _program = v;
            _reset();
          }),
        ),
        const SizedBox(height: 18),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () async {
                  final picked = await showDialog<AdminRow>(
                    context: context,
                    builder: (_) => _SchoolChoiceDialog(
                      title: 'Choose section',
                      load: (p) => widget.service.sections(
                        page: p,
                        year: _year.text.trim(),
                        grade: _grade,
                        program: _program,
                      ),
                      label: (r) =>
                          '${_nested(r, 'sections', 'section_name')} · ${SectionEnrollmentService.occupied(r)}/${r['capacity']} seats',
                    ),
                  );
                  if (picked != null) await _selectSection(picked);
                },
          child: Text(
            _section == null
                ? 'Select section'
                : _nested(_section!, 'sections', 'section_name'),
          ),
        ),
        if (_section != null)
          Text(
            '${SectionEnrollmentService.occupied(_section!)}/${_section!['capacity']} seats occupied · Final availability is checked on confirmation.',
          ),
        if (_section != null && _terms.isEmpty && !_busy)
          const Text(
            'No ready semester. Assign teachers and make a semester ready first.',
          ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in _terms)
              ChoiceChip(
                label: Text('Semester ${t['semester']}'),
                selected: _term?['id'] == t['id'],
                onSelected: _busy ? null : (_) => _selectTerm(t),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 18),
        AdminRecordPicker(
          kind: 'students',
          label: 'Student (add to selection)',
          value: null,
          enabled: !_busy,
          onChanged: (r) {
            if (r != null && !_students.any((s) => s['id'] == r['id'])) {
              setState(() => _students.add(r));
            }
          },
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _students)
              InputChip(
                label: Text('${s['full_name']}'),
                onDeleted: _busy
                    ? null
                    : () => setState(() => _students.remove(s)),
              ),
          ],
        ),
        if (_term != null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Subjects & Teachers',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        for (final a in _assignments)
          ListTile(
            title: Text(
              '${((a['subject_offerings'] as Map?)?['subjects'] as Map?)?['subject_title'] ?? '—'}',
            ),
            subtitle: Text(
              '${((a['subject_offerings'] as Map?)?['teachers'] as Map?)?['full_name'] ?? 'Unassigned'}',
            ),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed:
                _busy ||
                    _error != null ||
                    _term == null ||
                    _students.isEmpty ||
                    _assignments.isEmpty
                ? null
                : () => Navigator.pop(context, {
                    'term_id': _term!['id'],
                    'student_ids': _students.map((s) => s['id']).toList(),
                  }),
            child: Text(
              'Confirm enrollment for ${_students.length} student(s)',
            ),
          ),
        ),
      ],
    ),
  );
}
