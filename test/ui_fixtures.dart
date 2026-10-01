import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ble_attendance/services/supabase_service.dart';

const longName = 'Alexandria Marie Dela Cruz — a student with a long full name';
const longTitle =
    'Advanced Application Development and Information Systems Integration';
const offering = SubjectOffering(
  id: 'class-1',
  subjectId: 'subject-1',
  sectionId: 'section-1',
  subjectCode: 'IT401',
  subjectTitle: longTitle,
  section: 'BSIT 4A afternoon class',
  teacherId: 'teacher-1',
  teacherName: longName,
  beaconUuid: '12345678-1234-1234-1234-123456789012',
  beaconName: 'Class beacon',
);
const student = AppUser(
  role: 'student',
  linkedId: 'student-1',
  fullName: longName,
  username: 'student1',
);
const teacher = AppUser(
  role: 'teacher',
  linkedId: 'teacher-1',
  fullName: longName,
  username: 'teacher1',
);
final now = DateTime(2026, 6, 2, 10);
final session = ExamSession(
  id: 'exam-1',
  subjectOfferingId: offering.id,
  teacherId: offering.teacherId,
  examTitle: longTitle,
  examCode: 'EXAM123',
  bleUuid: offering.beaconUuid,
  rssiThreshold: -85,
  gracePeriodSeconds: 30,
  status: 'scheduled',
  createdAt: now,
);
final attempt = ExamAttempt(
  id: 'attempt-1',
  examSessionId: session.id,
  studentId: student.linkedId,
  status: 'in_progress',
  startedAt: now,
);
final attendance = TeacherSessionHistoryItem(
  sessionId: 'attendance-1',
  subjectCode: offering.subjectCode,
  subjectTitle: longTitle,
  section: offering.section,
  startedAt: now,
  endedAt: now,
  isActive: false,
);
final examRow = <String, dynamic>{
  'id': session.id,
  'subject_offering_id': offering.id,
  'teacher_id': teacher.linkedId,
  'exam_title': longTitle,
  'exam_code': 'EXAM123',
  'ble_uuid': offering.beaconUuid,
  'rssi_threshold': -85,
  'grace_period_seconds': 30,
  'status': 'active',
  'created_at': now.toIso8601String(),
  'duration_minutes': 60,
};
final attemptRow = <String, dynamic>{
  'id': 'attempt-1',
  'student_id': student.linkedId,
  'exam_session_id': 'exam-1',
  'status': 'in_progress',
  'started_at': now.toIso8601String(),
  'submitted_at': now.add(const Duration(minutes: 12)).toIso8601String(),
  'completion_seconds': 720,
  'percentage_score': 85,
  'violation_count': 0,
  'students': {'full_name': longName},
  'exam_sessions': examRow,
};
bool failHistory = false;

http.Response fakeResponse(http.Request request) {
  final path = request.url.path;
  Object data = <Object>[];
  if (request.method != 'GET' && !path.contains('/rpc/')) {
    return http.Response('', 204, request: request);
  }
  if (path.endsWith('/students')) {
    data = {
      'id': student.linkedId,
      'full_name': longName,
      'student_number': '2026-00001',
    };
  }
  if (path.endsWith('/exam_sessions')) data = [examRow];
  if (path.endsWith('/exam_attempts')) {
    if (failHistory) {
      return http.Response('{"message":"Offline","code":"ERROR"}', 503);
    }
    data = request.url.queryParameters['id'] != null
        ? [attemptRow]
        : [
            for (var i = 0; i < 14; i++)
              {
                ...attemptRow,
                'id': 'attempt-$i',
                'status': 'completed',
                'percentage_score': 75 + i,
                'exam_sessions': {
                  ...examRow,
                  'exam_title': '$longTitle — Exam ${i + 1}',
                },
              },
          ];
  }
  if (path.endsWith('/exam_questions')) {
    data = [
      for (var i = 0; i < 3; i++)
        {
          'id': 'q$i',
          'exam_session_id': 'exam-1',
          'question_text':
              'Explain the most appropriate approach to a complex application integration scenario with several competing requirements.',
          'points': 5,
          'question_order': i + 1,
        },
    ];
  }
  if (path.endsWith('/exam_choices')) {
    data = [
      for (var q = 0; q < 3; q++)
        for (var i = 1; i <= 4; i++)
          {
            'id': 'c$q$i',
            'exam_question_id': 'q$q',
            'choice_text':
                'A detailed answer option that wraps onto several lines on a small phone with large text enabled.',
            'is_correct': i == 1,
            'choice_order': i,
          },
    ];
  }
  if (path.endsWith('/exam_rankings')) {
    data = [
      {
        'student_id': student.linkedId,
        'exam_score': 85,
        'rank_number': 1,
        'students': {'full_name': longName},
        'remarks':
            'Very good performance. Review the questions you missed before your next examination.',
      },
    ];
  }
  if (path.endsWith('/student_subject_enrollments')) {
    data = [
      {
        'subject_offering_id': offering.id,
        'student_id': student.linkedId,
        'students': {
          'id': student.linkedId,
          'full_name': longName,
          'student_number': '2026-00001',
        },
      },
    ];
  }
  if (path.endsWith('/subject_offerings') ||
      path.endsWith('/get_student_dashboard')) {
    data = [
      {
        'id': offering.id,
        'offering_id': offering.id,
        'subject_id': offering.subjectId,
        'section_id': offering.sectionId,
        'subject_code': offering.subjectCode,
        'subject_title': longTitle,
        'section': offering.section,
        'teacher_id': offering.teacherId,
        'teacher_name': longName,
        'beacon_uuid': offering.beaconUuid,
        'beacon_name': offering.beaconName,
        'subjects': {
          'subject_code': offering.subjectCode,
          'subject_title': longTitle,
        },
        'sections': {'section_name': offering.section},
        'teachers': {'full_name': longName},
      },
    ];
  }
  if (path.endsWith('/get_teacher_session_history')) {
    data = [
      {
        'session_id': attendance.sessionId,
        'subject_code': offering.subjectCode,
        'subject_title': longTitle,
        'section': offering.section,
        'started_at': now.toIso8601String(),
        'ended_at': now.toIso8601String(),
        'is_active': false,
      },
    ];
  }
  if (path.endsWith('/get_teacher_session_attendees')) {
    data = [
      {
        'student_id': student.linkedId,
        'student_name': longName,
        'is_present': true,
        'marked_at': now.toIso8601String(),
        'device_used': 'A very long device model name for responsive testing',
      },
    ];
  }
  if (path.endsWith('/get_student_attendance_history')) {
    data = [
      {
        'subject_code': offering.subjectCode,
        'subject_title': longTitle,
        'section': offering.section,
        'teacher_name': longName,
        'session_started_at': now.toIso8601String(),
        'marked_at': now.toIso8601String(),
      },
    ];
  }
  if (data is List &&
      request.headers['accept']?.contains('vnd.pgrst.object') == true) {
    data = data.isEmpty ? <String, dynamic>{} : data.first;
  }
  return http.Response(
    jsonEncode(data),
    200,
    request: request,
    headers: {'content-type': 'application/json'},
  );
}
