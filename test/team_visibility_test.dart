import 'package:cricket/models/team.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a new team is private by default', () {
    expect(Team(id: '1', name: 'A', shortName: 'A').isPublic, isFalse);
  });

  test('team visibility round-trips through JSON', () {
    final t = Team(id: '1', name: 'Kings', shortName: 'KIN', isPublic: true);
    expect(Team.fromJson(t.toJson()).isPublic, isTrue);
  });

  test('teams saved before the setting existed load as private', () {
    final t = Team.fromJson({'id': '1', 'name': 'Old', 'shortName': 'OLD'});
    expect(t.isPublic, isFalse);
  });
}
