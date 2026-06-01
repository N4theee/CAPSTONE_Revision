import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../util/db_timestamptz.dart';

// ── Models ──────────────────────────────────────────────────────────────────

class ExamSession {
  const ExamSession({
    required this.id,
    required this.subjectOfferingId,
    required this.teacherId,
    required this.examTitle,
    required this.examCode,
    required this.bleUuid,
    required this.rssiThreshold,
    required this.gracePeriodSeconds,
    required this.status,
    this.startsAt,
    this.endsAt,
    required this.createdAt,
  });

  final String id;
  final String subjectOfferingId;
  final String teacherId;
  final String examTitle;
  final String examCode;
  final String bleUuid;
  final int rssiThreshold;
  final int gracePeriodSeconds;
  final String status;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime createdAt;

  bool get isActive => status == 'active';

  bool get isPaused => status == 'paused';

  bool get isTerminal =>
      status == 'ended' || status == 'cancelled';

  bool get isJoinable => status == 'active';
}

class ExamAttempt {
  const ExamAttempt({
    required this.id,
    required this.examSessionId,
    required this.studentId,
    required this.status,
    required this.startedAt,
    this.endedAt,
    this.violationCount = 0,
  });

  final String id;
  final String examSessionId;
  final String studentId;
  final String status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int violationCount;

  bool get isTerminal =>
      status == 'completed' || status == 'auto_ended' || status == 'flagged';
}

class ExamAttemptMonitorRow {
  const ExamAttemptMonitorRow({
    required this.attemptId,
    required this.studentId,
    required this.studentName,
    required this.attemptStatus,
    required this.proximityLabel,
    required this.isInRange,
    required this.violationCount,
    this.startedAt,
  });

  final String attemptId;
  final String studentId;
  final String studentName;
  final String attemptStatus;
  final String proximityLabel;
  final bool? isInRange;
  final int violationCount;
  final DateTime? startedAt;
}

class ExamAlertItem {
  const ExamAlertItem({
    required this.id,
    required this.examSessionId,
    required this.studentId,
    required this.alertType,
    required this.message,
    required this.createdAt,
    this.studentName,
    this.examAttemptId,
  });

  final String id;
  final String examSessionId;
  final String studentId;
  final String alertType;
  final String message;
  final DateTime createdAt;
  final String? studentName;
  final String? examAttemptId;
}

class ExamRankingRow {
  const ExamRankingRow({
    required this.studentId,
    required this.studentName,
    required this.examScore,
    required this.speedPoints,
    required this.violationPenalty,
    required this.overallScore,
    this.rankNumber,
    this.remarks,
  });

  final String studentId;
  final String studentName;
  final double examScore;
  final double speedPoints;
  final double violationPenalty;
  final double overallScore;
  final int? rankNumber;
  final String? remarks;
}

class StudentExamHistoryItem {
  const StudentExamHistoryItem({
    required this.attemptId,
    required this.examSessionId,
    required this.examTitle,
    required this.examCode,
    required this.subjectCode,
    required this.subjectTitle,
    required this.section,
    required this.status,
    required this.startedAt,
    this.endedAt,
    required this.violationCount,
  });

  final String attemptId;
  final String examSessionId;
  final String examTitle;
  final String examCode;
  final String subjectCode;
  final String subjectTitle;
  final String section;
  final String status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int violationCount;
}

/// Thrown when exam validation or persistence fails in a user-visible way.
class ExamServiceException implements Exception {
  ExamServiceException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      cause == null ? message : '$message (${cause.toString()})';
}

// ── Service ─────────────────────────────────────────────────────────────────

class ExamService {
  static final ExamService _i = ExamService._();
  factory ExamService() => _i;
  ExamService._();

  final _db = Supabase.instance.client;

  static String _jsonStr(dynamic v) {
    if (v == null) return '';
    if (v is String) return v.trim();
    return v.toString().trim();
  }

  ExamSession _examSessionFromMap(Map<String, dynamic> m) {
    return ExamSession(
      id: _jsonStr(m['id']),
      subjectOfferingId: _jsonStr(m['subject_offering_id']),
      teacherId: _jsonStr(m['teacher_id']),
      examTitle: _jsonStr(m['exam_title']),
      examCode: _jsonStr(m['exam_code']),
      bleUuid: _jsonStr(m['ble_uuid']),
      rssiThreshold: (m['rssi_threshold'] as num?)?.toInt() ?? -85,
      gracePeriodSeconds: (m['grace_period_seconds'] as num?)?.toInt() ?? 30,
      status: _jsonStr(m['status']).isEmpty ? 'scheduled' : _jsonStr(m['status']),
      startsAt: tryParseDbTimestamptzToLocal(m['starts_at']),
      endsAt: tryParseDbTimestamptzToLocal(m['ends_at']),
      createdAt: tryParseDbTimestamptzToLocal(m['created_at']) ?? DateTime.now(),
    );
  }

