import 'package:cricket/models/player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Player reads the profile fields the server returns', () {
    final p = Player.fromJson({
      'id': 'u_abc',
      'name': 'Ravi Kumar',
      'role': 'allRounder',
      'battingStyle': 'Left-hand bat',
      'bowlingStyle': 'Right-arm off spin',
      'email': 'ravi@example.com',
      'gender': 'male',
      'dateOfBirth': '1998-04-12',
      'heightCm': 178, // the server may send ints or doubles
      'weightKg': 72.5,
      'jerseyNumber': 18,
      'city': 'Chennai',
      'linkedUserId': 'abc',
      'isSelf': true,
      'isRegistered': true,
    });
    expect(p.heightCm, 178.0);
    expect(p.weightKg, 72.5);
    expect(p.jerseyNumber, 18);
    expect(p.isSelf, isTrue);
    expect(p.isRegistered, isTrue);
    expect(p.dateOfBirth, '1998-04-12');
  });

  test('Player written by an older app version (no profile fields) still loads', () {
    final p = Player.fromJson({
      'id': '1',
      'name': 'Old',
      'role': 'batter',
      'battingStyle': 'Right-hand bat',
      'bowlingStyle': 'None',
    });
    expect(p.email, isNull);
    expect(p.isSelf, isFalse);
    expect(p.isRegistered, isFalse);
  });

  test('Player round-trips through toJson / fromJson', () {
    final a = Player(id: 'x', name: 'A', email: 'a@b.co', heightCm: 180, jerseyNumber: 7, gender: 'female');
    final b = Player.fromJson(a.toJson());
    expect(b.email, 'a@b.co');
    expect(b.heightCm, 180);
    expect(b.jerseyNumber, 7);
    expect(b.gender, 'female');
  });
}
