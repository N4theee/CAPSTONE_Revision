import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/admin_data_service.dart';
import '../services/supabase_service.dart';
import 'admin_record_picker.dart';

class AdminClassForm extends StatefulWidget {
  const AdminClassForm({super.key, this.enrollment = false});
  final bool enrollment;
  @override
  State<AdminClassForm> createState() => _AdminClassFormState();
}

class _AdminClassFormState extends State<AdminClassForm> {
  final _data = AdminDataService();
  final _sectionName = TextEditingController();
  final _beaconName = TextEditingController();
  AdminRow? _teacher, _subject, _section, _student, _class;
  bool _newSection = false, _saving = false;
  final _uuid = const Uuid().v4();
  String? _error;
  @override
  void dispose() {
    _sectionName.dispose();
    _beaconName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final section = _newSection
        ? _sectionName.text.trim()
        : '${_section?['section_name'] ?? ''}';
    if (widget.enrollment
        ? (_student == null || _class == null)
        : (_teacher == null || _subject == null || section.isEmpty)) {
      setState(
        () => _error = widget.enrollment
            ? 'Select a student and a class.'
            : 'Select a teacher, subject, and section.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.enrollment) {
        await SupabaseService().enrollStudentToOffering(
          studentId: '${_student!['id']}',
          offeringId: '${_class!['id']}',
        );
      } else {
        await _data.createClass(
          teacherId: '${_teacher!['id']}',
          subjectId: '${_subject!['id']}',
          sectionName: section,
          beaconUuid: _uuid,
          beaconName: _beaconName.text.trim().isEmpty
              ? '${_subject!['subject_code']} · $section'
              : _beaconName.text,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is PostgrestException && e.code == '23505'
              ? 'This class already exists. Open it from Class Sections.'
              : e is PostgrestException && e.code == 'PGRST202'
              ? 'Class creation setup is missing. Apply the admin panel database update.'
              : 'Could not save. Please retry or refresh the available choices.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.enrollment ? 'Enroll Student' : 'Create Class Section',
        ),
        automaticallyImplyLeading: !_saving,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.enrollment
                  ? 'Choose the student and their class.'
                  : 'Choose existing school records. The subject title fills automatically.',
            ),
            const SizedBox(height: 20),
            if (widget.enrollment) ...[
              AdminRecordPicker(
                kind: 'students',
                label: 'Student',
                value: _student,
                enabled: !_saving,
                onChanged: (v) => setState(() => _student = v),
              ),
              const SizedBox(height: 16),
              AdminRecordPicker(
                kind: 'classes',
                label: 'Class',
                value: _class,
                enabled: !_saving,
                onChanged: (v) => setState(() => _class = v),
              ),
            ] else ...[
              AdminRecordPicker(
                kind: 'teachers',
                label: 'Teacher',
                value: _teacher,
                enabled: !_saving,
                onChanged: (v) => setState(() => _teacher = v),
              ),
              const SizedBox(height: 16),
              AdminRecordPicker(
                kind: 'subjects',
                label: 'Subject',
                value: _subject,
                enabled: !_saving,
                onChanged: (v) => setState(() => _subject = v),
              ),
              const SizedBox(height: 8),
              const Text(
                'Missing a subject? Add it from the Subjects page first.',
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Create a new section'),
                value: _newSection,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _newSection = v),
              ),
              if (_newSection)
                TextField(
                  controller: _sectionName,
                  enabled: !_saving,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'New section name',
                    hintText: 'Example: BSIT-4A',
                  ),
                )
              else
                AdminRecordPicker(
                  kind: 'sections',
                  label: 'Section',
                  value: _section,
                  enabled: !_saving,
                  onChanged: (v) => setState(() => _section = v),
                ),
              const SizedBox(height: 16),
              const Text(
                'A unique Bluetooth identifier is assigned automatically.',
              ),
              ExpansionTile(
                title: const Text('Optional beacon name'),
                children: [
                  TextField(
                    controller: _beaconName,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Beacon name',
                      helperText: 'Leave empty to use the subject and section.',
                    ),
                  ),
                ],
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(
                _saving
                    ? 'Saving…'
                    : widget.enrollment
                    ? 'Save Enrollment'
                    : 'Create Class Section',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
