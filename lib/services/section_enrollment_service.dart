import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_data_service.dart';

const schoolPrograms = ['ICT', 'GAS', 'EIM', 'HE', 'HUMSS'];

/// Section placement is an additional layer; existing offering IDs remain the
/// source of attendance/exam eligibility and beacon configuration.
class SectionEnrollmentService {
  final _db = Supabase.instance.client;

  Future<List<AdminRow>> existingEnrollments(List<String> studentIds) async {
    final result = <AdminRow>[];
    for (var page = 0; ; page++) {
      final rows = _rows(
        await _db
            .from('student_subject_enrollments')
            .select(
              'id,students(full_name),subject_offerings(school_year,is_active,subjects(subject_code),sections(section_name),teachers(full_name))',
            )
            .inFilter('student_id', studentIds)
            .order('id')
            .range(page * 100, page * 100 + 99),
      );
      result.addAll(rows);
      if (rows.length < 100) return result;
    }
  }

  Future<List<AdminRow>> curricula({
    int page = 0,
    int? grade,
    String? program,
    bool? approved,
  }) async {
    var q = _db.from('school_curricula').select();
    if (grade != null) q = q.eq('grade', grade);
    if (program != null) q = q.eq('program', program);
    if (approved != null) q = q.eq('approved', approved);
    return _rows(
      await q
          .order('grade')
          .order('program')
          .order('id')
          .range(page * 25, page * 25 + 24),
    );
  }

  Future<List<AdminRow>> curriculumSubjects(String id) async => _rows(
    await _db
        .from('school_curriculum_subjects')
        .select('subject_id, semester, subjects(subject_code,subject_title)')
        .eq('curriculum_id', id)
        .order('subject_id'),
  );

  Future<List<AdminRow>> sections({
    int page = 0,
    String search = '',
    String? year,
    int? grade,
    String? program,
  }) async {
    var q = _db
        .from('school_sections')
        .select(
          '*, sections!inner(section_name), teachers(full_name), school_section_placements(count)',
        );
    if (search.trim().isNotEmpty) {
      final literal = search
          .trim()
          .replaceAll('\\', '\\\\')
          .replaceAll('%', '\\%')
          .replaceAll('_', '\\_');
      q = q.ilike('sections.section_name', '%$literal%');
    }
    if (year != null) q = q.eq('school_year', year);
    if (grade != null) q = q.eq('grade', grade);
    if (program != null) q = q.eq('program', program);
    return _rows(
      await q
          .order('school_year', ascending: false)
          .order('id')
          .range(page * 25, page * 25 + 24),
    );
  }

  Future<List<AdminRow>> terms(String sectionId) async => _rows(
    await _db
        .from('school_section_terms')
        .select('*, school_curricula(version)')
        .eq('school_section_id', sectionId)
        .order('semester'),
  );

  Future<List<AdminRow>> assignments(String termId) async => _rows(
    await _db
        .from('school_teaching_assignments')
        .select(
          'subject_id, offering_id, subject_offerings(teacher_id, teachers(full_name), subjects(subject_title))',
        )
        .eq('term_id', termId)
        .order('subject_id'),
  );

  Future<List<AdminRow>> roster(String sectionId, {int page = 0}) async =>
      _rows(
        await _db
            .from('school_section_placements')
            .select(
              'student_id, students(full_name, student_number), created_at',
            )
            .eq('school_section_id', sectionId)
            .order('created_at')
            .order('id')
            .range(page * 25, page * 25 + 24),
      );

  Future<List<AdminRow>> requests({int page = 0}) async => _rows(
    await _db
        .from('school_student_requests')
        .select(
          '*, students(full_name,student_number,school_section_placements(school_year,school_sections(sections(section_name))))',
        )
        .order('created_at', ascending: false)
        .order('student_id')
        .range(page * 25, page * 25 + 24),
  );

  Future<AdminRow> studentPlacement(String studentId) async {
    try {
      final values = await Future.wait([
        _db
            .from('school_student_requests')
            .select('requested_grade,requested_program')
            .eq('student_id', studentId)
            .limit(1),
        _db
            .from('school_section_placements')
            .select(
              'school_year, school_sections(grade,program,sections(section_name))',
            )
            .eq('student_id', studentId)
            .order('school_year', ascending: false)
            .limit(1),
      ]);
      return {
        'request': values[0].isEmpty ? null : values[0].first,
        'placement': values[1].isEmpty ? null : values[1].first,
        'available': true,
      };
    } on PostgrestException catch (e) {
      // Existing installations remain usable until the additive migration is applied.
      if (e.code == 'PGRST205' || e.code == '42P01') {
        return {'available': false};
      }
      rethrow;
    }
  }

  Future<AdminRow> command(
    String action,
    AdminRow data, {
    required String username,
    required String password,
  }) async => AdminRow.from(
    await _db.rpc(
          'admin_school_command',
          params: {
            'p_username': username,
            'p_password': password,
            'p_action': action,
            'p_data': data,
          },
        )
        as Map,
  );

  static int occupied(AdminRow section) {
    final counts = section['school_section_placements'] as List?;
    return counts == null || counts.isEmpty
        ? 0
        : (counts.first['count'] as num).toInt();
  }

  List<AdminRow> _rows(List<dynamic> rows) =>
      rows.map((row) => AdminRow.from(row as Map)).toList();
}
