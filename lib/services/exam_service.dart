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
    this.durationMinutes = 60,
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
  final int durationMinutes;

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
    this.rawScore = 0,
    this.totalPoints = 0,
    this.percentageScore = 0,
    this.completionSeconds = 0,
    this.submittedAt,
  });

  final String id;
  final String examSessionId;
  final String studentId;
  final String status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int violationCount;
  final int rawScore;
  final int totalPoints;
  final double percentageScore;
  final int completionSeconds;
  final DateTime? submittedAt;

  bool get isTerminal =>
      status == 'completed' || status == 'auto_ended' || status == 'flagged';

  bool get canSubmitMcq =>
      status == 'in_progress';
}

class ExamChoice {
  const ExamChoice({
    required this.id,
    required this.examQuestionId,
    required this.choiceText,
    required this.isCorrect,
    required this.choiceOrder,
  });

  final String id;
  final String examQuestionId;
  final String choiceText;
  final bool isCorrect;
  final int choiceOrder;
}

class ExamQuestion {
  const ExamQuestion({
    required this.id,
    required this.examSessionId,
    required this.questionText,
    required this.points,
    required this.questionOrder,
    required this.choices,
  });

  final String id;
  final String examSessionId;
  final String questionText;
  final int points;
  final int questionOrder;
  final List<ExamChoice> choices;
}

/// Draft for teacher create-exam UI (choices include correct flag).
class ExamQuestionDraft {
  ExamQuestionDraft({
    this.questionText = '',
    this.points = 1,
    List<ExamChoiceDraft>? choices,
    this.correctChoiceIndex = 0,
  }) : choices = choices ?? ExamChoiceDraft.fourEmpty();

  String questionText;
  int points;
  int correctChoiceIndex;
  final List<ExamChoiceDraft> choices;
}

class ExamChoiceDraft {
  ExamChoiceDraft({this.text = ''});

  String text;

  static List<ExamChoiceDraft> fourEmpty() =>
      List.generate(4, (_) => ExamChoiceDraft());
}

class ExamSubmitResult {
  const ExamSubmitResult({
    required this.rawScore,
    required this.totalPoints,
    required this.percentageScore,
    required this.completionSeconds,
    required this.submittedAt,
  });