  ExamAttempt _examAttemptFromMap(Map<String, dynamic> m) {
    return ExamAttempt(
      id: _jsonStr(m['id']),
      examSessionId: _jsonStr(m['exam_session_id']),
      studentId: _jsonStr(m['student_id']),
      status: _jsonStr(m['status']).isEmpty ? 'in_progress' : _jsonStr(m['status']),
      startedAt:
          tryParseDbTimestamptzToLocal(m['started_at']) ?? DateTime.now(),
      endedAt: tryParseDbTimestamptzToLocal(m['ended_at']),
      violationCount: (m['violation_count'] as num?)?.toInt() ?? 0,
    );
  }

  ExamAlertItem _examAlertFromMap(dynamic row) {
    final m = Map<String, dynamic>.from(row as Map<dynamic, dynamic>);
    final students = m['students'];
    String? studentName;
    if (students is Map) {
      final n = _jsonStr(students['full_name']);
      if (n.isNotEmpty) studentName = n;
    }
    return ExamAlertItem(
      id: _jsonStr(m['id']),
      examSessionId: _jsonStr(m['exam_session_id']),
      studentId: _jsonStr(m['student_id']),
      alertType: _jsonStr(m['alert_type']),
      message: _jsonStr(m['message']).isEmpty
          ? _defaultExamAlertMessage(_jsonStr(m['alert_type']))
          : _jsonStr(m['message']),
      createdAt:
          tryParseDbTimestamptzToLocal(m['created_at']) ?? DateTime.now(),
      studentName: studentName,
      examAttemptId: _jsonStr(m['exam_attempt_id']).isEmpty
          ? null
          : _jsonStr(m['exam_attempt_id']),
    );
  }

  String _defaultExamAlertMessage(String alertType) {
    return teacherAlertMessage(
      alertType: alertType,
      studentName: 'A student',
    );
  }

  /// Teacher/proctor-facing alert copy (also used as default DB message).
  static String teacherAlertMessage({
    required String alertType,
    required String studentName,
  }) {
    final name = studentName.trim().isEmpty ? 'A student' : studentName.trim();
    switch (alertType) {
      case 'out_of_range':
        return '$name went out of exam range.';
      case 'returned_in_range':
        return '$name returned within range.';
      case 'auto_ended':
        return '$name was auto-ended due to prolonged out-of-range status.';
      default:
        return '$name: $alertType';
    }
  }

  /// Student row badge on teacher monitor (In Range / Out of Range / Auto Ended / Completed).
  static String studentMonitorStatusLabel(ExamAttemptMonitorRow row) {
    switch (row.attemptStatus) {
      case 'auto_ended':
        return 'Auto Ended';
      case 'completed':
        return 'Completed';
      case 'flagged':
        return 'Flagged';
      default:
        if (row.isInRange == false) return 'Out of Range';
        return 'In Range';
    }
  }

  Never _rethrowPostgrest(Object e, String context) {
    if (e is PostgrestException) {
      debugPrint('[ExamService] $context: ${e.message} (code=${e.code})');
      throw ExamServiceException(
        e.message.isNotEmpty ? e.message : context,
        cause: e,
      );
    }
    debugPrint('[ExamService] $context: $e');
    throw ExamServiceException(context, cause: e);
  }

  // ── 1) Create exam session ───────────────────────────────────────────────

  Future<String> generateUniqueExamCode() async {
    try {
      final raw = await _db.rpc('generate_unique_exam_code');
      if (raw is String && raw.trim().isNotEmpty) return raw.trim();
      throw ExamServiceException('Could not generate exam code');
    } catch (e) {
      if (e is ExamServiceException) rethrow;
      _rethrowPostgrest(e, 'generateUniqueExamCode failed');
    }
  }

