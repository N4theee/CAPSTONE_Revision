import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_identity_service.dart';
import '../util/db_timestamptz.dart';

export 'exam_service.dart';

class AppUser {
  const AppUser({
    required this.role,
    required this.linkedId,
    required this.fullName,
    required this.username,
  });

  final String role;
  final String linkedId;
  final String fullName;
  final String username;
}

class StudentActiveSessionStatus {
  const StudentActiveSessionStatus({
    required this.hasActiveSession,
    this.sessionId,
    this.offeringId,
    required this.alreadyMarked,
    this.subjectCode,
    this.subjectTitle,
    this.section,
  });

  final bool hasActiveSession;
  final String? sessionId;
  final String? offeringId;
  final bool alreadyMarked;
  final String? subjectCode;
  final String? subjectTitle;
  final String? section;
}

class SubjectOffering {
  const SubjectOffering({
    required this.id,
    required this.subjectId,
    required this.sectionId,
    required this.subjectCode,
    required this.subjectTitle,
    required this.section,
    required this.teacherId,
    required this.teacherName,
    required this.beaconUuid,
    required this.beaconName,
  });

  final String id;
  final String subjectId;
  final String sectionId;
  final String subjectCode;
  final String subjectTitle;
  final String section;
  final String teacherId;
  final String teacherName;
  final String beaconUuid;
  final String beaconName;

  String get label => '$subjectCode ($section)';
}

class StudentBasic {
  const StudentBasic({
    required this.id,
    required this.fullName,
  });

  final String id;
  final String fullName;
}

class TeacherBasic {
  const TeacherBasic({
    required this.id,
    required this.fullName,
  });

  final String id;
  final String fullName;
}

class TeacherSessionHistoryItem {
  const TeacherSessionHistoryItem({
    required this.sessionId,
    required this.subjectCode,
    required this.subjectTitle,
    required this.section,
    required this.startedAt,
    required this.endedAt,
    required this.isActive,
  });

  final String sessionId;
  final String subjectCode;
  final String subjectTitle;
  final String section;
  final DateTime startedAt;
  final DateTime? endedAt;
  final bool isActive;
}

class SessionAttendanceDetailItem {
  const SessionAttendanceDetailItem({
    required this.studentId,
    required this.studentName,
    required this.isPresent,
    this.markedAt,
    this.deviceUsed,
  });

  final String studentId;
  final String studentName;
  final bool isPresent;
  final DateTime? markedAt;
  final String? deviceUsed;
}

class StudentAttendanceHistoryItem {
  const StudentAttendanceHistoryItem({
    required this.subjectCode,
    required this.subjectTitle,
    required this.section,
    required this.teacherName,
    required this.sessionStartedAt,
    required this.markedAt,
  });

  final String subjectCode;
  final String subjectTitle;
  final String section;
  final String teacherName;
  final DateTime sessionStartedAt;
  final DateTime markedAt;
}

class EnrollmentRecord {
  const EnrollmentRecord({
    required this.studentId,
    required this.studentName,
    required this.offeringId,
    required this.teacherId,
    required this.teacherName,
    required this.subjectCode,
    required this.subjectTitle,
    required this.section,
  });

  final String studentId;
  final String studentName;
  final String offeringId;
  final String teacherId;
  final String teacherName;
  final String subjectCode;
  final String subjectTitle;
  final String section;

  String get label =>
      '$studentName â†’ $subjectCode $section ($teacherName)';
}

class AdminAttendanceReportItem {
  const AdminAttendanceReportItem({
    required this.sessionId,
    required this.sessionStartedAt,
    required this.sessionEndedAt,
    required this.subjectCode,
    required this.subjectTitle,
    required this.section,
    required this.teacherId,
    required this.teacherName,
    required this.studentId,
    required this.studentName,
    required this.markedAt,
    required this.deviceName,
    required this.deviceMac,
    required this.deviceFingerprint,
  });

  final String sessionId;
  final DateTime sessionStartedAt;
  final DateTime? sessionEndedAt;
  final String subjectCode;
  final String subjectTitle;
  final String section;
  final String teacherId;
  final String teacherName;
  final String studentId;
  final String studentName;
  final DateTime markedAt;
  final String? deviceName;
  final String? deviceMac;
  final String? deviceFingerprint;
}

class AttendanceAnomaly {
  const AttendanceAnomaly({
    required this.deviceLabel,
    required this.deviceUuid,
    required this.students,
  });

  final String deviceLabel;
  final String deviceUuid;
  final List<String> students;
}

class SessionNotificationItem {
  const SessionNotificationItem({
    required this.sessionId,
    required this.offeringId,
    required this.subjectCode,
    required this.subjectTitle,
    required this.section,
    required this.teacherName,
    required this.startedAt,
  });

  final String sessionId;
  final String offeringId;
  final String subjectCode;
  final String subjectTitle;
  final String section;
  final String teacherName;
  final DateTime startedAt;
}

class SupabaseService {
  static final SupabaseService _i = SupabaseService._();
  factory SupabaseService() => _i;
  SupabaseService._();

  final _db = Supabase.instance.client;

