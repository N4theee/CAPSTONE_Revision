import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../services/supabase_service.dart';

class AdminWebPanelScreen extends StatefulWidget {
  const AdminWebPanelScreen({super.key});

  @override
  State<AdminWebPanelScreen> createState() => _AdminWebPanelScreenState();
}

class _AdminWebPanelScreenState extends State<AdminWebPanelScreen> {
  final _db = SupabaseService();
  final _nameCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _maxStudentsCtrl = TextEditingController(text: '30');
  final _subjectCodeCtrl = TextEditingController();
  final _subjectTitleCtrl = TextEditingController();
  final _sectionCtrl = TextEditingController();
  final _beaconNameCtrl = TextEditingController();
  bool _loading = false;
  bool _creatingOffering = false;
  bool _enrolling = false;
  bool _loadingLists = true;
  bool _loadingReport = false;
  List<StudentBasic> _students = [];
  List<ProfessorBasic> _professors = [];
  List<SubjectOffering> _offerings = [];
  List<EnrollmentRecord> _enrollments = [];
  List<AdminAttendanceReportItem> _reportRows = [];
  DateTimeRange? _reportRange;
  String? _reportProfessorId;
  String? _reportSubjectCode;
  String? _reportSection;
  String? _selectedOfferingProfessorId;
  String? _selectedBeaconUuid;
  List<String> _beaconUuidOptions = [];
  String? _selectedStudentId;
  String? _selectedProfessorId;
  String? _selectedSubjectCode;
  String? _selectedSection;
  String? _selectedOfferingId;
  String? _selectedEnrollmentKey;

  // Calm slate + violet accent; body text kept light for readability.
  static const _bg = Color(0xFF0F172A);
  static const _card = Color(0xFF1E293B);
  static const _accent = Color(0xFF8B5CF6);
  static const _muted = Color(0xFFCBD5E1);
  static const _border = Color(0xFF334155);
  static const _dropdownTextStyle = TextStyle(
    color: Color(0xFFF8FAFC),
    fontSize: 15,
  );

