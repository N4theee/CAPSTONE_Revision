class TeacherProfile {
  const TeacherProfile({
    required this.id,
    required this.name,
    required this.subject,
    required this.beaconUuid,
    required this.beaconName,
    this.maxStudents = 30,
  });

  final String id;
  final String name;
  final String subject;
  final String beaconUuid;
  final String beaconName;
  final int maxStudents;
}

class StudentProfile {
  const StudentProfile({
    required this.id,
    required this.name,
    required this.teacherId,
  });

  final String id;
  final String name;
  final String teacherId;
}

class DemoData {
  static const List<TeacherProfile> teachers = [
    TeacherProfile(
      id: 'teach_nath',
      name: 'Teacher Nath',
      subject: 'MOBILE301',
      beaconUuid: '11111111-1111-1111-1111-111111111111',
      beaconName: 'NATH301',
    ),
    TeacherProfile(
      id: 'teach_cana',
      name: 'Teacher Cana',
      subject: 'NET302',
      beaconUuid: '22222222-2222-2222-2222-222222222222',
      beaconName: 'CANA302',
    ),
    TeacherProfile(
      id: 'teach_rus',
      name: 'Teacher Rus',
      subject: 'IOT303',
      beaconUuid: '33333333-3333-3333-3333-333333333333',
      beaconName: 'RUS303',
    ),
  ];

  static const List<StudentProfile> students = [
    StudentProfile(id: 'nath_001', name: 'Nath Student 01', teacherId: 'teach_nath'),
    StudentProfile(id: 'nath_002', name: 'Nath Student 02', teacherId: 'teach_nath'),
    StudentProfile(id: 'nath_003', name: 'Nath Student 03', teacherId: 'teach_nath'),
    StudentProfile(id: 'nath_004', name: 'Nath Student 04', teacherId: 'teach_nath'),
    StudentProfile(id: 'nath_005', name: 'Nath Student 05', teacherId: 'teach_nath'),
    StudentProfile(id: 'cana_001', name: 'Cana Student 01', teacherId: 'teach_cana'),
    StudentProfile(id: 'cana_002', name: 'Cana Student 02', teacherId: 'teach_cana'),
    StudentProfile(id: 'cana_003', name: 'Cana Student 03', teacherId: 'teach_cana'),
    StudentProfile(id: 'cana_004', name: 'Cana Student 04', teacherId: 'teach_cana'),
    StudentProfile(id: 'cana_005', name: 'Cana Student 05', teacherId: 'teach_cana'),
    StudentProfile(id: 'rus_001', name: 'Rus Student 01', teacherId: 'teach_rus'),
    StudentProfile(id: 'rus_002', name: 'Rus Student 02', teacherId: 'teach_rus'),
    StudentProfile(id: 'rus_003', name: 'Rus Student 03', teacherId: 'teach_rus'),
    StudentProfile(id: 'rus_004', name: 'Rus Student 04', teacherId: 'teach_rus'),
    StudentProfile(id: 'rus_005', name: 'Rus Student 05', teacherId: 'teach_rus'),
  ];

  static TeacherProfile teacherById(String teacherId) {
    return teachers.firstWhere((p) => p.id == teacherId);
  }
}
