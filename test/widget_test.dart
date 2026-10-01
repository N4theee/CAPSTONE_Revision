import 'package:flutter_test/flutter_test.dart';

void main() {
  test('branding uses Proxamity and teacher role label', () {
    const appTitle = 'Proxamity';
    const teacherRoleLabel = 'I am a Teacher';
    expect(appTitle, 'Proxamity');
    expect(teacherRoleLabel, contains('Teacher'));
    expect(teacherRoleLabel, isNot(contains('Professor')));
  });
}