  // â”€â”€ AUTH + ADMIN â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<AppUser?> login({
    required String username,
    required String password,
    required String role,
  }) async {
    final raw = await _db.rpc(
      'app_login',
      params: {
        'p_username': username.trim(),
        'p_password': password.trim(),
        'p_role': role.trim(),
      },
    );
    if (raw is! List || raw.isEmpty) return null;
    final row = raw.first as Map<String, dynamic>;
    return AppUser(
      role: row['role'] as String,
      linkedId: row['linked_id'] as String,
      fullName: row['full_name'] as String,
      username: row['username'] as String,
    );
  }

  /// Student login with device binding (RPC `app_student_login_with_device`).
  Future<AppUser?> loginStudentWithDevice({
    required String username,
    required String password,
    required DeviceIdentity identity,
  }) async {
    final raw = await _db.rpc(
      'app_student_login_with_device',
      params: {
        'p_username': username.trim(),
        'p_password': password.trim(),
        'p_device_uuid': identity.deviceUuid.trim(),
        'p_device_name': identity.deviceName.trim(),
        'p_device_fingerprint': identity.deviceFingerprint.trim(),
      },
    );
    if (raw is! List || raw.isEmpty) return null;
    final row = raw.first as Map<String, dynamic>;
    return AppUser(
      role: row['role'] as String,
      linkedId: row['linked_id'] as String,
      fullName: row['full_name'] as String,
      username: row['username'] as String,
    );
  }

  Future<void> signOutStudentDevice({
    required String studentId,
    required DeviceIdentity identity,
  }) async {
    await _db.rpc(
      'student_sign_out_device',
      params: {
        'p_student_id': studentId.trim(),
        'p_device_uuid': identity.deviceUuid.trim(),
      },
    );
  }

  Future<StudentActiveSessionStatus> getStudentActiveSessionStatus(
    String studentId,
  ) async {
    final raw = await _db.rpc(
      'get_student_active_session_status',
      params: {'p_student_id': studentId.trim()},
    );
    if (raw is! List || raw.isEmpty) {
      return const StudentActiveSessionStatus(
        hasActiveSession: false,
        alreadyMarked: false,
      );
    }
    final row = raw.first as Map<String, dynamic>;
    return StudentActiveSessionStatus(
      hasActiveSession: row['has_active_session'] as bool? ?? false,
      sessionId: row['session_id'] as String?,
      offeringId: row['offering_id'] as String?,
      alreadyMarked: row['already_marked'] as bool? ?? false,
      subjectCode: row['subject_code'] as String?,
      subjectTitle: row['subject_title'] as String?,
      section: row['section'] as String?,
    );
  }

  /// Secure student attendance (device validated server-side).
  Future<bool> markAttendanceSecure({
    required String sessionId,
    required String studentId,
    required String studentName,
    required DeviceIdentity identity,
  }) async {
    final result = await _db.rpc(
      'mark_attendance_secure',
      params: {
        'p_session_id': sessionId,
        'p_student_id': studentId,
        'p_student_name': studentName.trim(),
        'p_device_uuid': identity.deviceUuid.trim(),
        'p_device_name': identity.deviceName.trim(),
        'p_device_fingerprint': identity.deviceFingerprint.trim(),
      },
    );
    return result == true;
  }

  Future<String> registerStudent({
    required String studentId,
    required String fullName,
    required String username,
    required String password,
    String? deviceUuid,
    String? deviceName,
  }) async {
    final baseParams = {
      'p_student_id': studentId.trim(),
      'p_full_name': fullName.trim(),
      'p_username': username.trim(),
      'p_password': password.trim(),
    };
    try {
      final result = await _db.rpc(
        'register_student',
        params: {
          ...baseParams,
          'p_device_uuid': deviceUuid,
          'p_device_name': deviceName?.trim(),
        },
      );
      return result as String;
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202') rethrow;
      final result = await _db.rpc(
        'register_student',
        params: baseParams,
      );
      return result as String;
    }
  }

  Future<List<StudentBasic>> getAllStudents() async {
    final rows = await _db
        .from('students')
        .select('id, full_name, student_number')
        .order('full_name');
    return rows
        .map((e) => StudentBasic(
              id: e['id'] as String,
              fullName: e['full_name'] as String,
            ))
        .toList();
  }

  Future<List<TeacherBasic>> getAllTeachers() async {
    final rows = await _db.from('teachers').select('id, full_name').order(
          'full_name',
        );
    return rows
        .map((e) => TeacherBasic(
              id: e['id'] as String,
              fullName: e['full_name'] as String,
            ))
        .toList();
  }

  Future<String> createTeacherByAdmin({
    required String teacherId,
    required String fullName,
    required String username,
    required String password,
    int maxStudents = 30,
  }) async {
    final params = {
      'p_teacher_id': teacherId.trim(),
      'p_full_name': fullName.trim(),
      'p_username': username.trim(),
      'p_password': password.trim(),
      'p_max_students': maxStudents,
    };
    try {
      final result = await _db.rpc(
        'admin_create_teacher_account',
        params: params,
      );
      return result as String;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202') {
        throw Exception(
          'Database function missing. Run latest SQL schema and reload PostgREST cache.',
        );
      }
      rethrow;
    }
  }

  Future<void> createSubjectOfferingByAdmin({
    required String teacherId,
    required String subjectCode,
    required String subjectTitle,
    required String section,
    required String beaconUuid,
    required String beaconName,
  }) async {
    try {
      await _db.rpc(
        'admin_create_subject_offering',
        params: {
          'p_teacher_id': teacherId.trim(),
          'p_subject_code': subjectCode.trim(),
          'p_subject_title': subjectTitle.trim(),
          'p_section': section.trim(),
          'p_beacon_uuid': beaconUuid.trim(),
          'p_beacon_name': beaconName.trim(),
        },
      );
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202') {
        throw Exception(
          'Database function missing. Run the latest SQL schema then retry.',
        );
      }
      rethrow;
    }
  }

  Future<List<SubjectOffering>> getAllOfferings() async {
    return _fetchSubjectOfferingsFromTable(teacherId: null);
  }

  Future<void> enrollStudentToOffering({
    required String studentId,
    required String offeringId,
  }) async {
    await _db.rpc(
      'admin_assign_student_to_offering',
      params: {
        'p_student_id': studentId.trim(),
        'p_offering_id': offeringId,
      },
    );
  }

  Future<List<EnrollmentRecord>> getAdminEnrollments() async {
    final rows = await _db.rpc('get_admin_enrollments');
    if (rows is! List) return [];
    return rows.map((e) {
      final map = e as Map<String, dynamic>;
      return EnrollmentRecord(
        studentId: map['student_id'] as String,
        studentName: map['student_name'] as String,
        offeringId: map['offering_id'] as String,
        teacherId: map['teacher_id'] as String,
        teacherName: map['teacher_name'] as String,
        subjectCode: map['subject_code'] as String,
        subjectTitle: map['subject_title'] as String,
        section: map['section'] as String,
      );
    }).toList();
  }

  Future<void> removeEnrollment({
    required String studentId,
    required String offeringId,
  }) async {
    await _db
        .from('student_subject_enrollments')
        .delete()
        .eq('student_id', studentId)
        .eq('subject_offering_id', offeringId);
  }

  Future<List<AdminAttendanceReportItem>> getAdminAttendanceReport({
    DateTime? from,
    DateTime? to,
    String? teacherId,
    String? subjectCode,
    String? section,
  }) async {
    final rows = await _db.rpc(
      'get_admin_attendance_report',
      params: {
        'p_from': from?.toUtc().toIso8601String(),
        'p_to': to?.toUtc().toIso8601String(),
        'p_teacher_id': teacherId?.trim(),
        'p_subject_code': subjectCode?.trim(),
        'p_section_name': section?.trim(),
      },
    );
    if (rows is! List) return [];
    return rows.map((row) {
      final map = row as Map<String, dynamic>;

      return AdminAttendanceReportItem(
        sessionId: (map['session_id'] as String?) ?? '',
        sessionStartedAt: parseDbTimestamptzToLocal(
          (map['session_started_at'] ?? map['marked_at'])!,
        ),
        sessionEndedAt: (map['session_ended_at'] as String?) == null
            ? null
            : parseDbTimestamptzToLocal(map['session_ended_at'] as String),
        subjectCode: (map['subject_code'] as String?) ?? 'SUBJECT',
        subjectTitle: (map['subject_title'] as String?) ?? 'Untitled',
        section: (map['section'] as String?) ?? 'N/A',
        teacherId: (map['teacher_id'] as String?) ?? '',
        teacherName: (map['teacher_name'] as String?) ?? 'Teacher',
        studentId: (map['student_id'] as String?) ?? '',
        studentName: (map['student_name'] as String?) ?? 'Student',
        markedAt: parseDbTimestamptzToLocal(map['marked_at'] as String),
        deviceName: map['device_name'] as String?,
        deviceMac: map['device_mac'] as String?,
        deviceFingerprint: map['device_fingerprint'] as String?,
      );
    }).toList();
  }

  Future<void> updateDisplayName({
    required String role,
    required String linkedId,
    required String fullName,
  }) async {
    await _db.rpc(
      'update_display_name',
      params: {
        'p_role': role,
        'p_linked_id': linkedId,
        'p_full_name': fullName.trim(),
      },
    );
  }

  Future<List<SubjectOffering>> getStudentOfferings(String studentId) async {
    final rows = await _db.rpc(
      'get_student_dashboard',
      params: {'p_student_id': studentId},
    );
    if (rows is! List) return [];
    return rows
        .map((e) => _offeringFromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<SubjectOffering>> getTeacherOfferings(String teacherId) async {
    return _fetchSubjectOfferingsFromTable(teacherId: teacherId);
  }

  /// Loads offerings from `subject_offerings` so `beacon_uuid` / `beacon_name`
  /// always match the table (RPC cache / shape mismatches on older deployments).
  Future<List<SubjectOffering>> _fetchSubjectOfferingsFromTable({
    String? teacherId,
  }) async {
    final pid = teacherId?.trim();
    try {
      var q = _db
          .from('subject_offerings')
          .select(
            'id, subject_id, section_id, teacher_id, beacon_uuid, beacon_name, '
            'subjects(subject_code, subject_title), '
            'sections(section_name), '
            'teachers(full_name)',
          )
          .eq('is_active', true);
      if (pid != null && pid.isNotEmpty) {
        q = q.eq('teacher_id', pid);
      }
      final rows = await q;
      if (rows.isEmpty) return [];
      final list = rows
          .map((e) => _offeringFromTableRow(Map<String, dynamic>.from(e)))
          .toList();
      list.sort((a, b) {
        final c = a.subjectCode.compareTo(b.subjectCode);
        return c != 0 ? c : a.section.compareTo(b.section);
      });
      return list;
    } on PostgrestException {
      // Fall back to RPC (e.g. embed not exposed).
    }

    final rpcRows = (pid == null || pid.isEmpty)
        ? await _db.rpc('get_subject_offerings_view')
        : await _db.rpc(
            'get_subject_offerings_view',
            params: {'p_teacher_id': pid},
          );
    if (rpcRows is! List) return [];
    return rpcRows
        .map((e) => _offeringFromSelect(e as Map<String, dynamic>))
        .toList();
  }

  /// Enrollment counts per offering (for dashboard cards).
  Future<Map<String, int>> getEnrollmentCountsForOfferings(
      List<String> offeringIds) async {
    if (offeringIds.isEmpty) return {};
    final rows = await _db
        .from('student_subject_enrollments')
        .select('subject_offering_id')
        .inFilter('subject_offering_id', offeringIds);
    final map = {for (final id in offeringIds) id: 0};
    for (final r in rows) {
      final id = r['subject_offering_id'] as String;
      map[id] = (map[id] ?? 0) + 1;
    }
    return map;
  }

  static String _jsonStr(dynamic v) {
    if (v == null) return '';
    if (v is String) return v.trim();
    return v.toString().trim();
  }

  static Map<String, dynamic> _embeddedOne(
    Map<String, dynamic> row,
    String key,
  ) {
    final v = row[key];
    if (v is Map<String, dynamic>) return v;
    if (v is List) {
      for (final item in v) {
        if (item is Map<String, dynamic>) return item;
      }
    }
    return const {};
  }

  SubjectOffering _offeringFromTableRow(Map<String, dynamic> e) {
    final sub = _embeddedOne(e, 'subjects');
    final sec = _embeddedOne(e, 'sections');
    final prof = _embeddedOne(e, 'teachers');
    final profName = _jsonStr(prof['full_name']);
    return SubjectOffering(
      id: _jsonStr(e['id']),
      subjectId: _jsonStr(e['subject_id']),
      sectionId: _jsonStr(e['section_id']),
      subjectCode: _jsonStr(sub['subject_code']),
      subjectTitle: _jsonStr(sub['subject_title']),
      section: _jsonStr(sec['section_name']),
      teacherId: _jsonStr(e['teacher_id']),
      teacherName: profName.isEmpty ? 'Teacher' : profName,
      beaconUuid: _jsonStr(e['beacon_uuid']),
      beaconName: _jsonStr(e['beacon_name']),
    );
  }

  SubjectOffering _offeringFromMap(Map<String, dynamic> e) {
    final profName = _jsonStr(e['teacher_name']);
    return SubjectOffering(
      id: _jsonStr(e['offering_id']),
      subjectId: _jsonStr(e['subject_id']),
      sectionId: _jsonStr(e['section_id']),
      subjectCode: _jsonStr(e['subject_code']),
      subjectTitle: _jsonStr(e['subject_title']),
      section: _jsonStr(e['section']),
      teacherId: _jsonStr(e['teacher_id']),
      teacherName: profName.isEmpty ? 'Teacher' : profName,
      beaconUuid: _jsonStr(e['beacon_uuid']),
      beaconName: _jsonStr(e['beacon_name']),
    );
  }

  SubjectOffering _offeringFromSelect(Map<String, dynamic> e) {
    final profName = _jsonStr(e['teacher_name']);
    return SubjectOffering(
      id: _jsonStr(e['id']),
      subjectId: _jsonStr(e['subject_id']),
      sectionId: _jsonStr(e['section_id']),
      subjectCode: _jsonStr(e['subject_code']),
      subjectTitle: _jsonStr(e['subject_title']),
      section: _jsonStr(e['section']),
      teacherId: _jsonStr(e['teacher_id']),
      teacherName: profName.isEmpty ? 'Teacher' : profName,
      beaconUuid: _jsonStr(e['beacon_uuid']),
      beaconName: _jsonStr(e['beacon_name']),
    );
  }

  // â”€â”€ TEACHER ATTENDANCE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<Map<String, dynamic>> startSession({
    required String teacherId,
    required String offeringId,
    required String subject,
    required String beaconUuid,
    required String beaconName,
    int rssiThreshold = -100,
  }) async {
    // End any previous active sessions first
    try {
      await _db
          .from('attendance_sessions')
          .update({'is_active': false, 'ended_at': utcIsoNowForDb()})
          .eq('subject_offering_id', offeringId)
          .eq('is_active', true);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST204' && e.message.contains('offering_id')) {
        await _db
            .from('attendance_sessions')
            .update({'is_active': false, 'ended_at': utcIsoNowForDb()})
            .eq('is_active', true);
      } else {
        rethrow;
      }
    }

    Map<String, dynamic> result;
    try {
      result = await _db
          .from('attendance_sessions')
          .insert({
            'subject_offering_id': offeringId,
            'beacon_uuid': beaconUuid,
            'beacon_name': beaconName,
            'rssi_threshold': rssiThreshold,
            'is_active': true,
          })
          .select()
          .single();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST204' && e.message.contains('beacon_name')) {
        result = await _db
            .from('attendance_sessions')
            .insert({
              'subject_offering_id': offeringId,
              'beacon_uuid': beaconUuid,
              'is_active': true,
            })
            .select()
            .single();
      } else if (e.code == 'PGRST204' && e.message.contains('offering_id')) {
        result = await _db
            .from('attendance_sessions')
            .insert({
              'subject_offering_id': offeringId,
              'beacon_uuid': beaconUuid,
              'beacon_name': beaconName,
              'rssi_threshold': rssiThreshold,
              'is_active': true,
            })
            .select()
            .single();
      } else {
        rethrow;
      }
    }

    debugPrint('[DB] Session started: ${result['id']}');
    return result;
  }

  Future<void> endSession(String sessionId) async {
    await _db.from('attendance_sessions').update({
      'is_active': false,
      'ended_at': utcIsoNowForDb(),
    }).eq('id', sessionId);
    debugPrint('[DB] Session ended: $sessionId');
  }

  // â”€â”€ STUDENT â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<Map<String, dynamic>?> getActiveSessionForOffering(
      String offeringId) async {
    List<Map<String, dynamic>> result;
    try {
      result = await _db
          .from('attendance_sessions')
          .select()
          .eq('is_active', true)
          .eq('subject_offering_id', offeringId)
          .order('started_at', ascending: false)
          .limit(1);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST204' && e.message.contains('offering_id')) {
        result = await _db
            .from('attendance_sessions')
            .select()
            .eq('is_active', true)
            .order('started_at', ascending: false)
            .limit(1);
      } else {
        rethrow;
      }
    }
    if (result.isEmpty) return null;
    debugPrint('[DB] Active session found: ${result.first}');
    return result.first;
  }

  Future<bool> markAttendance({
    required String sessionId,
    required String studentId,
    required String studentName,
    String? deviceUuid,
    String? deviceName,
    String? deviceMac,
    String? deviceFingerprint,
  }) async {
    try {
      final payload = <String, dynamic>{
        'attendance_session_id': sessionId,
        'student_id': studentId,
        'student_device_id': null,
        'status': 'Present',
        'marked_at': utcIsoNowForDb(),
      };
      if (deviceName != null && deviceName.trim().isNotEmpty) {
        payload['device_name'] = deviceName.trim();
      }
      if (deviceUuid != null && deviceUuid.trim().isNotEmpty) {
        payload['device_uuid'] = deviceUuid.trim();
      }
      if (deviceMac != null && deviceMac.trim().isNotEmpty) {
        payload['device_mac'] = deviceMac.trim();
      }
      if (deviceFingerprint != null && deviceFingerprint.trim().isNotEmpty) {
        payload['device_fingerprint'] = deviceFingerprint.trim();
      }

      await _db.from('attendance_records').insert(payload);
      debugPrint('[DB] Attendance marked for $studentName');
      return true;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST204' &&
          (e.message.contains('device_uuid') ||
              e.message.contains('device_name') ||
              e.message.contains('device_mac') ||
              e.message.contains('device_fingerprint'))) {
        await _db.from('attendance_records').insert({
          'attendance_session_id': sessionId,
          'student_id': studentId,
          'student_device_id': null,
          'status': 'Present',
          'marked_at': utcIsoNowForDb(),
        });
        debugPrint('[DB] Attendance marked for $studentName (legacy schema)');
        return true;
      }
      if (e.code == '23505') {
        debugPrint('[DB] Already marked!');
        return false;
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getAttendees(String sessionId) async {
    final rows = await _db
        .from('attendance_records')
        .select(
          'student_id, marked_at, device_name, device_uuid, device_fingerprint, students(full_name)',
        )
        .eq('attendance_session_id', sessionId)
        .order('marked_at');
    return rows.map((row) {
      final student = row['students'] as Map<String, dynamic>? ?? {};
      return <String, dynamic>{
        ...row,
        'student_name': (student['full_name'] as String?) ?? 'Student',
      };
    }).toList();
  }

  List<AttendanceAnomaly> detectSharedDeviceAnomalies(
    List<Map<String, dynamic>> attendees,
  ) {
    final buckets = <String, Set<String>>{};
    final labels = <String, String>{};

    for (final row in attendees) {
      final deviceUuid = (row['device_uuid'] as String?)?.trim();
      if (deviceUuid == null || deviceUuid.isEmpty) continue;

      final studentName =
          ((row['student_name'] as String?)?.trim().isNotEmpty ?? false)
              ? (row['student_name'] as String).trim()
              : ((row['student_id'] as String?) ?? 'Unknown student');
      final deviceName = (row['device_name'] as String?)?.trim();
      final displayName =
          (deviceName != null && deviceName.isNotEmpty) ? deviceName : 'Unknown device';
      final label = displayName;

      buckets.putIfAbsent(deviceUuid, () => <String>{}).add(studentName);
      labels.putIfAbsent(deviceUuid, () => label);
    }

    final anomalies = <AttendanceAnomaly>[];
    buckets.forEach((deviceUuid, students) {
      if (students.length < 2) return;
      final sortedStudents = students.toList()..sort();
      anomalies.add(
        AttendanceAnomaly(
          deviceLabel: labels[deviceUuid] ?? 'Unknown device',
          deviceUuid: deviceUuid,
          students: sortedStudents,
        ),
      );
    });

    anomalies.sort((a, b) => b.students.length.compareTo(a.students.length));
    return anomalies;
  }

  // Realtime stream â€” fires whenever session row changes
  Stream<bool> watchSessionActive(String sessionId) {
    return _db
        .from('attendance_sessions')
        .stream(primaryKey: ['id'])
        .eq('id', sessionId)
        .map((rows) => rows.isNotEmpty && (rows.first['is_active'] as bool));
  }

  /// In-app session alerts only (no OS/local notifications). Uses polling so
  /// alerts work without Supabase Realtime being enabled on `attendance_sessions`.
  Stream<List<SessionNotificationItem>> watchStudentSessionNotifications(
    String studentId,
  ) {
    Timer? timer;
    final controller = StreamController<List<SessionNotificationItem>>(
      onCancel: () => timer?.cancel(),
    );

    Future<void> start() async {
      final offerings = await getStudentOfferings(studentId.trim());
      final offeringById = {
        for (final offering in offerings) offering.id: offering,
      };
      if (offeringById.isEmpty) {
        if (!controller.isClosed) controller.add(const []);
        await controller.close();
        return;
      }

      final offeringIds = offeringById.keys.toList();
      final subscriptionOpenedAt = DateTime.now().toUtc();
      const skewPad = Duration(seconds: 45);
      final emitted = <String>{};

      Future<void> poll() async {
        if (controller.isClosed) return;
        try {
          final raw = await _db
              .from('attendance_sessions')
              .select('id, subject_offering_id, started_at')
              .eq('is_active', true)
              .inFilter('subject_offering_id', offeringIds);

          final notifications = <SessionNotificationItem>[];
          for (final row in raw) {
            final m = Map<String, dynamic>.from(row as Map<dynamic, dynamic>);
            final offeringId = _jsonStr(m['subject_offering_id']);
            if (offeringId.isEmpty || !offeringById.containsKey(offeringId)) {
              continue;
            }
            final sessionId = _jsonStr(m['id']);
            if (sessionId.isEmpty || emitted.contains(sessionId)) continue;

            final startedStr = m['started_at'];
            if (startedStr == null) continue;
            final startedAt = parseDbTimestamptzToLocal(startedStr);
            if (startedAt.isBefore(
              subscriptionOpenedAt.subtract(skewPad).toLocal(),
            )) {
              emitted.add(sessionId);
              continue;
            }

            emitted.add(sessionId);
            final offering = offeringById[offeringId]!;
            notifications.add(
              SessionNotificationItem(
                sessionId: sessionId,
                offeringId: offeringId,
                subjectCode: offering.subjectCode,
                subjectTitle: offering.subjectTitle,
                section: offering.section,
                teacherName: offering.teacherName,
                startedAt: startedAt,
              ),
            );
          }
          if (notifications.isNotEmpty && !controller.isClosed) {
            notifications.sort((a, b) => b.startedAt.compareTo(a.startedAt));
            controller.add(notifications);
          }
        } catch (e, st) {
          debugPrint('[watchStudentSessionNotifications] poll error: $e\n$st');
        }
      }

      await poll();
      timer = Timer.periodic(const Duration(seconds: 4), (_) {
        unawaited(poll());
      });
    }

    unawaited(start());
    return controller.stream;
  }

  Future<List<TeacherSessionHistoryItem>> getTeacherSessionHistory(
    String teacherId,
  ) async {
    final rows = await _db.rpc(
      'get_teacher_session_history',
      params: {'p_teacher_id': teacherId},
    );
    if (rows is! List) return [];

    return rows.map((row) {
      final map = row as Map<String, dynamic>;
      final endedRaw = map['ended_at'];
      final endedAt = (endedRaw == null ||
              (endedRaw is String && endedRaw.trim().isEmpty))
          ? null
          : parseDbTimestamptzToLocal(endedRaw);
      return TeacherSessionHistoryItem(
        sessionId: (map['session_id'] as String?) ?? '',
        subjectCode: (map['subject_code'] as String?) ?? 'SUBJECT',
        subjectTitle: (map['subject_title'] as String?) ?? 'Untitled',
        section: (map['section'] as String?) ?? 'N/A',
        startedAt: parseDbTimestamptzToLocal(map['started_at']),
        endedAt: endedAt,
        isActive: (map['is_active'] as bool?) ?? false,
      );
    }).toList();
  }

  Future<List<SessionAttendanceDetailItem>> getSessionAttendeesForTeacher({
    required String teacherId,
    required String sessionId,
  }) async {
    try {
      final rows = await _db.rpc(
        'get_teacher_session_attendees',
        params: {
          'p_teacher_id': teacherId.trim(),
          'p_session_id': sessionId,
        },
      );
      if (rows is! List) return [];

      return rows.map((row) {
        final map = row as Map<String, dynamic>;
        final isPresent = (map['is_present'] as bool?) ??
            (map['marked_at'] != null);
        final markedRaw = map['marked_at'];
        final markedAt = markedRaw == null
            ? null
            : parseDbTimestamptzToLocal(markedRaw);
        final deviceRaw = map['device_used'];
        final deviceStr =
            deviceRaw == null ? '' : _jsonStr(deviceRaw);
        return SessionAttendanceDetailItem(
          studentId: _jsonStr(map['student_id']),
          studentName: _jsonStr(map['student_name']).isEmpty
              ? 'Student'
              : _jsonStr(map['student_name']),
          isPresent: isPresent,
          markedAt: markedAt,
          deviceUsed: isPresent
              ? (deviceStr.isEmpty ? 'Unknown device' : deviceStr)
              : null,
        );
      }).toList();
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202') rethrow;

      // Fallback: all enrolled students; present only if there is a record.
      final sessionRow = await _db
          .from('attendance_sessions')
          .select('subject_offering_id')
          .eq('id', sessionId)
          .maybeSingle();
      if (sessionRow == null) return [];
      final offeringId = _jsonStr(sessionRow['subject_offering_id']);
      if (offeringId.isEmpty) return [];

      final owner = await _db
          .from('subject_offerings')
          .select('id')
          .eq('id', offeringId)
          .eq('teacher_id', teacherId.trim())
          .maybeSingle();
      if (owner == null) return [];

      final enrollRows = await _db
          .from('student_subject_enrollments')
          .select('student_id, students(full_name)')
          .eq('subject_offering_id', offeringId);

      final recordRows = await _db
          .from('attendance_records')
          .select(
            'student_id, marked_at, device_name, device_uuid, device_fingerprint',
          )
          .eq('attendance_session_id', sessionId);

      final byStudent = <String, Map<String, dynamic>>{};
      for (final r in recordRows) {
        final mm = Map<String, dynamic>.from(r as Map);
        final stuId = _jsonStr(mm['student_id']);
        if (stuId.isNotEmpty) {
          byStudent[stuId] = mm;
        }
      }

      final out = <SessionAttendanceDetailItem>[];
      for (final er in enrollRows) {
        final m = Map<String, dynamic>.from(er as Map);
        final stuId = _jsonStr(m['student_id']);
        final st = m['students'] as Map<String, dynamic>? ?? {};
        final name = _jsonStr(st['full_name']);
        final rec = byStudent[stuId];
        if (rec == null) {
          out.add(
            SessionAttendanceDetailItem(
              studentId: stuId,
              studentName: name.isEmpty ? 'Student' : name,
              isPresent: false,
            ),
          );
        } else {
          final deviceName = (rec['device_name'] as String?)?.trim();
          final fp = (rec['device_fingerprint'] as String?)?.trim();
          final hasUuid =
              ((rec['device_uuid'] as String?)?.trim().isNotEmpty ?? false);
          final deviceUsed = (deviceName != null && deviceName.isNotEmpty)
              ? deviceName
              : (hasUuid
                  ? 'Registered handset'
                  : ((fp != null && fp.isNotEmpty)
                      ? 'Registered device'
                      : 'Unknown device'));
          out.add(
            SessionAttendanceDetailItem(
              studentId: stuId,
              studentName: name.isEmpty ? 'Student' : name,
              isPresent: true,
              markedAt: parseDbTimestamptzToLocal(rec['marked_at']),
              deviceUsed: deviceUsed,
            ),
          );
        }
      }
      out.sort(
        (a, b) => a.studentName.toLowerCase().compareTo(
              b.studentName.toLowerCase(),
            ),
      );
      return out;
    }
  }

  /// Teacher override from session history: mark present (manual) or absent (remove record).
  Future<void> setTeacherSessionAttendance({
    required String teacherId,
    required String sessionId,
    required String studentId,
    required bool isPresent,
  }) async {
    final profId = teacherId.trim();
    final sessId = sessionId.trim();
    final stuId = studentId.trim();
    if (profId.isEmpty || sessId.isEmpty || stuId.isEmpty) {
      throw Exception('Missing session or student.');
    }

    final sessionRow = await _db
        .from('attendance_sessions')
        .select('subject_offering_id')
        .eq('id', sessId)
        .maybeSingle();
    if (sessionRow == null) {
      throw Exception('Session not found.');
    }
    final offeringId = _jsonStr(sessionRow['subject_offering_id']);
    final owner = await _db
        .from('subject_offerings')
        .select('id')
        .eq('id', offeringId)
        .eq('teacher_id', profId)
        .maybeSingle();
    if (owner == null) {
      throw Exception('You do not have access to this session.');
    }

    if (!isPresent) {
      await _db
          .from('attendance_records')
          .delete()
          .eq('attendance_session_id', sessId)
          .eq('student_id', stuId);
      return;
    }

    try {
      await _db.from('attendance_records').upsert(
        {
          'attendance_session_id': sessId,
          'student_id': stuId,
          'student_device_id': null,
          'status': 'Present',
          'marked_at': utcIsoNowForDb(),
          'device_name': 'Manual (teacher)',
        },
        onConflict: 'attendance_session_id,student_id',
      );
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST204' &&
          (e.message.contains('device_name') ||
              e.message.contains('onConflict'))) {
        await _db.from('attendance_records').upsert(
          {
            'attendance_session_id': sessId,
            'student_id': stuId,
            'student_device_id': null,
            'status': 'Present',
            'marked_at': utcIsoNowForDb(),
          },
          onConflict: 'attendance_session_id,student_id',
        );
        return;
      }
      rethrow;
    }
  }

  Future<List<AttendanceAnomaly>> getSessionDeviceAnomalies(
    String sessionId,
  ) async {
    final rows = await _db.rpc(
      'get_session_device_anomalies',
      params: {'p_session_id': sessionId},
    );
    if (rows is! List) return [];

    final anomalies = rows.map((row) {
      final map = row as Map<String, dynamic>;
      final rawUuid = (map['device_uuid'] as String?)?.trim() ?? '';
      final namesRaw = map['student_names'];
      final idsRaw = map['student_ids'];

      final names = namesRaw is List
          ? namesRaw.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
          : <String>[];
      final ids = idsRaw is List
          ? idsRaw.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
          : <String>[];
      // Prefer real names; never show raw student UUIDs in the UI.
      final students = names.isNotEmpty
          ? names
          : (ids.isNotEmpty ? <String>['Multiple students'] : <String>[]);

      return AttendanceAnomaly(
        deviceLabel: 'Shared device signal',
        deviceUuid: rawUuid,
        students: students,
      );
    }).toList();

    anomalies.sort((a, b) => b.students.length.compareTo(a.students.length));
    return anomalies;
  }

  Future<bool> hasStudentMarkedAttendance({
    required String sessionId,
    required String studentId,
  }) async {
    final rows = await _db
        .from('attendance_records')
        .select('id')
        .eq('attendance_session_id', sessionId)
        .eq('student_id', studentId)
        .limit(1);
    return rows.isNotEmpty;
  }

  Future<void> clearTeacherHistory(String teacherId) async {
    final id = teacherId.trim();
    try {
      await _db.rpc(
        'clear_teacher_history',
        params: {'p_teacher_id': id},
      );
      return;
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202') rethrow;
    }

    // Backward-compat: some deployments used a different RPC name.
    try {
      await _db.rpc(
        'clear_teacher_session_history',
        params: {'p_teacher_id': id},
      );
      return;
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202') rethrow;
    }

    // Final fallback: direct delete through teacher offerings.
    final rawOfferings = await _db
        .from('subject_offerings')
        .select('id')
        .eq('teacher_id', id);
    final offeringIds = rawOfferings
        .cast<Map<String, dynamic>>()
        .map((e) => e['id'] as String?)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList();
    if (offeringIds.isEmpty) return;

    final rawSessions = await _db
        .from('attendance_sessions')
        .select('id')
        .inFilter('subject_offering_id', offeringIds);

    final rows = rawSessions.cast<Map<String, dynamic>>();
    final ids = rows
        .map((e) => e['id'])
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList();

    const chunkSize = 100;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(
        i,
        (i + chunkSize) > ids.length ? ids.length : (i + chunkSize),
      );
      await _db
          .from('attendance_records')
          .delete()
          .inFilter('attendance_session_id', chunk);
    }

    await _db
        .from('attendance_sessions')
        .delete()
        .inFilter('subject_offering_id', offeringIds);
  }

  Future<List<StudentAttendanceHistoryItem>> getStudentAttendanceHistory(
    String studentId,
  ) async {
    final rows = await _db.rpc(
      'get_student_attendance_history',
      params: {'p_student_id': studentId},
    );
    if (rows is! List) return [];

    return rows.map((row) {
      final map = row as Map<String, dynamic>;

      return StudentAttendanceHistoryItem(
        subjectCode: (map['subject_code'] as String?) ?? 'SUBJECT',
        subjectTitle: (map['subject_title'] as String?) ?? 'Untitled',
        section: (map['section'] as String?) ?? 'N/A',
        teacherName: (map['teacher_name'] as String?) ?? 'Teacher',
        sessionStartedAt:
            parseDbTimestamptzToLocal(map['session_started_at'] as String),
        markedAt: parseDbTimestamptzToLocal(map['marked_at'] as String),
      );
    }).toList();
  }

  Future<void> clearStudentHistory(String studentId) async {
    final id = studentId.trim();
    try {
      await _db.rpc(
        'clear_student_history',
        params: {'p_student_id': id},
      );
      return;
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202') rethrow;
    }

    // Final fallback: direct delete (RLS allows deletes).
    await _db.from('attendance_records').delete().eq('student_id', id);
  }
}
