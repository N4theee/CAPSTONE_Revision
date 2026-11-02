import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/admin_data_service.dart';
import '../services/device_management_service.dart';
import 'admin_record_picker.dart';

class AdminDeviceManagement extends StatefulWidget {
  const AdminDeviceManagement({super.key, this.adminUsername = ''});
  final String adminUsername;

  @override
  State<AdminDeviceManagement> createState() => _AdminDeviceManagementState();
}

class _AdminDeviceManagementState extends State<AdminDeviceManagement> {
  final _service = DeviceManagementService();
  AdminRow? _student;
  List<AdminRow> _devices = [], _history = [];
  bool _busy = false;
  String? _error;
  int _request = 0, _historyPage = 0;
  bool _historyLoaded = false;

  String _time(dynamic value) {
    final d = DateTime.tryParse('$value')?.toLocal();
    return d == null
        ? 'Unknown'
        : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _message(Object e) =>
      e is PostgrestException &&
          ['PGRST202', 'PGRST205', '42P01'].contains(e.code)
      ? 'Device Management setup is missing. Apply device_management.sql in Supabase, then retry.'
      : e is PostgrestException
      ? e.message
      : 'Could not complete the request. Please retry.';

  Future<void> _loadDevices() async {
    final student = _student;
    final request = ++_request;
    if (student == null) {
      setState(() => _devices = []);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rows = await _service.devices('${student['id']}');
      if (mounted && request == _request) setState(() => _devices = rows);
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = _message(e));
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _authorize({
    String? action,
    AdminRow? device,
    int page = 0,
  }) async {
    final student = _student;
    if (action != null && student == null) return;
    final result = await showDialog<AdminRow>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeviceAuthorizationDialog(
        username: widget.adminUsername,
        student: student,
        action: action,
        device: device,
        page: page,
      ),
    );
    if (!mounted || result == null) return;
    if (action == null) {
      setState(() {
        _history = (result['rows'] as List)
            .map((r) => AdminRow.from(r as Map))
            .toList();
        _historyPage = page;
        _historyLoaded = true;
      });
    } else {
      setState(() {
        _history = [AdminRow.from(result['entry'] as Map)];
        _historyLoaded = false;
        _historyPage = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Device binding released and login revoked. Ask the student to log in on the intended phone.',
          ),
        ),
      );
      await _loadDevices();
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Release a registered phone without deleting the student’s account or academic records. Each reset requires your administrator password and a reason.',
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          AdminRecordPicker(
            kind: 'students',
            label: 'Student',
            value: _student,
            enabled: !_busy,
            onChanged: (s) {
              setState(() {
                _student = s;
                _devices = [];
              });
              _loadDevices();
            },
          ),
          OutlinedButton.icon(
            onPressed: _busy || _student == null ? null : _loadDevices,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh devices'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _authorize(),
            icon: const Icon(Icons.history),
            label: const Text('View reset history'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(_error!),
        ),
      if (_student != null) ...[
        Text(
          '${_student!['full_name']} · ${_student!['student_number'] ?? _student!['email'] ?? ''}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _authorize(action: 'reset_student_device'),
            icon: const Icon(Icons.phonelink_erase),
            label: const Text('Reset a student’s device'),
          ),
        ),
        const SizedBox(height: 8),
        if (_devices.isEmpty && !_busy && _error == null)
          const Text(
            'No current device binding. An existing login session can still be cleared with Reset a student’s device.',
          ),
        for (final d in _devices)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${d['device_name'] ?? 'Unnamed phone'}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SelectableText('Device ID: ${d['device_uuid']}'),
                  Text(
                    'Registered: ${_time(d['registered_at'])} · Last seen: ${_time(d['last_seen_at'])}',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _authorize(action: 'release_device', device: d),
                    icon: const Icon(Icons.phonelink_off),
                    label: const Text('Release a device for another account'),
                  ),
                ],
              ),
            ),
          ),
      ],
      const SizedBox(height: 24),
      Text(
        _historyLoaded ? 'Reset history — all students' : 'Recent reset',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      if (_history.isEmpty)
        Text(
          _historyLoaded
              ? 'No reset history yet.'
              : 'Use View reset history to securely load administrator reset records.',
        ),
      for (final h in _history)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${h['student_name']} · ${h['student_number'] ?? ''}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  h['action'] == 'release_device'
                      ? 'Released device for another account'
                      : 'Reset student device',
                ),
                Text(
                  'By ${h['admin_name']} (${h['admin_username']}) · ${_time(h['created_at'])}',
                ),
                Text('Reason: ${h['reason']}'),
                if ('${h['details'] ?? ''}'.isNotEmpty) Text('${h['details']}'),
                for (final d in (h['devices'] as List? ?? []))
                  SelectableText(
                    '${d['device_name'] ?? 'Phone'} · ${d['device_uuid']}',
                  ),
              ],
            ),
          ),
        ),
      if (_historyLoaded)
        Wrap(
          spacing: 12,
          children: [
            Text('Page ${_historyPage + 1}'),
            OutlinedButton(
              onPressed: _historyPage == 0
                  ? null
                  : () => _authorize(page: _historyPage - 1),
              child: const Text('Previous'),
            ),
            OutlinedButton(
              onPressed: _history.length < 25
                  ? null
                  : () => _authorize(page: _historyPage + 1),
              child: const Text('Next'),
            ),
          ],
        ),
    ],
  );
}