  /// Inserts into [exam_sessions]. Pass [examCode] or let the DB RPC generate one.
  Future<ExamSession> createExamSession({
    required String subjectOfferingId,
    required String teacherId,
    required String examTitle,
    required String bleUuid,
    required String status,
    int rssiThreshold = -85,
    int gracePeriodSeconds = 30,
    DateTime? startsAt,
    DateTime? endsAt,
    String? examCode,
  }) async {
    try {
      final code = (examCode != null && examCode.trim().isNotEmpty)
          ? examCode.trim().toUpperCase()
          : await generateUniqueExamCode();

      final payload = <String, dynamic>{
        'subject_offering_id': subjectOfferingId.trim(),
        'teacher_id': teacherId.trim(),
        'exam_title': examTitle.trim(),
        'exam_code': code,
        'ble_uuid': bleUuid.trim(),
        'rssi_threshold': rssiThreshold,
        'grace_period_seconds': gracePeriodSeconds,
        'status': status,
      };
      if (startsAt != null) {
        payload['starts_at'] = startsAt.toUtc().toIso8601String();
      }
      if (endsAt != null) {
        payload['ends_at'] = endsAt.toUtc().toIso8601String();
      }

      final row = await _db
          .from('exam_sessions')
          .insert(payload)
          .select()
          .single();
      debugPrint('[ExamService] Session created: ${row['id']} ($code)');
      return _examSessionFromMap(Map<String, dynamic>.from(row));
    } catch (e) {
      if (e is ExamServiceException) rethrow;
      _rethrowPostgrest(e, 'createExamSession failed');
    }
  }

  // ── 2) Active sessions by offering ─────────────────────────────────────────

  Future<List<ExamSession>> getActiveExamSessionsBySubjectOffering(
    String subjectOfferingId,
  ) async {
    try {
      final rows = await _db
          .from('exam_sessions')
          .select()
          .eq('subject_offering_id', subjectOfferingId.trim())
          .eq('status', 'active')
          .order('created_at', ascending: false);
      return rows
          .map((e) => _examSessionFromMap(
                Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
              ))
          .toList();
    } catch (e) {
      _rethrowPostgrest(e, 'getActiveExamSessionsBySubjectOffering failed');
    }
  }

