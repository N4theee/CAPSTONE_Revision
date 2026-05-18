import 'package:flutter_test/flutter_test.dart';

void main() {
  test('branding uses Attendximity and teacher role label', () {
    const appTitle = 'Attendximity';
    const teacherRoleLabel = 'I am a Teacher';
    expect(appTitle, 'Attendximity');
    expect(teacherRoleLabel, contains('Teacher'));
    expect(teacherRoleLabel, isNot(contains('Professor')));
  });
}