  Text _dropdownLabel(String text) => Text(text, style: _dropdownTextStyle);

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _maxStudentsCtrl.dispose();
    _subjectCodeCtrl.dispose();
    _subjectTitleCtrl.dispose();
    _sectionCtrl.dispose();
    _beaconNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _createProfessor() async {
    setState(() => _loading = true);
    try {
      await _db.createProfessorByAdmin(
        professorId: '',
        fullName: _nameCtrl.text,
        username: _userCtrl.text,
        password: _passCtrl.text,
        maxStudents: int.tryParse(_maxStudentsCtrl.text.trim()) ?? 30,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Professor created successfully.')),
      );
      await _loadLists();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Create failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createOffering() async {
    setState(() => _creatingOffering = true);
    try {
      if (_selectedOfferingProfessorId == null) {
        throw Exception('Please select a professor.');
      }
      if (_selectedBeaconUuid == null || _selectedBeaconUuid!.isEmpty) {
        throw Exception('Please select a beacon UUID.');
      }
      await _db.createSubjectOfferingByAdmin(
        professorId: _selectedOfferingProfessorId!,
        subjectCode: _subjectCodeCtrl.text,
        subjectTitle: _subjectTitleCtrl.text,
        section: _sectionCtrl.text,
        beaconUuid: _selectedBeaconUuid!,
        beaconName: _beaconNameCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Class section created successfully.')),
      );
      await _loadLists();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Create class failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _creatingOffering = false);
    }
  }

  void _regenBeaconUuids() {
    final uuid = const Uuid();
    final next = <String>{};
    while (next.length < 12) {
      next.add(uuid.v4());
    }
    setState(() {
      _beaconUuidOptions = next.toList();
      _beaconUuidOptions.sort();
      _selectedBeaconUuid =
          _beaconUuidOptions.isEmpty ? null : _beaconUuidOptions.first;
    });
  }

  Future<void> _loadLists() async {
    setState(() => _loadingLists = true);
    try {
      final students = await _db.getAllStudents();
      final professors = await _db.getAllProfessors();
      final offerings = await _db.getAllOfferings();
      final enrollments = await _db.getAdminEnrollments();
      if (!mounted) return;
      final selectedProfessorId = professors.any((p) => p.id == _selectedProfessorId)
          ? _selectedProfessorId
          : (professors.isNotEmpty ? professors.first.id : null);
      final offeringsByProfessor = selectedProfessorId == null
          ? <SubjectOffering>[]
          : offerings.where((o) => o.professorId == selectedProfessorId).toList();
      final subjectCodes = offeringsByProfessor
          .map((o) => o.subjectCode)
          .toSet()
          .toList()
        ..sort();
      final selectedSubjectCode = subjectCodes.contains(_selectedSubjectCode)
          ? _selectedSubjectCode
          : (subjectCodes.isNotEmpty ? subjectCodes.first : null);
      final sections = offeringsByProfessor
          .where((o) => o.subjectCode == selectedSubjectCode)
          .map((o) => o.section)
          .toSet()
          .toList()
        ..sort();
      final selectedSection = sections.contains(_selectedSection)
          ? _selectedSection
          : (sections.isNotEmpty ? sections.first : null);
      final selectedOfferingId = offeringsByProfessor
          .where((o) =>
              o.subjectCode == selectedSubjectCode && o.section == selectedSection)
          .map((o) => o.id)
          .cast<String?>()
          .firstWhere((_) => true, orElse: () => null);

      setState(() {
        _students = students;
        _professors = professors;
        _offerings = offerings;
        _enrollments = enrollments;
        _selectedOfferingProfessorId =
            professors.any((p) => p.id == _selectedOfferingProfessorId)
                ? _selectedOfferingProfessorId
                : (professors.isNotEmpty ? professors.first.id : null);
        _selectedStudentId = students.any((s) => s.id == _selectedStudentId)
            ? _selectedStudentId
            : (students.isNotEmpty ? students.first.id : null);
        _selectedProfessorId = selectedProfessorId;
        _selectedSubjectCode = selectedSubjectCode;
        _selectedSection = selectedSection;
        _selectedOfferingId = selectedOfferingId;
      });
      if (_beaconUuidOptions.isEmpty) {
        _regenBeaconUuids();
      }
    } finally {
      if (mounted) setState(() => _loadingLists = false);
    }
  }

  Future<void> _enrollStudent() async {
    if (_selectedStudentId == null || _selectedOfferingId == null) return;
    setState(() => _enrolling = true);
    try {
      await _db.enrollStudentToOffering(
        studentId: _selectedStudentId!,
        offeringId: _selectedOfferingId!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enrollment saved successfully.')),
      );
      await _loadLists();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enrollment failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _enrolling = false);
    }
  }