  /// Latest active or scheduled session (teacher hub convenience).
  Future<ExamSession?> getActiveExamSessionForOffering(String offeringId) async {
    try {
      final rows = await _db
          .from('exam_sessions')
          .select()
          .eq('subject_offering_id', offeringId)
          .inFilter('status', ['active', 'scheduled', 'paused'])
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) return null;
      return _examSessionFromMap(
        Map<String, dynamic>.from(rows.first as Map<dynamic, dynamic>),
      );
    } catch (e) {
      _rethrowPostgrest(e, 'getActiveExamSessionForOffering failed');
    }
  }

  Future<List<ExamSession>> getExamSessionsForOffering(String offeringId) async {
    try {
      final rows = await _db
          .from('exam_sessions')
          .select()
          .eq('subject_offering_id', offeringId)
          .order('created_at', ascending: false);
      return rows
          .map((e) => _examSessionFromMap(
                Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
              ))
          .toList();
    } catch (e) {
      _rethrowPostgrest(e, 'getExamSessionsForOffering failed');
    }
  }

  Future<ExamSession?> getExamSessionById(String sessionId) async {
    try {
      final row = await _db
          .from('exam_sessions')
          .select()
          .eq('id', sessionId)
          .maybeSingle();
      if (row == null) return null;
      return _examSessionFromMap(Map<String, dynamic>.from(row));
    } catch (e) {
      _rethrowPostgrest(e, 'getExamSessionById failed');
    }
  }

  Future<void> endExamSession(String sessionId) async {
    await updateExamSessionStatus(sessionId, 'ended', setEndsAt: true);
  }

  Future<void> activateExamSession(String sessionId) async {
    await updateExamSessionStatus(sessionId, 'active', setStartsAt: true);
  }

  Future<void> pauseExamSession(String sessionId) async {
    await updateExamSessionStatus(sessionId, 'paused');
  }

  Future<void> resumeExamSession(String sessionId) async {
    await updateExamSessionStatus(sessionId, 'active');
  }

  Future<void> cancelExamSession(String sessionId) async {
    await updateExamSessionStatus(sessionId, 'cancelled', setEndsAt: true);
  }

  Future<void> updateExamSessionStatus(
    String sessionId,
    String status, {
    bool setStartsAt = false,
    bool setEndsAt = false,
  }) async {
    try {
      final payload = <String, dynamic>{'status': status};
      if (setStartsAt) {
        payload['starts_at'] = utcIsoNowForDb();
      }
      if (setEndsAt) {
        payload['ends_at'] = utcIsoNowForDb();
      }
      await _db.from('exam_sessions').update(payload).eq('id', sessionId);
      debugPrint('[ExamService] Session $sessionId → $status');
    } catch (e) {
      _rethrowPostgrest(e, 'updateExamSessionStatus failed');
    }
  }

  /// Normalizes codes like `exm-7k92q` → `EXM-7K92Q`.
  static String normalizeExamCode(String raw) {
    return raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }

  /// Uses the more lenient (more negative) RSSI so exam join matches attendance.
  static int effectiveProximityRssi(int sessionRssi) {
    return sessionRssi < AppConfig.rssiThreshold
        ? sessionRssi
        : AppConfig.rssiThreshold;
  }

  /// Prefer session UUID; fall back to the class offering beacon.
  static String resolveBeaconUuid({
    required ExamSession session,
    required String offeringBeaconUuid,
  }) {
    final fromSession = session.bleUuid.trim();
    if (fromSession.isNotEmpty) return fromSession;
    return offeringBeaconUuid.trim();
  }

  // ── 3) Validate exam code ──────────────────────────────────────────────────

  /// Ensures [examCode] exists, is joinable, and belongs to [subjectOfferingId].
  Future<ExamSession> validateExamCode({
    required String examCode,
    required String subjectOfferingId,
  }) async {
    final code = normalizeExamCode(examCode);
    if (code.isEmpty) {
      throw ExamServiceException('Enter a valid exam code.');
    }

    try {
      final rows = await _db
          .from('exam_sessions')
          .select()
          .ilike('exam_code', code)
          .limit(5);

      if (rows.isEmpty) {
        throw ExamServiceException(
          'Exam not found. Check the code, confirm your teacher started the exam, '
          'and that exam tables are set up in Supabase (exam_sessions_schema.sql).',
        );
      }

      ExamSession? session;
      for (final row in rows) {
        final s = _examSessionFromMap(
          Map<String, dynamic>.from(row as Map<dynamic, dynamic>),
        );
        if (normalizeExamCode(s.examCode) == code) {
          session = s;
          break;
        }
      }
      session ??= _examSessionFromMap(
        Map<String, dynamic>.from(rows.first as Map<dynamic, dynamic>),
      );

      if (session.subjectOfferingId != subjectOfferingId.trim()) {
        throw ExamServiceException(
          'This exam code is for a different class. Open the correct subject, then join again.',
        );
      }

      if (session.status == 'scheduled') {
        final now = DateTime.now().toUtc();
        final start = session.startsAt?.toUtc();
        if (start == null || !start.isAfter(now)) {
          await activateExamSession(session.id);
          final refreshed = await getExamSessionById(session.id);
          if (refreshed == null) {
            throw ExamServiceException('Could not activate exam session.');
          }
          return refreshed;
        }
        throw ExamServiceException(
          'Exam is scheduled for later (${_fmtLocal(session.startsAt)}). '
          'Ask your teacher to start the exam now.',
        );
      }

      if (session.status == 'paused') {
        throw ExamServiceException(
          'Exam is paused. Ask your teacher to resume before you join.',
        );
      }

      if (session.status == 'ended') {
        throw ExamServiceException('This exam has already ended.');
      }

      if (session.status == 'cancelled') {
        throw ExamServiceException('This exam was cancelled by the teacher.');
      }

      if (!session.isJoinable) {
        throw ExamServiceException(
          'Exam is not open for joining (status: ${session.status}).',
        );
      }

      return session;
    } on ExamServiceException {
      rethrow;
    } on PostgrestException catch (e) {
      if (e.code == '42P01' ||
          (e.message.contains('exam_sessions') &&
              e.message.toLowerCase().contains('does not exist'))) {
        throw ExamServiceException(
          'Exam database tables are missing. Run supabase/exam_sessions_schema.sql '
          'in the Supabase SQL Editor, then try again.',
        );
      }
      _rethrowPostgrest(e, 'validateExamCode failed');
    } catch (e) {
      _rethrowPostgrest(e, 'validateExamCode failed');
    }
  }

  String _fmtLocal(DateTime? dt) {
    if (dt == null) return '—';
    final l = dt.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Future<bool> isStudentEnrolledInOffering(
    String studentId,
    String offeringId,
  ) async {
    try {
      final row = await _db
          .from('student_subject_enrollments')
          .select('id')
          .eq('student_id', studentId.trim())
          .eq('subject_offering_id', offeringId.trim())
          .maybeSingle();
      return row != null;
    } catch (e) {
      _rethrowPostgrest(e, 'isStudentEnrolledInOffering failed');
    }
  }

  // ── 4) Exam attempts ─────────────────────────────────────────────────────

  Future<ExamAttempt?> getExamAttemptById(String attemptId) async {
    try {
      final row = await _db
          .from('exam_attempts')
          .select()
          .eq('id', attemptId)
          .maybeSingle();
      if (row == null) return null;
      return _examAttemptFromMap(Map<String, dynamic>.from(row));
    } catch (e) {
      _rethrowPostgrest(e, 'getExamAttemptById failed');
    }
  }

  Future<ExamAttempt?> getStudentExamAttempt({
    required String examSessionId,
    required String studentId,
  }) async {
    try {
      final row = await _db
          .from('exam_attempts')
          .select()
          .eq('exam_session_id', examSessionId)
          .eq('student_id', studentId.trim())
          .maybeSingle();
      if (row == null) return null;
      return _examAttemptFromMap(Map<String, dynamic>.from(row));
    } catch (e) {
      _rethrowPostgrest(e, 'getStudentExamAttempt failed');
    }
  }

  /// Creates a new attempt or returns the existing [in_progress] row (unique per session+student).
  Future<ExamAttempt> createExamAttempt({
    required String examSessionId,
    required String studentId,
  }) async {
    final sid = studentId.trim();
    try {
      final existing = await getStudentExamAttempt(
        examSessionId: examSessionId,
        studentId: sid,
      );
      if (existing != null) {
        if (existing.status == 'in_progress') {
          debugPrint('[ExamService] Reusing in_progress attempt ${existing.id}');
          return existing;
        }
        throw ExamServiceException(
          'You already have an attempt for this exam (${existing.status}).',
        );
      }

      final row = await _db
          .from('exam_attempts')
          .insert({
            'exam_session_id': examSessionId,
            'student_id': sid,
            'status': 'in_progress',
          })
          .select()
          .single();
      debugPrint('[ExamService] Attempt created: ${row['id']}');
      return _examAttemptFromMap(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      if (e.code == '23505' ||
          (e.message.contains('duplicate key') ||
              e.message.contains('unique constraint'))) {
        final retry = await getStudentExamAttempt(
          examSessionId: examSessionId,
          studentId: sid,
        );
        if (retry != null && retry.status == 'in_progress') return retry;
      }
      _rethrowPostgrest(e, 'createExamAttempt failed');
    } catch (e) {
      if (e is ExamServiceException) rethrow;
      _rethrowPostgrest(e, 'createExamAttempt failed');
    }
  }

  // ── 5) Proximity logs ──────────────────────────────────────────────────────

  Future<void> saveProximityLog({
    required String examAttemptId,
    required String studentId,
    required String examSessionId,
    required bool isInRange,
    int? rssi,
  }) async {
    try {
      await _db.from('exam_proximity_logs').insert({
        'exam_attempt_id': examAttemptId,
        'student_id': studentId.trim(),
        'exam_session_id': examSessionId,
        'is_in_range': isInRange,
        if (rssi != null) 'rssi': rssi,
      });
    } catch (e) {
      _rethrowPostgrest(e, 'saveProximityLog failed');
    }
  }

  // ── 6) Alerts ──────────────────────────────────────────────────────────────

  Future<void> createExamAlert({
    required String examSessionId,
    required String studentId,
    required String alertType,
    String? message,
    String? examAttemptId,
  }) async {
    const allowed = {'out_of_range', 'returned_in_range', 'auto_ended'};
    if (!allowed.contains(alertType)) {
      throw ExamServiceException('Invalid alert type: $alertType');
    }
    try {
      await _db.from('exam_alerts').insert({
        'exam_session_id': examSessionId,
        'student_id': studentId.trim(),
        'alert_type': alertType,
        if (message != null && message.trim().isNotEmpty)
          'message': message.trim(),
        if (examAttemptId != null && examAttemptId.isNotEmpty)
          'exam_attempt_id': examAttemptId,
      });
    } catch (e) {
      _rethrowPostgrest(e, 'createExamAlert failed');
    }
  }

  Future<List<ExamAlertItem>> fetchExamAlerts(String examSessionId) async {
    try {
      final rows = await _db
          .from('exam_alerts')
          .select(
            'id, exam_session_id, exam_attempt_id, student_id, alert_type, message, created_at, students(full_name)',
          )
          .eq('exam_session_id', examSessionId)
          .order('created_at', ascending: false)
          .limit(100);
      return rows.map(_examAlertFromMap).toList();
    } catch (e) {
      _rethrowPostgrest(e, 'fetchExamAlerts failed');
    }
  }

  // ── 7) Update attempt status ───────────────────────────────────────────────

  Future<void> updateExamAttemptStatus({
    required String attemptId,
    required String status,
    DateTime? endedAt,
    int? violationCount,
  }) async {
    const allowed = {
      'in_progress',
      'completed',
      'flagged',
      'auto_ended',
    };
    if (!allowed.contains(status)) {
      throw ExamServiceException('Invalid attempt status: $status');
    }
    try {
      final payload = <String, dynamic>{'status': status};
      if (endedAt != null) {
        payload['ended_at'] = endedAt.toUtc().toIso8601String();
      } else if (status == 'completed' ||
          status == 'auto_ended' ||
          status == 'flagged') {
        payload['ended_at'] = utcIsoNowForDb();
      }
      if (violationCount != null) {
        payload['violation_count'] = violationCount;
      }
      await _db.from('exam_attempts').update(payload).eq('id', attemptId);
      debugPrint('[ExamService] Attempt $attemptId → $status');
    } catch (e) {
      if (e is ExamServiceException) rethrow;
      _rethrowPostgrest(e, 'updateExamAttemptStatus failed');
    }
  }

  // ── 8) Realtime alerts ─────────────────────────────────────────────────────

  /// Listens to [exam_alerts] for [examSessionId] (realtime with polling fallback).
  Stream<List<ExamAlertItem>> listenToExamAlerts(String examSessionId) {
    final controller = StreamController<List<ExamAlertItem>>();
    StreamSubscription<List<Map<String, dynamic>>>? sub;
    Timer? pollTimer;
    var useStream = true;

    Future<void> emitFromFetch() async {
      if (controller.isClosed) return;
      try {
        final items = await fetchExamAlerts(examSessionId);
        if (!controller.isClosed) controller.add(items);
      } catch (e, st) {
        debugPrint('[ExamService] listenToExamAlerts fetch: $e\n$st');
      }
    }

    void startPolling() {
      pollTimer?.cancel();
      pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        unawaited(emitFromFetch());
      });
    }

    controller.onListen = () async {
      await emitFromFetch();
      try {
        sub = _db
            .from('exam_alerts')
            .stream(primaryKey: ['id'])
            .eq('exam_session_id', examSessionId)
            .order('created_at', ascending: false)
            .listen(
          (rows) {
            if (controller.isClosed) return;
            controller.add(rows.map(_examAlertFromMap).toList());
          },
          onError: (Object e, StackTrace st) {
            debugPrint('[ExamService] listenToExamAlerts stream: $e\n$st');
            if (useStream) {
              useStream = false;
              sub?.cancel();
              startPolling();
            }
          },
        );
      } catch (e, st) {
        debugPrint('[ExamService] listenToExamAlerts setup: $e\n$st');
        useStream = false;
        startPolling();
      }
      if (!useStream) startPolling();
    };

    controller.onCancel = () async {
      await sub?.cancel();
      pollTimer?.cancel();
    };

    return controller.stream;
  }

  // ── 9) Rankings ────────────────────────────────────────────────────────────

  Future<List<ExamRankingRow>> getExamRankings(String examSessionId) async {
    try {
      final rows = await _db
          .from('exam_rankings')
          .select(
            'student_id, exam_score, speed_points, violation_penalty, overall_score, rank_number, remarks, students(full_name)',
          )
          .eq('exam_session_id', examSessionId)
          .order('rank_number', ascending: true);

      final list = rows.map((row) {
        final m = Map<String, dynamic>.from(row as Map<dynamic, dynamic>);
        final students = m['students'];
        var name = 'Student';
        if (students is Map) {
          final n = _jsonStr(students['full_name']);
          if (n.isNotEmpty) name = n;
        }
        return ExamRankingRow(
          studentId: _jsonStr(m['student_id']),
          studentName: name,
          examScore: (m['exam_score'] as num?)?.toDouble() ?? 0,
          speedPoints: (m['speed_points'] as num?)?.toDouble() ?? 0,
          violationPenalty: (m['violation_penalty'] as num?)?.toDouble() ?? 0,
          overallScore: (m['overall_score'] as num?)?.toDouble() ?? 0,
          rankNumber: (m['rank_number'] as num?)?.toInt(),
          remarks: (m['remarks'] as String?)?.trim(),
        );
      }).toList();

      list.sort((a, b) {
        final ar = a.rankNumber;
        final br = b.rankNumber;
        if (ar != null && br != null) return ar.compareTo(br);
        if (ar != null) return -1;
        if (br != null) return 1;
        return b.overallScore.compareTo(a.overallScore);
      });
      return list;
    } catch (e) {
      _rethrowPostgrest(e, 'getExamRankings failed');
    }
  }

  // ── Teacher monitor / student history helpers ──────────────────────────────

  Future<List<ExamAttemptMonitorRow>> getExamAttemptMonitorRows(
    String examSessionId,
  ) async {
    try {
      final attemptsRaw = await _db
          .from('exam_attempts')
          .select(
            'id, student_id, status, violation_count, started_at, students(full_name)',
          )
          .eq('exam_session_id', examSessionId)
          .order('started_at', ascending: true);

      final logsRaw = await _db
          .from('exam_proximity_logs')
          .select('exam_attempt_id, is_in_range, created_at')
          .eq('exam_session_id', examSessionId)
          .order('created_at', ascending: false);

      final latestInRange = <String, bool>{};
      for (final row in logsRaw) {
        final m = Map<String, dynamic>.from(row as Map<dynamic, dynamic>);
        final attemptId = _jsonStr(m['exam_attempt_id']);
        if (attemptId.isEmpty || latestInRange.containsKey(attemptId)) continue;
        latestInRange[attemptId] = m['is_in_range'] as bool? ?? false;
      }

      final rows = <ExamAttemptMonitorRow>[];
      for (final row in attemptsRaw) {
        final m = Map<String, dynamic>.from(row as Map<dynamic, dynamic>);
        final attemptId = _jsonStr(m['id']);
        final status =
            _jsonStr(m['status']).isEmpty ? 'in_progress' : _jsonStr(m['status']);
        final students = m['students'];
        var studentName = 'Student';
        if (students is Map) {
          studentName = _jsonStr(students['full_name']);
          if (studentName.isEmpty) studentName = 'Student';
        }

        final proximity = _proximityLabelForAttempt(
          status,
          latestInRange[attemptId],
        );
        rows.add(
          ExamAttemptMonitorRow(
            attemptId: attemptId,
            studentId: _jsonStr(m['student_id']),
            studentName: studentName,
            attemptStatus: status,
            proximityLabel: proximity.label,
            isInRange: proximity.isInRange,
            violationCount: (m['violation_count'] as num?)?.toInt() ?? 0,
            startedAt: tryParseDbTimestamptzToLocal(m['started_at']),
          ),
        );
      }
      return rows;
    } catch (e) {
      _rethrowPostgrest(e, 'getExamAttemptMonitorRows failed');
    }
  }

  ({String label, bool? isInRange}) _proximityLabelForAttempt(
    String status,
    bool? latestInRange,
  ) {
    switch (status) {
      case 'auto_ended':
        return (label: 'Auto Ended', isInRange: false);
      case 'completed':
        return (label: 'Completed', isInRange: latestInRange);
      case 'flagged':
        return (label: 'Flagged', isInRange: latestInRange);
      default:
        if (latestInRange == false) {
          return (label: 'Out of Range', isInRange: false);
        }
        return (label: 'In Range', isInRange: latestInRange ?? true);
    }
  }

  Future<List<StudentExamHistoryItem>> getStudentExamHistory(
    String studentId, {
    String? offeringId,
    String subjectCode = 'SUBJECT',
    String subjectTitle = 'Untitled',
    String section = 'N/A',
  }) async {
    try {
      List<Map<String, dynamic>> rows;
      try {
        rows = List<Map<String, dynamic>>.from(
          await _db
              .from('exam_attempts')
              .select(
                'id, exam_session_id, status, started_at, ended_at, violation_count, '
                'exam_sessions(exam_title, exam_code, subject_offering_id)',
              )
              .eq('student_id', studentId.trim())
              .order('started_at', ascending: false),
        );
      } catch (_) {
        return _getStudentExamHistoryFallback(
          studentId,
          offeringId,
          subjectCode: subjectCode,
          subjectTitle: subjectTitle,
          section: section,
        );
      }

      final list = <StudentExamHistoryItem>[];
      for (final m in rows) {
        final sess = m['exam_sessions'];
        if (sess is! Map) continue;
        final sm = Map<String, dynamic>.from(sess);
        final sessionOfferingId = _jsonStr(sm['subject_offering_id']);
        if (offeringId != null &&
            offeringId.isNotEmpty &&
            sessionOfferingId != offeringId) {
          continue;
        }

        list.add(
          StudentExamHistoryItem(
            attemptId: _jsonStr(m['id']),
            examSessionId: _jsonStr(m['exam_session_id']),
            examTitle: _jsonStr(sm['exam_title']),
            examCode: _jsonStr(sm['exam_code']),
            subjectCode: subjectCode,
            subjectTitle: subjectTitle,
            section: section,
            status: _jsonStr(m['status']),
            startedAt:
                tryParseDbTimestamptzToLocal(m['started_at']) ?? DateTime.now(),
            endedAt: tryParseDbTimestamptzToLocal(m['ended_at']),
            violationCount: (m['violation_count'] as num?)?.toInt() ?? 0,
          ),
        );
      }

      if (list.isNotEmpty || offeringId == null) return list;

      return _getStudentExamHistoryFallback(
        studentId,
        offeringId,
        subjectCode: subjectCode,
        subjectTitle: subjectTitle,
        section: section,
      );
    } catch (e) {
      _rethrowPostgrest(e, 'getStudentExamHistory failed');
    }
  }

  Future<List<StudentExamHistoryItem>> _getStudentExamHistoryFallback(
    String studentId,
    String? offeringId, {
    String subjectCode = 'SUBJECT',
    String subjectTitle = 'Untitled',
    String section = 'N/A',
  }) async {
    final rows = await _db
        .from('exam_attempts')
        .select()
        .eq('student_id', studentId.trim())
        .order('started_at', ascending: false);

    final sessionsById = <String, ExamSession>{};
    final list = <StudentExamHistoryItem>[];

    for (final row in rows) {
      final m = Map<String, dynamic>.from(row as Map<dynamic, dynamic>);
      final sessionId = _jsonStr(m['exam_session_id']);
      ExamSession? sess = sessionsById[sessionId];
      sess ??= await getExamSessionById(sessionId);
      if (sess == null) continue;
      sessionsById[sessionId] = sess;

      if (offeringId != null &&
          offeringId.isNotEmpty &&
          sess.subjectOfferingId != offeringId) {
        continue;
      }

      list.add(
        StudentExamHistoryItem(
          attemptId: _jsonStr(m['id']),
          examSessionId: sessionId,
          examTitle: sess.examTitle,
          examCode: sess.examCode,
          subjectCode: subjectCode,
          subjectTitle: subjectTitle,
          section: section,
          status: _jsonStr(m['status']),
          startedAt:
              tryParseDbTimestamptzToLocal(m['started_at']) ?? DateTime.now(),
          endedAt: tryParseDbTimestamptzToLocal(m['ended_at']),
          violationCount: (m['violation_count'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return list;
  }

  // ── Clear history ──────────────────────────────────────────────────────────

  /// Removes this student's attempts (and related logs/alerts/rankings) for one class.
  Future<void> clearStudentExamHistoryForOffering({
    required String studentId,
    required String subjectOfferingId,
  }) async {
    try {
      final sessionsRaw = await _db
          .from('exam_sessions')
          .select('id')
          .eq('subject_offering_id', subjectOfferingId.trim());
      final sessionIds = sessionsRaw
          .map((r) => _jsonStr(
                Map<String, dynamic>.from(r as Map<dynamic, dynamic>)['id'],
              ))
          .where((id) => id.isNotEmpty)
          .toList();
      if (sessionIds.isEmpty) return;

      final attemptsRaw = await _db
          .from('exam_attempts')
          .select('id')
          .eq('student_id', studentId.trim())
          .inFilter('exam_session_id', sessionIds);
      final attemptIds = attemptsRaw
          .map((r) => _jsonStr(
                Map<String, dynamic>.from(r as Map<dynamic, dynamic>)['id'],
              ))
          .where((id) => id.isNotEmpty)
          .toList();

      if (attemptIds.isNotEmpty) {
        await _db.from('exam_alerts').delete().inFilter('exam_attempt_id', attemptIds);
        await _db
            .from('exam_proximity_logs')
            .delete()
            .inFilter('exam_attempt_id', attemptIds);
      }

      await _db
          .from('exam_rankings')
          .delete()
          .eq('student_id', studentId.trim())
          .inFilter('exam_session_id', sessionIds);

      await _db
          .from('exam_alerts')
          .delete()
          .eq('student_id', studentId.trim())
          .inFilter('exam_session_id', sessionIds);

      await _db
          .from('exam_attempts')
          .delete()
          .eq('student_id', studentId.trim())
          .inFilter('exam_session_id', sessionIds);

      debugPrint(
        '[ExamService] Cleared exam history for student $studentId offering $subjectOfferingId',
      );
    } catch (e) {
      _rethrowPostgrest(e, 'clearStudentExamHistoryForOffering failed');
    }
  }

  /// Removes all ranking rows for one exam session.
  Future<void> clearExamRankingsForSession(String examSessionId) async {
    try {
      await _db
          .from('exam_rankings')
          .delete()
          .eq('exam_session_id', examSessionId.trim());
      debugPrint('[ExamService] Cleared rankings for session $examSessionId');
    } catch (e) {
      _rethrowPostgrest(e, 'clearExamRankingsForSession failed');
    }
  }

  /// Removes ranking rows for every exam session in a subject offering.
  Future<void> clearAllExamRankingsForOffering(String subjectOfferingId) async {
    try {
      final sessionsRaw = await _db
          .from('exam_sessions')
          .select('id')
          .eq('subject_offering_id', subjectOfferingId.trim());
      final sessionIds = sessionsRaw
          .map((r) => _jsonStr(
                Map<String, dynamic>.from(r as Map<dynamic, dynamic>)['id'],
              ))
          .where((id) => id.isNotEmpty)
          .toList();
      if (sessionIds.isEmpty) return;
      await _db.from('exam_rankings').delete().inFilter('exam_session_id', sessionIds);
      debugPrint(
        '[ExamService] Cleared all rankings for offering $subjectOfferingId',
      );
    } catch (e) {
      _rethrowPostgrest(e, 'clearAllExamRankingsForOffering failed');
    }
  }
}
