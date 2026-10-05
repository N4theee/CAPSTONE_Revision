import 'package:supabase_flutter/supabase_flutter.dart';

typedef AdminRow = Map<String, dynamic>;

/// Explicit public columns: account password hashes are never fetched.
class AdminDataService {
  final _db = Supabase.instance.client;
  static const selects = <String, String>{
    'enrollmentSubjects':
        'id, subject_code, subject_title, created_at, subject_offerings(sections(section_name), teachers(full_name), student_subject_enrollments(count))',
    'students': 'id, full_name, email, student_number, created_at',
    'teachers': 'id, full_name, email, max_students, created_at',
    'admins': 'id, full_name, email, created_at',
    'subjects': 'id, subject_code, subject_title, created_at',
    'sections': 'id, section_name, created_at',
    'classes':
        'id, teacher_id, subject_id, section_id, beacon_uuid, beacon_name, is_active, created_at, subjects(subject_code, subject_title), sections(section_name), teachers(full_name)',
    'enrollments':
        'id, student_id, subject_offering_id, created_at, students(full_name, student_number), subject_offerings(subjects(subject_code), sections(section_name), teachers(full_name))',
    'exams':
        'id, exam_title, exam_code, status, created_at, starts_at, ends_at, teacher_id, subject_offering_id, teachers(full_name), subject_offerings(subjects(subject_code), sections(section_name))',
    'questions':
        'id, question_text, points, question_order, exam_session_id, created_at, exam_sessions(exam_title, exam_code)',
    'attempts':
        'id, student_id, exam_session_id, status, exam_score, percentage_score, raw_score, total_points, submitted_at, completion_seconds, violation_count, started_at, ended_at, students(full_name), exam_sessions(exam_title, exam_code)',
    'sessions':
        'id, subject_offering_id, is_active, started_at, ended_at, beacon_uuid, beacon_name, subject_offerings(subjects(subject_code), sections(section_name), teachers(full_name))',
    'records':
        'id, student_id, attendance_session_id, status, marked_at, device_name, students(full_name, student_number), attendance_sessions(subject_offerings(subjects(subject_code), sections(section_name), teachers(full_name)))',
    'alerts':
        'id, student_id, exam_attempt_id, exam_session_id, alert_type, message, is_read, created_at, students(full_name), exam_sessions(exam_title)',
  };
  static const tables = {
    'enrollmentSubjects': 'subjects',
    'classes': 'subject_offerings',
    'enrollments': 'student_subject_enrollments',
    'exams': 'exam_sessions',
    'questions': 'exam_questions',
    'attempts': 'exam_attempts',
    'sessions': 'attendance_sessions',
    'records': 'attendance_records',
    'alerts': 'exam_alerts',
  };
  static const dates = {
    'attempts': 'started_at',
    'sessions': 'started_at',
    'records': 'marked_at',
  };

  Future<List<AdminRow>> page(
    String kind, {
    int page = 0,
    int size = 25,
    String? status,
    DateTime? from,
    DateTime? to,
    String? teacherId,
    String? subjectId,
    String? examId,
    String? filterColumn,
    String? filterValue,
  }) async {
    var selection = selects[kind]!;
    if (kind == 'classes') selection += ', student_subject_enrollments(count)';
    if ((kind == 'questions' || kind == 'attempts') &&
        (teacherId != null || subjectId != null)) {
      selection = selection.replaceFirst(
        'exam_sessions(exam_title, exam_code)',
        'exam_sessions!inner(exam_title, exam_code, teacher_id, subject_offerings!inner(subject_id))',
      );
    }
    if (kind == 'exams' && subjectId != null) {
      selection = selection.replaceFirst(
        'subject_offerings(',
        'subject_offerings!inner(subject_id, ',
      );
    }
    var query = _db.from(tables[kind] ?? kind).select(selection);
    if (teacherId != null) {
      query = query.eq(
        kind == 'exams' ? 'teacher_id' : 'exam_sessions.teacher_id',
        teacherId,
      );
    }
    if (subjectId != null) {
      query = query.eq(
        kind == 'exams'
            ? 'subject_offerings.subject_id'
            : 'exam_sessions.subject_offerings.subject_id',
        subjectId,
      );
    }
    if (examId != null) {
      query = query.eq(kind == 'exams' ? 'id' : 'exam_session_id', examId);
    }
    if (status != null) {
      query = kind == 'sessions' || kind == 'classes'
          ? query.eq('is_active', status == 'Active')
          : query.eq('status', status);
    }
    if (filterColumn != null && filterValue != null) {
      query = query.eq(filterColumn, filterValue);
    }
    final date = dates[kind] ?? 'created_at';
    if (from != null) query = query.gte(date, from.toUtc().toIso8601String());
    if (to != null) query = query.lt(date, to.toUtc().toIso8601String());
    final rows = await query
        .order(
          kind == 'questions' ? 'question_order' : date,
          ascending: kind == 'questions',
        )
        .order('id')
        .range(page * size, (page + 1) * size - 1);
    return rows.map((r) {
      final row = AdminRow.from(r);
      int count(dynamic value) => value is List && value.isNotEmpty
          ? (value.first['count'] as num?)?.toInt() ?? 0
          : 0;
      if (kind == 'classes') {
        row['student_count'] = count(row['student_subject_enrollments']);
      }
      if (kind == 'enrollmentSubjects') {
        final offerings = (row['subject_offerings'] as List? ?? [])
            .where((o) => count(o['student_subject_enrollments']) > 0)
            .toList();
        row['section_summary'] = offerings
            .map((o) => o['sections']?['section_name'])
            .whereType<String>()
            .toSet()
            .join(', ');
        row['teacher_summary'] = offerings
            .map((o) => o['teachers']?['full_name'])
            .whereType<String>()
            .toSet()
            .join(', ');
        row['student_count'] = offerings.fold<int>(
          0,
          (total, o) => total + count(o['student_subject_enrollments']),
        );
      }
      return row;
    }).toList();
  }