  final int rawScore;
  final int totalPoints;
  final double percentageScore;
  final int completionSeconds;
  final DateTime submittedAt;
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
    this.completionSeconds,
    this.violationCount = 0,
  });

  final String studentId;
  final String studentName;
  final double examScore;
  final double speedPoints;
  final double violationPenalty;
  final double overallScore;
  final int? rankNumber;
  final String? remarks;
  final int? completionSeconds;
  final int violationCount;
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
    this.submittedAt,
    required this.violationCount,
    this.percentageScore,
    this.completionSeconds,
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
  final DateTime? submittedAt;
  final int violationCount;
  final double? percentageScore;
  final int? completionSeconds;

  /// Best instant for "finished at" display (submitted → ended → null).
  DateTime? get finishedAt => submittedAt ?? endedAt;
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
      durationMinutes: (m['duration_minutes'] as num?)?.toInt() ?? 60,
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
      rawScore: (m['raw_score'] as num?)?.toInt() ?? 0,
      totalPoints: (m['total_points'] as num?)?.toInt() ?? 0,
      percentageScore: (m['percentage_score'] as num?)?.toDouble() ??
          (m['exam_score'] as num?)?.toDouble() ??
          0,
      completionSeconds: (m['completion_seconds'] as num?)?.toInt() ?? 0,
      submittedAt: tryParseDbTimestamptzToLocal(m['submitted_at']),
    );
  }

  ExamChoice _examChoiceFromMap(Map<String, dynamic> m) {
    return ExamChoice(
      id: _jsonStr(m['id']),
      examQuestionId: _jsonStr(m['exam_question_id']),
      choiceText: _jsonStr(m['choice_text']),
      isCorrect: m['is_correct'] as bool? ?? false,
      choiceOrder: (m['choice_order'] as num?)?.toInt() ?? 1,
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
    int durationMinutes = 60,
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
        'duration_minutes': durationMinutes,
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

  /// RSSI threshold for continuous exam proximity monitoring (from session row).
  static int effectiveProximityRssi(int sessionRssi) => sessionRssi;

  /// Forgiving fixed threshold when joining an exam (weaker signal allowed).
  static int examJoinProximityRssi(int sessionRssi) =>
      AppConfig.examJoinRssiThreshold;

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
        'rssi': ?rssi,
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

  // ── MCQ questions / choices / answers ─────────────────────────────────────

  /// Validates [drafts] for teacher create-exam flow.
  static void validateQuestionDrafts(List<ExamQuestionDraft> drafts) {
    if (drafts.isEmpty) {
      throw ExamServiceException('Add at least one question.');
    }
    for (var i = 0; i < drafts.length; i++) {
      final q = drafts[i];
      final n = i + 1;
      if (q.questionText.trim().isEmpty) {
        throw ExamServiceException('Question $n needs question text.');
      }
      if (q.points < 1) {
        throw ExamServiceException('Question $n must have at least 1 point.');
      }
      for (var j = 0; j < q.choices.length; j++) {
        if (q.choices[j].text.trim().isEmpty) {
          throw ExamServiceException(
            'Question $n: fill all four choices (A–D).',
          );
        }
      }
      if (q.correctChoiceIndex < 0 || q.correctChoiceIndex > 3) {
        throw ExamServiceException('Question $n: select the correct answer.');
      }
    }
  }

  Future<ExamSession> createExamWithQuestions({
    required String subjectOfferingId,
    required String teacherId,
    required String examTitle,
    required String bleUuid,
    required String status,
    required List<ExamQuestionDraft> questions,
    int rssiThreshold = -85,
    int gracePeriodSeconds = 30,
    int durationMinutes = 60,
    DateTime? startsAt,
    DateTime? endsAt,
    String? examCode,
  }) async {
    validateQuestionDrafts(questions);
    final session = await createExamSession(
      subjectOfferingId: subjectOfferingId,
      teacherId: teacherId,
      examTitle: examTitle,
      bleUuid: bleUuid,
      status: status,
      rssiThreshold: rssiThreshold,
      gracePeriodSeconds: gracePeriodSeconds,
      durationMinutes: durationMinutes,
      startsAt: startsAt,
      endsAt: endsAt,
      examCode: examCode,
    );
    for (var i = 0; i < questions.length; i++) {
      final draft = questions[i];
      final questionId = await addExamQuestion(
        examSessionId: session.id,
        questionText: draft.questionText.trim(),
        points: draft.points,
        questionOrder: i + 1,
      );
      await addExamChoices(
        examQuestionId: questionId,
        choices: draft.choices,
        correctChoiceIndex: draft.correctChoiceIndex,
      );
    }
    return session;
  }

  Future<String> addExamQuestion({
    required String examSessionId,
    required String questionText,
    required int points,
    required int questionOrder,
  }) async {
    try {
      final row = await _db
          .from('exam_questions')
          .insert({
            'exam_session_id': examSessionId,
            'question_text': questionText,
            'points': points,
            'question_order': questionOrder,
          })
          .select('id')
          .single();
      return _jsonStr(row['id']);
    } catch (e) {
      if (e is ExamServiceException) rethrow;
      _rethrowPostgrest(e, 'addExamQuestion failed');
    }
  }

  Future<void> addExamChoices({
    required String examQuestionId,
    required List<ExamChoiceDraft> choices,
    required int correctChoiceIndex,
  }) async {
    try {
      final payload = <Map<String, dynamic>>[];
      for (var i = 0; i < choices.length; i++) {
        payload.add({
          'exam_question_id': examQuestionId,
          'choice_text': choices[i].text.trim(),
          'is_correct': i == correctChoiceIndex,
          'choice_order': i + 1,
        });
      }
      await _db.from('exam_choices').insert(payload);
    } catch (e) {
      _rethrowPostgrest(e, 'addExamChoices failed');
    }
  }

  Future<List<ExamQuestion>> getExamQuestionsWithChoices(
    String examSessionId, {
    bool includeCorrectFlags = false,
  }) async {
    try {
      final qRows = await _db
          .from('exam_questions')
          .select()
          .eq('exam_session_id', examSessionId)
          .order('question_order', ascending: true);
      if (qRows.isEmpty) return [];

      final questionIds = qRows
          .map((r) => _jsonStr(
                Map<String, dynamic>.from(r as Map<dynamic, dynamic>)['id'],
              ))
          .where((id) => id.isNotEmpty)
          .toList();

      final cRows = await _db
          .from('exam_choices')
          .select()
          .inFilter('exam_question_id', questionIds)
          .order('choice_order', ascending: true);

      final choicesByQuestion = <String, List<ExamChoice>>{};
      for (final row in cRows) {
        final m = Map<String, dynamic>.from(row as Map<dynamic, dynamic>);
        final choice = _examChoiceFromMap(m);
        if (!includeCorrectFlags && choice.isCorrect) {
          // Student view: strip correct flag (still need choices for UI)
        }
        final list = choicesByQuestion.putIfAbsent(
          choice.examQuestionId,
          () => <ExamChoice>[],
        );
        list.add(
          ExamChoice(
            id: choice.id,
            examQuestionId: choice.examQuestionId,
            choiceText: choice.choiceText,
            isCorrect: includeCorrectFlags ? choice.isCorrect : false,
            choiceOrder: choice.choiceOrder,
          ),
        );
      }

      final questions = <ExamQuestion>[];
      for (final row in qRows) {
        final m = Map<String, dynamic>.from(row as Map<dynamic, dynamic>);
        final id = _jsonStr(m['id']);
        questions.add(
          ExamQuestion(
            id: id,
            examSessionId: _jsonStr(m['exam_session_id']),
            questionText: _jsonStr(m['question_text']),
            points: (m['points'] as num?)?.toInt() ?? 1,
            questionOrder: (m['question_order'] as num?)?.toInt() ?? 1,
            choices: choicesByQuestion[id] ?? const [],
          ),
        );
      }
      return questions;
    } catch (e) {
      _rethrowPostgrest(e, 'getExamQuestionsWithChoices failed');
    }
  }

  Future<int> countExamQuestions(String examSessionId) async {
    try {
      final rows = await _db
          .from('exam_questions')
          .select('id')
          .eq('exam_session_id', examSessionId);
      return rows.length;
    } catch (e) {
      _rethrowPostgrest(e, 'countExamQuestions failed');
    }
  }

  /// Performance recommendation from percentage score and violations.
  static String buildPerformanceRemarks({
    required double percentageScore,
    required int violationCount,
  }) {
    final parts = <String>[];
    if (percentageScore >= 90) {
      parts.add('Excellent performance');
    } else if (percentageScore >= 80) {
      parts.add('Very good performance');
    } else if (percentageScore >= 75) {
      parts.add('Passed but needs improvement');
    } else {
      parts.add('Needs remediation');
    }
    if (violationCount > 0) {
      parts.add('Review proximity violations');
    }
    return parts.join('. ');
  }

  /// Submits MCQ answers, scores attempt, and refreshes session rankings.
  Future<ExamSubmitResult> submitExamAttempt({
    required String attemptId,
    required Map<String, String> answersByQuestionId,
  }) async {
    try {
      final attemptRow = await _db
          .from('exam_attempts')
          .select()
          .eq('id', attemptId)
          .maybeSingle();
      if (attemptRow == null) {
        throw ExamServiceException('Exam attempt not found.');
      }
      final attempt = _examAttemptFromMap(
        Map<String, dynamic>.from(attemptRow),
      );
      if (!attempt.canSubmitMcq) {
        throw ExamServiceException(
          'This exam was already submitted (${attempt.status}).',
        );
      }

      final questions = await getExamQuestionsWithChoices(
        attempt.examSessionId,
        includeCorrectFlags: true,
      );
      if (questions.isEmpty) {
        throw ExamServiceException(
          'This exam has no questions yet. Ask your teacher to add questions.',
        );
      }

      var rawScore = 0;
      var totalPoints = 0;
      final answerRows = <Map<String, dynamic>>[];

      for (final q in questions) {
        totalPoints += q.points;
        final selectedId = answersByQuestionId[q.id]?.trim() ?? '';
        ExamChoice? selected;
        ExamChoice? correct;
        for (final c in q.choices) {
          if (c.isCorrect) correct = c;
          if (c.id == selectedId) selected = c;
        }
        final isCorrect =
            selected != null && correct != null && selected.id == correct.id;
        final pointsAwarded = isCorrect ? q.points : 0;
        rawScore += pointsAwarded;

        answerRows.add({
          'exam_attempt_id': attemptId,
          'exam_question_id': q.id,
          'selected_choice_id': selectedId.isEmpty ? null : selectedId,
          'is_correct': isCorrect,
          'points_awarded': pointsAwarded,
          'answered_at': utcIsoNowForDb(),
        });
      }

      final percentageScore =
          totalPoints > 0 ? (rawScore / totalPoints) * 100.0 : 0.0;
      final submittedAtUtc = DateTime.now().toUtc();
      final submittedIso = submittedAtUtc.toIso8601String();
      final completionSeconds = completionSecondsBetween(
        startedAt: attempt.startedAt,
        submittedAt: submittedAtUtc,
      );

      await _db.from('exam_answers').upsert(
        answerRows,
        onConflict: 'exam_attempt_id,exam_question_id',
      );

      await _db.from('exam_attempts').update({
        'status': 'completed',
        'raw_score': rawScore,
        'total_points': totalPoints,
        'percentage_score': percentageScore,
        'exam_score': percentageScore,
        'completion_seconds': completionSeconds,
        'submitted_at': submittedIso,
        'ended_at': submittedIso,
      }).eq('id', attemptId);

      await recomputeExamRankingsForSession(attempt.examSessionId);

      debugPrint(
        '[ExamService] Submitted $attemptId: $rawScore/$totalPoints '
        '(${percentageScore.toStringAsFixed(1)}%)',
      );

      return ExamSubmitResult(
        rawScore: rawScore,
        totalPoints: totalPoints,
        percentageScore: percentageScore,
        completionSeconds: completionSeconds,
        submittedAt: submittedAtUtc.toLocal(),
      );
    } catch (e) {
      if (e is ExamServiceException) rethrow;
      _rethrowPostgrest(e, 'submitExamAttempt failed');
    }
  }

  /// Ranks completed attempts and upserts [exam_rankings] for the session.
  Future<void> recomputeExamRankingsForSession(String examSessionId) async {
    try {
      final attemptsRaw = await _db
          .from('exam_attempts')
          .select(
            'id, student_id, status, percentage_score, exam_score, '
            'completion_seconds, violation_count, students(full_name)',
          )
          .eq('exam_session_id', examSessionId)
          .eq('status', 'completed');

      final ranked = <({
        String studentId,
        String studentName,
        double percentageScore,
        int completionSeconds,
        int violationCount,
      })>[];

      for (final row in attemptsRaw) {
        final m = Map<String, dynamic>.from(row as Map<dynamic, dynamic>);
        final pct = (m['percentage_score'] as num?)?.toDouble() ??
            (m['exam_score'] as num?)?.toDouble() ??
            0;
        final students = m['students'];
        var name = 'Student';
        if (students is Map) {
          final n = _jsonStr(students['full_name']);
          if (n.isNotEmpty) name = n;
        }
        ranked.add((
          studentId: _jsonStr(m['student_id']),
          studentName: name,
          percentageScore: pct,
          completionSeconds: (m['completion_seconds'] as num?)?.toInt() ?? 0,
          violationCount: (m['violation_count'] as num?)?.toInt() ?? 0,
        ));
      }

      ranked.sort((a, b) {
        final byScore = b.percentageScore.compareTo(a.percentageScore);
        if (byScore != 0) return byScore;
        final bySpeed = a.completionSeconds.compareTo(b.completionSeconds);
        if (bySpeed != 0) return bySpeed;
        return a.violationCount.compareTo(b.violationCount);
      });

      for (var i = 0; i < ranked.length; i++) {
        final r = ranked[i];
        final rankNum = i + 1;
        final remarks = buildPerformanceRemarks(
          percentageScore: r.percentageScore,
          violationCount: r.violationCount,
        );
        final speedPoints = r.completionSeconds > 0
            ? (10000 / r.completionSeconds).clamp(0.0, 9999.0)
            : 0.0;
        await _db.from('exam_rankings').upsert(
          {
            'exam_session_id': examSessionId,
            'student_id': r.studentId,
            'exam_score': r.percentageScore,
            'speed_points': speedPoints,
            'violation_penalty': r.violationCount.toDouble(),
            'overall_score': r.percentageScore,
            'rank_number': rankNum,
            'remarks': remarks,
          },
          onConflict: 'exam_session_id,student_id',
        );
      }
      debugPrint(
        '[ExamService] Recomputed ${ranked.length} rankings for $examSessionId',
      );
    } catch (e) {
      _rethrowPostgrest(e, 'recomputeExamRankingsForSession failed');
    }
  }

  static String formatCompletionTime(int? seconds) {
    if (seconds == null || seconds <= 0) return '—';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  /// Picks the best completion instant from an attempt row or model.
  static DateTime? resolveAttemptSubmittedAt({
    DateTime? submittedAt,
    DateTime? endedAt,
    dynamic updatedAt,
  }) {
    if (submittedAt != null && submittedAt.year >= 2000) {
      return submittedAt.toLocal();
    }
    if (endedAt != null && endedAt.year >= 2000) {
      return endedAt.toLocal();
    }
    final parsed = tryParseDbTimestamptzToLocal(updatedAt);
    if (parsed != null && parsed.year >= 2000) return parsed;
    return null;
  }

  static int completionSecondsBetween({
    required DateTime startedAt,
    required DateTime submittedAt,
  }) {
    final seconds = submittedAt
        .toUtc()
        .difference(startedAt.toUtc())
        .inSeconds;
    if (seconds < 0) return 0;
    return seconds.clamp(0, 86400);
  }

  StudentExamHistoryItem _studentHistoryFromAttemptRow(
    Map<String, dynamic> m,
    Map<String, dynamic> sm, {
    required String subjectCode,
    required String subjectTitle,
    required String section,
  }) {
    final submittedAt = tryParseDbTimestamptzToLocal(m['submitted_at']);
    final endedAt = tryParseDbTimestamptzToLocal(m['ended_at']);
    var completionSeconds = (m['completion_seconds'] as num?)?.toInt();
    if ((completionSeconds == null || completionSeconds <= 0) &&
        submittedAt != null) {
      final started =
          tryParseDbTimestamptzToLocal(m['started_at']) ?? DateTime.now();
      completionSeconds = completionSecondsBetween(
        startedAt: started,
        submittedAt: submittedAt,
      );
    }

    return StudentExamHistoryItem(
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
      endedAt: endedAt,
      submittedAt: submittedAt,
      violationCount: (m['violation_count'] as num?)?.toInt() ?? 0,
      percentageScore: (m['percentage_score'] as num?)?.toDouble() ??
          (m['exam_score'] as num?)?.toDouble(),
      completionSeconds: completionSeconds,
    );
  }

  // ── 9) Rankings ────────────────────────────────────────────────────────────

  Future<List<ExamRankingRow>> getExamRankings(String examSessionId) async {
    try {
      await recomputeExamRankingsForSession(examSessionId);

      final rows = await _db
          .from('exam_rankings')
          .select(
            'student_id, exam_score, speed_points, violation_penalty, overall_score, rank_number, remarks, students(full_name)',
          )
          .eq('exam_session_id', examSessionId);

      final attemptByStudent = <String, Map<String, dynamic>>{};
      try {
        final attemptsRaw = await _db
            .from('exam_attempts')
            .select('student_id, completion_seconds, violation_count')
            .eq('exam_session_id', examSessionId)
            .eq('status', 'completed');
        for (final row in attemptsRaw) {
          final m = Map<String, dynamic>.from(row as Map<dynamic, dynamic>);
          attemptByStudent[_jsonStr(m['student_id'])] = m;
        }
      } catch (_) {}

      final list = rows.map((row) {
        final m = Map<String, dynamic>.from(row as Map<dynamic, dynamic>);
        final students = m['students'];
        var name = 'Student';
        if (students is Map) {
          final n = _jsonStr(students['full_name']);
          if (n.isNotEmpty) name = n;
        }
        final sid = _jsonStr(m['student_id']);
        final att = attemptByStudent[sid];
        final completionSeconds =
            (att?['completion_seconds'] as num?)?.toInt();
        final violationCount =
            (att?['violation_count'] as num?)?.toInt() ??
            (m['violation_penalty'] as num?)?.toInt() ??
            0;
        return ExamRankingRow(
          studentId: sid,
          studentName: name,
          examScore: (m['exam_score'] as num?)?.toDouble() ?? 0,
          speedPoints: (m['speed_points'] as num?)?.toDouble() ?? 0,
          violationPenalty: (m['violation_penalty'] as num?)?.toDouble() ?? 0,
          overallScore: (m['overall_score'] as num?)?.toDouble() ?? 0,
          rankNumber: (m['rank_number'] as num?)?.toInt(),
          remarks: (m['remarks'] as String?)?.trim(),
          completionSeconds: completionSeconds,
          violationCount: violationCount,
        );
      }).toList();

      list.sort((a, b) {
        final ar = a.rankNumber;
        final br = b.rankNumber;
        if (ar != null && br != null) return ar.compareTo(br);
        if (ar != null) return -1;
        if (br != null) return 1;
        final byScore = b.examScore.compareTo(a.examScore);
        if (byScore != 0) return byScore;
        final aSec = a.completionSeconds ?? 999999;
        final bSec = b.completionSeconds ?? 999999;
        final bySpeed = aSec.compareTo(bSec);
        if (bySpeed != 0) return bySpeed;
        return a.violationCount.compareTo(b.violationCount);
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
                'id, exam_session_id, status, started_at, ended_at, submitted_at, '
                'violation_count, percentage_score, exam_score, completion_seconds, '
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
          _studentHistoryFromAttemptRow(
            m,
            sm,
            subjectCode: subjectCode,
            subjectTitle: subjectTitle,
            section: section,
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
        _studentHistoryFromAttemptRow(
          m,
          {
            'exam_title': sess.examTitle,
            'exam_code': sess.examCode,
            'subject_offering_id': sess.subjectOfferingId,
          },
          subjectCode: subjectCode,
          subjectTitle: subjectTitle,
          section: section,
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

  /// Deletes one exam session and all related rows (safe if some tables are missing).
  Future<void> deleteExamSessionCompletely(String examSessionId) async {
    final sid = examSessionId.trim();
    if (sid.isEmpty) {
      throw ExamServiceException('Invalid exam session id.');
    }

    try {
      final attemptsRaw = await _db
          .from('exam_attempts')
          .select('id')
          .eq('exam_session_id', sid);
      final attemptIds = attemptsRaw
          .map((r) => _jsonStr(
                Map<String, dynamic>.from(r as Map<dynamic, dynamic>)['id'],
              ))
          .where((id) => id.isNotEmpty)
          .toList();

      if (attemptIds.isNotEmpty) {
        await _safeDeleteTable(
          () => _db
              .from('exam_answers')
              .delete()
              .inFilter('exam_attempt_id', attemptIds),
          'exam_answers',
        );
      }

      final questionsRaw = await _db
          .from('exam_questions')
          .select('id')
          .eq('exam_session_id', sid);
      final questionIds = questionsRaw
          .map((r) => _jsonStr(
                Map<String, dynamic>.from(r as Map<dynamic, dynamic>)['id'],
              ))
          .where((id) => id.isNotEmpty)
          .toList();

      if (questionIds.isNotEmpty) {
        await _safeDeleteTable(
          () => _db
              .from('exam_choices')
              .delete()
              .inFilter('exam_question_id', questionIds),
          'exam_choices',
        );
      }

      await _safeDeleteTable(
        () => _db.from('exam_questions').delete().eq('exam_session_id', sid),
        'exam_questions',
      );
      await _safeDeleteTable(
        () => _db.from('exam_rankings').delete().eq('exam_session_id', sid),
        'exam_rankings',
      );
      await _safeDeleteTable(
        () =>
            _db.from('exam_proximity_logs').delete().eq('exam_session_id', sid),
        'exam_proximity_logs',
      );
      await _safeDeleteTable(
        () => _db.from('exam_alerts').delete().eq('exam_session_id', sid),
        'exam_alerts',
      );
      await _safeDeleteTable(
        () => _db.from('exam_attempts').delete().eq('exam_session_id', sid),
        'exam_attempts',
      );

      await _db.from('exam_sessions').delete().eq('id', sid);
      debugPrint('[ExamService] Deleted exam session $sid and related data');
    } catch (e) {
      if (e is ExamServiceException) rethrow;
      _rethrowPostgrest(e, 'deleteExamSessionCompletely failed');
    }
  }

  Future<void> _safeDeleteTable(
    Future<dynamic> Function() deleteOp,
    String tableName,
  ) async {
    try {
      await deleteOp();
    } on PostgrestException catch (e) {
      if (e.code == '42P01' ||
          e.message.toLowerCase().contains('does not exist')) {
        debugPrint('[ExamService] skip delete on missing table $tableName');
        return;
      }
      rethrow;
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