class _DeviceAuthorizationDialog extends StatefulWidget {
  const _DeviceAuthorizationDialog({
    required this.username,
    this.student,
    this.action,
    this.device,
    this.page = 0,
  });
  final String username;
  final AdminRow? student, device;
  final String? action;
  final int page;
  @override
  State<_DeviceAuthorizationDialog> createState() =>
      _DeviceAuthorizationDialogState();
}

class _DeviceAuthorizationDialogState
    extends State<_DeviceAuthorizationDialog> {
  late final _username = TextEditingController(text: widget.username);
  final _password = TextEditingController(), _details = TextEditingController();
  final _form = GlobalKey<FormState>();
  String? _reason, _error;
  bool _busy = false;
  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await DeviceManagementService().command(
        username: _username.text,
        password: _password.text,
        action: widget.action ?? 'history',
        studentId: widget.action == null ? null : '${widget.student!['id']}',
        deviceUuid: widget.device?['device_uuid'] as String?,
        reason: _reason,
        details: _details.text,
        page: widget.page,
      );
      _password.clear();
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _password.clear();
          _error =
              e is PostgrestException && ['PGRST202', '42P01'].contains(e.code)
              ? 'Device Management setup is missing. Apply device_management.sql in Supabase.'
              : e is PostgrestException
              ? e.message
              : 'Request failed. Please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(
        widget.action == null
            ? 'Authorize reset history'
            : widget.action == 'release_device'
            ? 'Release this device?'
            : 'Reset this student’s device?',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.action != null) ...[
                  Text('Student: ${widget.student!['full_name']}'),
                  if (widget.device != null)
                    SelectableText(
                      'Phone: ${widget.device!['device_name'] ?? 'Unnamed phone'}\nDevice ID: ${widget.device!['device_uuid']}',
                    ),
                  const SizedBox(height: 12),
                  Text(
                    widget.action == 'release_device'
                        ? 'This phone will be released for another account and its student login revoked.'
                        : 'The student’s device bindings and existing login will be revoked. Their next successful login can register the intended phone.',
                  ),
                  const Text(
                    'Account, enrollments, attendance and exam records will be preserved.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Required reason',
                    ),
                    items: [
                      for (final r in deviceResetReasons)
                        DropdownMenuItem(value: r, child: Text(r)),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _reason = v),
                    validator: (v) => v == null ? 'Choose a reason.' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _details,
                    enabled: !_busy,
                    maxLength: 1000,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Explanation / approval reference',
                    ),
                    validator: (v) =>
                        _reason == 'Other' && (v ?? '').trim().length < 5
                        ? 'Explain the other reason (at least 5 characters).'
                        : null,
                  ),
                ],
                TextFormField(
                  controller: _username,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Admin username',
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'Enter your administrator username.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Admin password',
                  ),
                  validator: (v) => (v ?? '').isEmpty
                      ? 'Enter your administrator password.'
                      : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!),
                  ),
                if (_busy) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(widget.action == null ? 'View history' : 'Confirm reset'),
        ),
      ],
    ),
  );
}
