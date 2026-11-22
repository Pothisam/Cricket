import 'package:cricket/data/api/api_models.dart';
import 'package:cricket/models/cricket_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> invitationJson({String direction = 'outgoing', String status = 'accepted'}) => {
        'id': 'inv1',
        'direction': direction,
        'status': status,
        'fromUserId': 'a',
        'fromUserName': 'Anna',
        'fromTeam': {'id': 't1', 'name': 'Chennai Kings', 'short': 'CSK'},
        'toUserId': 'b',
        'toUserName': 'Bala',
        'toTeam': {'id': 't2', 'name': 'Mumbai Stars', 'short': 'MI'},
        'overs': 10,
        'scheduledAt': '2026-12-01T10:00:00.000Z',
        'venue': 'Chepauk',
        'createdAt': '2026-11-22T10:00:00.000Z',
      };

  test('MatchInvitation reads what the server sends', () {
    final i = MatchInvitation.fromJson(invitationJson());
    expect(i.outgoing, isTrue);
    expect(i.isAccepted, isTrue);
    expect(i.title, 'CSK vs MI');
    expect(i.otherTeamName, 'Mumbai Stars');
    expect(i.otherOwnerName, 'Bala');
    expect(i.overs, 10);
    expect(i.scheduledAt, isNotNull);

    final incoming = MatchInvitation.fromJson(invitationJson(direction: 'incoming', status: 'pending'));
    expect(incoming.outgoing, isFalse);
    expect(incoming.isPending, isTrue);
    expect(incoming.otherTeamName, 'Chennai Kings');
  });

  test('a match started from an invitation keeps the link through JSON', () {
    final m = CricketMatch(
      id: 'm1',
      teamAId: 't1',
      teamBId: 't2',
      teamAName: 'Chennai Kings',
      teamBName: 'Mumbai Stars',
      teamAShort: 'CSK',
      teamBShort: 'MI',
      overs: 10,
      tossWinnerId: 't1',
      electedToBat: true,
      teamAPlayers: ['p1', 'p2'],
      teamBPlayers: ['q1', 'q2'],
      playerNames: {'p1': 'A', 'p2': 'B', 'q1': 'C', 'q2': 'D'},
      date: DateTime(2026, 12, 1),
      invitationId: 'inv1',
      opponentUserId: 'b',
    );
    final back = CricketMatch.fromJson(m.toJson());
    expect(back.invitationId, 'inv1');
    expect(back.opponentUserId, 'b');
  });

  test('a normal match has no invitation', () {
    final m = CricketMatch.fromJson({
      'id': 'm2', 'teamAId': 'a', 'teamBId': 'b', 'teamAName': 'A', 'teamBName': 'B',
      'teamAShort': 'A', 'teamBShort': 'B', 'overs': 5, 'tossWinnerId': 'a', 'electedToBat': true,
      'teamAPlayers': <String>[], 'teamBPlayers': <String>[], 'playerNames': <String, String>{},
      'date': '2026-11-22T10:00:00.000', 'innings': <dynamic>[], 'status': 'live',
    });
    expect(m.invitationId, isNull);
    expect(m.opponentUserId, isNull);
  });
}
