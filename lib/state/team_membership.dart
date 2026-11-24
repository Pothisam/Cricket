import '../models/player.dart';
import 'membership_controller.dart';
import 'teams_controller.dart';

/// In how many teams is a player, and which ones.
///
/// * my teams that include the player
/// * for the account owner (me) also the teams of other scorers that added me or handed
///   their team over to me
class TeamMembership {
  TeamMembership({required this.mine, required this.others});

  /// Names of my teams that include the player.
  final List<String> mine;

  /// Names of other scorers' teams the player is in (only known for the account owner).
  final List<String> others;

  int get total => mine.length + others.length;
  List<String> get names => [...mine, ...others];

  /// "Not in any team", "In 1 team", "In 3 teams".
  String get countLabel => switch (total) {
    0 => 'Not in any team',
    1 => 'In 1 team',
    _ => 'In $total teams',
  };

  /// "In 3 teams: Blue Wing A, Kings, Stars" (long lists are shortened).
  String get line {
    if (total == 0) return countLabel;
    const show = 3;
    final shown = names.take(show).join(', ');
    final more = total > show ? ' +${total - show}' : '';
    return '$countLabel: $shown$more';
  }

  /// "3 yours · 2 added by others" (for the account owner).
  String get breakdown {
    if (others.isEmpty) return '';
    return '${mine.length} yours · ${others.length} added by others';
  }

  factory TeamMembership.of(
    Player p,
    TeamsController tc,
    MembershipController ms,
  ) {
    final mine = [for (final t in tc.teamsOfPlayer(p.id)) t.name];
    final others = <String>[];
    if (p.isSelf) {
      // A team can be both "added me" and "handed over to me": count it once.
      final seen = <String>{};
      for (final t in ms.teams) {
        if (seen.add('${t.ownerId}|${t.teamId}')) others.add(t.name);
      }
      for (final t in ms.managedTeams) {
        if (seen.add('${t.ownerId}|${t.teamId}')) others.add(t.name);
      }
    }
    return TeamMembership(mine: mine, others: others);
  }
}

/// All teams I am involved in, for the summary on the Teams tab.
class MyTeamsSummary {
  MyTeamsSummary(TeamsController tc, MembershipController ms)
    : created = tc.teams.length,
      admin = ms.managedTeams.length,
      addedBy = {for (final t in ms.teams) '${t.ownerId}|${t.teamId}'}
          .difference({
            for (final t in ms.managedTeams) '${t.ownerId}|${t.teamId}',
          })
          .length;

  /// Teams I created.
  final int created;

  /// Teams handed over to me (I am an admin).
  final int admin;

  /// Teams where I only play (somebody added me), not counting the ones I also administer.
  final int addedBy;

  int get total => created + admin + addedBy;
}