  /// Fetch only one page of dropdown choices; filtering runs in Postgres.
  Future<List<AdminRow>> lookup(
    String kind, {
    String search = '',
    int page = 0,
    String? teacherId,
    String? subjectId,
  }) async {
    const fields = {
      'teachers': 'full_name',
      'students': 'full_name',
      'subjects': 'subject_code',
      'sections': 'section_name',
      'exams': 'exam_title',
    };
    var selection = selects[kind]!;
    if ((kind == 'exams' || kind == 'classes') && subjectId != null) {
      selection = selection
          .replaceFirst('subject_offerings(', 'subject_offerings!inner(')
          .replaceFirst(
            'subjects(subject_code)',
            'subject_id, subjects(subject_code)',
          );
    }
    if (kind == 'classes' && search.trim().isNotEmpty) {
      selection = selection.replaceFirst(
        'sections(section_name)',
        'sections!inner(section_name)',
      );
    }
    var query = _db.from(tables[kind] ?? kind).select(selection);
    if (kind == 'classes') query = query.eq('is_active', true);
    if (teacherId != null) query = query.eq('teacher_id', teacherId);
    if (subjectId != null) {
      query = query.eq(
        kind == 'classes' ? 'subject_id' : 'subject_offerings.subject_id',
        subjectId,
      );
    }
    final field = fields[kind] ?? 'created_at';
    final searchField = kind == 'classes' ? 'sections.section_name' : field;
    if (search.trim().isNotEmpty) {
      final term = search.trim().replaceAll('%', r'\%').replaceAll('_', r'\_');
      query = query.ilike(searchField, '%$term%');
    }
    final rows = await query
        .order(field)
        .order('id')
        .range(page * 25, page * 25 + 24);
    return rows.map(AdminRow.from).toList();
  }

  Future<void> createClass({
    required String teacherId,
    required String subjectId,
    required String sectionName,
    required String beaconUuid,
    required String beaconName,
  }) async {
    await _db.rpc(
      'admin_create_class_section',
      params: {
        'p_teacher_id': teacherId,
        'p_subject_id': subjectId,
        'p_section_name': sectionName.trim(),
        'p_beacon_uuid': beaconUuid,
        'p_beacon_name': beaconName.trim(),
      },
    );
  }

  Future<int> count(String kind, {String? status}) async {
    var query = _db.from(tables[kind] ?? kind).count(CountOption.exact);
    if (status != null) query = query.eq('status', status);
    return await query;
  }

  Future<Map<String, int>> totals() async {
    const kinds = [
      'students',
      'teachers',
      'subjects',
      'classes',
      'enrollments',
      'exams',
      'attempts',
    ];
    final values = await Future.wait(kinds.map(count));
    return Map.fromIterables(kinds, values);
  }

  Future<void> saveSubject({
    String? id,
    required String code,
    required String title,
  }) async {
    final values = {'subject_code': code.trim(), 'subject_title': title.trim()};
    if (id == null) {
      await _db.from('subjects').insert(values);
    } else {
      await _db.from('subjects').update(values).eq('id', id);
    }
  }

  Future<void> saveClass(
    String id, {
    required String teacherId,
    required String beaconUuid,
    required String beaconName,
    required bool active,
  }) async {
    final running = await Future.wait<int>([
      _db
          .from('attendance_sessions')
          .count(CountOption.exact)
          .eq('subject_offering_id', id)
          .eq('is_active', true),
      _db
          .from('exam_sessions')
          .count(CountOption.exact)
          .eq('subject_offering_id', id)
          .inFilter('status', ['active', 'paused']),
    ]);
    if (running.any((count) => count > 0)) {
      throw Exception(
        'End the running attendance or exam session before editing this class.',
      );
    }
    await _db
        .from('subject_offerings')
        .update({
          'teacher_id': teacherId,
          'beacon_uuid': beaconUuid.trim(),
          'beacon_name': beaconName.trim(),
          'is_active': active,
        })
        .eq('id', id);
  }

  Future<List<AdminRow>> monitoring(String attemptId, {int page = 0}) async {
    final rows = await _db
        .from('exam_proximity_logs')
        .select('id, created_at, is_in_range, rssi')
        .eq('exam_attempt_id', attemptId)
        .order('created_at', ascending: false)
        .order('id')
        .range(page * 25, page * 25 + 24);
    return rows.map(AdminRow.from).toList();
  }

  /// Full aggregation happens in Postgres, without downloading historical rows.
  Future<AdminRow> summary() async =>
      AdminRow.from(await _db.rpc('admin_dashboard_summary'));
}
