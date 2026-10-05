import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/admin_data_service.dart';

String adminChoiceLabel(String kind, AdminRow row) {
  if (kind == 'subjects') {
    return '${row['subject_code']} — ${row['subject_title']}';
  }
  if (kind == 'sections') return '${row['section_name']}';
  if (kind == 'exams') return '${row['exam_title']} · ${row['exam_code']}';
  if (kind == 'classes') {
    final subject = row['subjects'] as Map? ?? {};
    final section = row['sections'] as Map? ?? {};
    final teacher = row['teachers'] as Map? ?? {};
    return '${subject['subject_code']} · ${section['section_name']} · ${teacher['full_name']}';
  }
  return '${row['full_name']} · ${row['email'] ?? row['student_number'] ?? ''}';
}

/// Searchable dropdown with bounded, server-filtered choice pages.
class AdminRecordPicker extends StatelessWidget {
  const AdminRecordPicker({
    super.key,
    required this.kind,
    required this.label,
    required this.value,
    required this.onChanged,
    this.teacherId,
    this.subjectId,
    this.enabled = true,
    this.allowClear = true,
  });
  final String kind, label;
  final AdminRow? value;
  final ValueChanged<AdminRow?> onChanged;
  final String? teacherId, subjectId;
  final bool enabled, allowClear;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 280,
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(14)),
      onPressed: !enabled
          ? null
          : () async {
              final result = await showDialog<AdminRow>(
                context: context,
                builder: (_) => _PickerDialog(
                  kind: kind,
                  label: label,
                  teacherId: teacherId,
                  subjectId: subjectId,
                  allowClear: allowClear,
                ),
              );
              if (result != null) onChanged(result.isEmpty ? null : result);
            },
      child: Row(
        children: [
          Expanded(
            child: Text(
              value == null ? 'Select $label' : adminChoiceLabel(kind, value!),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    ),
  );
}

class _PickerDialog extends StatefulWidget {
  const _PickerDialog({
    required this.kind,
    required this.label,
    this.teacherId,
    this.subjectId,
    required this.allowClear,
  });
  final String kind, label;
  final String? teacherId, subjectId;
  final bool allowClear;
  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  final _data = AdminDataService();
  final _search = TextEditingController();
  Timer? _debounce;
  List<AdminRow> _rows = [];
  bool _busy = true;
  String? _error;
  int _page = 0, _request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
      _rows = [];
    });
    try {
      final rows = await _data.lookup(
        widget.kind,
        search: _search.text,
        page: _page,
        teacherId: widget.teacherId,
        subjectId: widget.subjectId,
      );
      if (mounted && request == _request) {
        setState(() {
          _rows = rows;
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _error = 'Could not load choices. Please retry.';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Select ${widget.label}'),
    content: SizedBox(
      width: 540,
      height: math.max(
        100,
        math.min(
          380,
          (MediaQuery.sizeOf(context).height -
                  MediaQuery.viewInsetsOf(context).vertical) *
              .45,
        ),
      ),
      child: Column(
        children: [
          TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: widget.kind == 'subjects'
                  ? 'Search subject code'
                  : widget.kind == 'classes'
                  ? 'Search section name'
                  : 'Search ${widget.label.toLowerCase()}',
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (_) {
              _debounce?.cancel();
              ++_request;
              setState(() {
                _busy = true;
              });
              _debounce = Timer(const Duration(milliseconds: 350), () {
                _page = 0;
                _load();
              });
            },
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            TextButton(onPressed: _load, child: Text(_error!)),
          Expanded(
            child: _busy
                ? const SizedBox()
                : ListView(
                    children: [
                      if (_rows.isEmpty && _error == null)
                        const ListTile(title: Text('No matching choices')),
                      for (final row in _rows)
                        ListTile(
                          title: Text(adminChoiceLabel(widget.kind, row)),
                          onTap: () => Navigator.pop(context, row),
                        ),
                    ],
                  ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Page ${_page + 1}'),
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
            ],
          ),
        ],
      ),
    ),
    actions: [
      if (widget.allowClear)
        TextButton(
          onPressed: () => Navigator.pop(context, <String, dynamic>{}),
          child: const Text('Clear selection'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}