  Future<void> _removeSelectedEnrollment() async {
    if (_selectedEnrollmentKey == null) return;
    final parts = _selectedEnrollmentKey!.split('|');
    if (parts.length != 2) return;
    setState(() => _enrolling = true);
    try {
      await _db.removeEnrollment(studentId: parts[0], offeringId: parts[1]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enrollment removed.')),
      );
      await _loadLists();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Remove failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _enrolling = false);
    }
  }

  Future<void> _generateReport() async {
    setState(() => _loadingReport = true);
    try {
      final rows = await _db.getAdminAttendanceReport(
        from: _reportRange?.start,
        to: _reportRange?.end,
        professorId: _reportProfessorId,
        subjectCode: _reportSubjectCode,
        section: _reportSection,
      );
      if (!mounted) return;
      setState(() => _reportRows = rows);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report generated: ${rows.length} records')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report generation failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingReport = false);
    }
  }

  Future<void> _pickReportRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _reportRange,
    );
    if (picked == null || !mounted) return;
    setState(() => _reportRange = picked);
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return const Scaffold(
        body: Center(
          child: Text('Admin panel is web-only.'),
        ),
      );
    }
    final theme = Theme.of(context);
    const inputText = Color(0xFFF8FAFC);
    const hint = Color(0xFFCBD5E1);
    const label = Color(0xFFE2E8F0);

    final dark = theme.copyWith(
      scaffoldBackgroundColor: _bg,
      cardColor: _card,
      colorScheme: theme.colorScheme.copyWith(
        surface: _card,
        onSurface: inputText,
        onSurfaceVariant: hint,
      ),
      textTheme: theme.textTheme.apply(
        bodyColor: inputText,
        displayColor: Colors.white,
      ),
      primaryTextTheme: theme.primaryTextTheme.apply(
        bodyColor: inputText,
        displayColor: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.07),
        labelStyle: const TextStyle(
          color: label,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.never,
        hintStyle: const TextStyle(color: hint, fontSize: 15),
        helperStyle: TextStyle(color: _muted.withValues(alpha: 0.95)),
        errorStyle: const TextStyle(color: Color(0xFFFCA5A5)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _accent, width: 1.3),
        ),
        prefixIconColor: hint,
        suffixIconColor: hint,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _card,
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
      dividerTheme: const DividerThemeData(color: _border),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: const TextStyle(color: inputText, fontSize: 15),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(_card),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
    );

    final screenW = MediaQuery.sizeOf(context).width;
    final contentMaxW =
        screenW > 960 ? 900.0 : (screenW - 24).clamp(300.0, 900.0);
    final gutter = ((screenW - contentMaxW) / 2).clamp(12.0, 48.0);

    return Theme(
      data: dark,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          title: const Text('Admin Panel'),
          actions: [
            IconButton(
              tooltip: 'Refresh lists',
              onPressed: _loadingLists ? null : _loadLists,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _bg,
                _bg,
                _accent.withValues(alpha: 0.10),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMaxW),
              child: ListView(
                padding: EdgeInsets.fromLTRB(gutter, 20, gutter, 40),
                children: [
              Card(
                color: _card,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: _border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Create Professor Account',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Professor Full Name',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _userCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Professor Username',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _passCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Professor Password',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _maxStudentsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Max Students (default 30)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Section assignment is per class offering and student enrollment. Login email is the professor username.',
                        style: TextStyle(fontSize: 12, color: _muted),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _loading ? null : _createProfessor,
                        icon: _loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.person_add_alt_1),
                        label: const Text('Create Professor'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                color: _card,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Create Class Section (Subject Offering)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _selectedOfferingProfessorId,
                        style: _dropdownTextStyle,
                        dropdownColor: _card,
                        decoration: const InputDecoration(
                          labelText: 'Professor (owner of this class)',
                        ),
                        items: _professors
                            .map(
                              (p) => DropdownMenuItem(
                                value: p.id,
                                child: _dropdownLabel(p.fullName),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedOfferingProfessorId = v),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _subjectCodeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Subject Code (ex: IT401)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _subjectTitleCtrl,
                        decoration: const InputDecoration(labelText: 'Subject Title'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _sectionCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Section (ex: BSIT-4A)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedBeaconUuid,
                              style: _dropdownTextStyle,
                              dropdownColor: _card,
                              decoration: const InputDecoration(
                                labelText: 'Beacon UUID',
                              ),
                              items: _beaconUuidOptions
                                  .map(
                                    (u) => DropdownMenuItem(
                                      value: u,
                                      child: Text(
                                        u,
                                        style: _dropdownTextStyle.copyWith(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _selectedBeaconUuid = v),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: _regenBeaconUuids,
                            icon: const Icon(Icons.refresh),
                            label: const Text('New UUIDs'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _beaconNameCtrl,
                        decoration: const InputDecoration(labelText: 'Beacon Name'),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _creatingOffering ? null : _createOffering,
                        icon: _creatingOffering
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.class_),
                        label: const Text('Create Class Section'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Enroll Student to Subject',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Admin can edit student–subject enrollment here.',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
              const SizedBox(height: 12),
              if (_loadingLists) const LinearProgressIndicator(),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _selectedStudentId,
                style: _dropdownTextStyle,
                dropdownColor: _card,
                decoration: const InputDecoration(labelText: 'Student'),
                items: _students
                    .map((s) => DropdownMenuItem(
                          value: s.id,
                          child: _dropdownLabel(s.fullName),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedStudentId = v),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _selectedProfessorId,
                style: _dropdownTextStyle,
                dropdownColor: _card,
                decoration: const InputDecoration(labelText: 'Professor'),
                items: _professors
                    .map((p) => DropdownMenuItem(
                          value: p.id,
                          child: _dropdownLabel(p.fullName),
                        ))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedProfessorId = v;
                    final codes = _subjectCodesForProfessor;
                    _selectedSubjectCode = codes.isNotEmpty ? codes.first : null;
                    final sections = _sectionsForSubject;
                    _selectedSection = sections.isNotEmpty ? sections.first : null;
                    _resolveSelectedOffering();
                  });
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _selectedSubjectCode,
                style: _dropdownTextStyle,
                dropdownColor: _card,
                decoration: const InputDecoration(labelText: 'Subject'),
                items: _subjectCodesForProfessor
                    .map((code) => DropdownMenuItem(
                          value: code,
                          child: _dropdownLabel(code),
                        ))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedSubjectCode = v;
                    final sections = _sectionsForSubject;
                    _selectedSection = sections.isNotEmpty ? sections.first : null;
                    _resolveSelectedOffering();
                  });
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _selectedSection,
                style: _dropdownTextStyle,
                dropdownColor: _card,
                decoration: const InputDecoration(labelText: 'Section'),
                items: _sectionsForSubject
                    .map((section) => DropdownMenuItem(
                          value: section,
                          child: _dropdownLabel(section),
                        ))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedSection = v;
                    _resolveSelectedOffering();
                  });
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _selectedOfferingId,
                style: _dropdownTextStyle,
                dropdownColor: _card,
                decoration: const InputDecoration(labelText: 'Resolved Class Offering'),
                items: _filteredByProfessor
                    .where((o) => _selectedSubjectCode == null || o.subjectCode == _selectedSubjectCode)
                    .where((o) => _selectedSection == null || o.section == _selectedSection)
                    .map((o) => DropdownMenuItem(
                          value: o.id,
                          child: _dropdownLabel(
                              '${o.subjectCode} ${o.section} - ${o.professorName}'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedOfferingId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedEnrollmentKey,
                style: _dropdownTextStyle,
                dropdownColor: _card,
                decoration: const InputDecoration(
                  labelText: 'Existing Enrollment (for editing/removal)',
                ),
                items: _enrollments
                    .map((e) => DropdownMenuItem(
                          value: '${e.studentId}|${e.offeringId}',
                          child: _dropdownLabel(e.label),
                        ))
                    .toList(),
                onChanged: (v) {
                  setState(() => _selectedEnrollmentKey = v);
                  if (v == null) return;
                  final parts = v.split('|');
                  if (parts.length != 2) return;
                  final studentId = parts[0];
                  final offeringId = parts[1];
                  final enrollment = _enrollments.firstWhere(
                    (e) => e.studentId == studentId && e.offeringId == offeringId,
                  );
                  setState(() {
                    _selectedStudentId = enrollment.studentId;
                    _selectedProfessorId = enrollment.professorId;
                    _selectedSubjectCode = enrollment.subjectCode;
                    _selectedSection = enrollment.section;
                    _resolveSelectedOffering();
                  });
                },
              ),
              if (_offerings.isEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'No offerings yet. Create a professor account above first.',
                  style: TextStyle(color: Colors.orange),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _loadingLists ? null : _loadLists,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh lists'),
                ),
              ],
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed:
                    (_enrolling || _selectedStudentId == null || _selectedOfferingId == null)
                        ? null
                        : _enrollStudent,
                icon: _enrolling
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.how_to_reg),
                label: const Text('Save Enrollment'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: (_enrolling || _selectedEnrollmentKey == null)
                    ? null
                    : _removeSelectedEnrollment,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove Selected Enrollment'),
              ),
              const SizedBox(height: 18),
              Card(
                color: _card,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Admin Reports',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 240,
                            child: DropdownButtonFormField<String?>(
                              value: _reportProfessorId,
                              style: _dropdownTextStyle,
                              dropdownColor: _card,
                              decoration: const InputDecoration(
                                labelText: 'Professor',
                              ),
                              items: [
                                DropdownMenuItem<String?>(
                                  value: null,
                                  child: _dropdownLabel('All'),
                                ),
                                ..._professors.map(
                                  (p) => DropdownMenuItem<String?>(
                                    value: p.id,
                                    child: _dropdownLabel(p.fullName),
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                setState(() {
                                  _reportProfessorId = v;
                                  _reportSubjectCode = null;
                                  _reportSection = null;
                                });
                              },
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: DropdownButtonFormField<String?>(
                              value: _reportSubjectCode,
                              style: _dropdownTextStyle,
                              dropdownColor: _card,
                              decoration: const InputDecoration(
                                labelText: 'Subject',
                              ),
                              items: [
                                DropdownMenuItem<String?>(
                                  value: null,
                                  child: _dropdownLabel('All'),
                                ),
                                ..._reportSubjectCodeOptions.map(
                                  (c) => DropdownMenuItem<String?>(
                                    value: c,
                                    child: _dropdownLabel(c),
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                setState(() {
                                  _reportSubjectCode = v;
                                  _reportSection = null;
                                });
                              },
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: DropdownButtonFormField<String?>(
                              value: _reportSection,
                              style: _dropdownTextStyle,
                              dropdownColor: _card,
                              decoration: const InputDecoration(
                                labelText: 'Section',
                              ),
                              items: [
                                DropdownMenuItem<String?>(
                                  value: null,
                                  child: _dropdownLabel('All'),
                                ),
                                ..._reportSectionOptions.map(
                                  (s) => DropdownMenuItem<String?>(
                                    value: s,
                                    child: _dropdownLabel(s),
                                  ),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _reportSection = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _reportRange == null
                                  ? 'Date range: All records'
                                  : 'Date range: ${_reportRange!.start.toLocal().toString().split(' ').first} to ${_reportRange!.end.toLocal().toString().split(' ').first}',
                              style: TextStyle(
                                fontSize: 12,
                                color: _muted,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _pickReportRange,
                            icon: const Icon(Icons.date_range),
                            label: const Text('Pick range'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _loadingReport ? null : _generateReport,
                        icon: _loadingReport
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.summarize_outlined),
                        label: const Text('Generate Attendance Report'),
                      ),
                      const SizedBox(height: 12),
                      if (_reportRows.isNotEmpty)
                        SizedBox(
                          height: 320,
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            color: Colors.white.withValues(alpha: 0.02),
                            elevation: 0,
                            child: ListView.separated(
                              itemCount: _reportRows.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final row = _reportRows[i];
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    '${row.subjectCode} ${row.section} • ${row.studentName}',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  subtitle: Text(
                                    '${row.professorName} • ${row.markedAt.toLocal()}',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.78),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<SubjectOffering> get _reportOfferingsFiltered {
    if (_reportProfessorId == null) return _offerings;
    return _offerings.where((o) => o.professorId == _reportProfessorId).toList();
  }

  List<String> get _reportSubjectCodeOptions {
    final codes = _reportOfferingsFiltered.map((o) => o.subjectCode).toSet().toList()
      ..sort();
    return codes;
  }

  List<String> get _reportSectionOptions {
    final offerings = _reportOfferingsFiltered.where((o) {
      if (_reportSubjectCode == null) return true;
      return o.subjectCode == _reportSubjectCode;
    }).toList();
    final sections = offerings.map((o) => o.section).toSet().toList()..sort();
    return sections;
  }

  List<SubjectOffering> get _filteredByProfessor {
    if (_selectedProfessorId == null) return [];
    return _offerings
        .where((o) => o.professorId == _selectedProfessorId)
        .toList();
  }

  List<String> get _subjectCodesForProfessor {
    final codes = _filteredByProfessor.map((o) => o.subjectCode).toSet().toList()
      ..sort();
    return codes;
  }

  List<String> get _sectionsForSubject {
    final sections = _filteredByProfessor
        .where((o) => o.subjectCode == _selectedSubjectCode)
        .map((o) => o.section)
        .toSet()
        .toList()
      ..sort();
    return sections;
  }

  void _resolveSelectedOffering() {
    final match = _filteredByProfessor.firstWhere(
      (o) =>
          o.subjectCode == _selectedSubjectCode && o.section == _selectedSection,
      orElse: () => const SubjectOffering(
        id: '',
        subjectId: '',
        sectionId: '',
        subjectCode: '',
        subjectTitle: '',
        section: '',
        professorId: '',
        professorName: '',
        beaconUuid: '',
        beaconName: '',
      ),
    );
    _selectedOfferingId = match.id.isEmpty ? null : match.id;
  }
}
