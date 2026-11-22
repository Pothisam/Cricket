
import 'package:cricket/models/ball_event.dart';
import 'package:cricket/ui/widgets/batting_clips.dart';
import 'package:cricket/ui/widgets/glb_model.dart';
import 'package:flutter_test/flutter_test.dart';

BallEvent _ball({int runs = 0, ExtraType extra = ExtraType.none, WicketType? wicket, ShotDirection? dir, List<Offset>? path, ShotLoft? loft}) => BallEvent(
      strikerId: 'a',
      nonStrikerId: 'b',
      bowlerId: 'c',
      runs: runs,
      extra: extra,
      extraRuns: extra == ExtraType.none ? 0 : 1,
      wicket: wicket,
      outPlayerId: wicket == null ? null : 'a',
      shotDirection: dir,
      shotPath: path,
      loft: loft,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recorded shots map to the right batting clip, and always the same one', () async {
    final g = await GlbModel.readGlb('assets/models/batsman.glb');
    final meta = Map<String, dynamic>.from(((g.json['scenes'] as List).first as Map)['extras']['batting'] as Map);
    final clips = BattingClips(meta);
    const o = Offset(0, -0.1385);

    BattingShot play(BallEvent b) => clips.choose(b);

    // Ground shots follow the direction the ball left the bat in (off side is positive for us).
    expect(play(_ball(runs: 4, dir: ShotDirection.cover, path: const [o, Offset(0.3, 0.0), Offset(0.8, 0.4)])).clip, 'Drive_Cover');
    expect(play(_ball(runs: 1, dir: ShotDirection.straight, path: const [o, Offset(0, 0.3), Offset(0, 0.7)])).clip, 'Drive_Straight');
    expect(play(_ball(runs: 2, dir: ShotDirection.midWicket)).clip, anyOf('Flick', 'Pull'));
    expect(play(_ball(runs: 1, dir: ShotDirection.squareLeg)).clip, anyOf('Sweep', 'Pull'));
    expect(play(_ball(runs: 1, dir: ShotDirection.point)).clip, 'Cut_Square');
    expect(play(_ball(runs: 1, dir: ShotDirection.thirdMan)).clip, 'Cut_Late');
    // Lofted shots.
    expect(play(_ball(runs: 6, dir: ShotDirection.straight, loft: ShotLoft.aerial)).clip, 'Loft_Straight');
    expect(play(_ball(runs: 6, dir: ShotDirection.cover, loft: ShotLoft.aerial)).clip, 'Loft_Cover');
    // No contact / defensive.
    expect(play(_ball(extra: ExtraType.wide)).clip, 'Leave');
    expect(play(_ball()).clip, 'Defence_Forward');
    expect(play(_ball(wicket: WicketType.bowled)).clip, 'Drive_Straight');
    expect(play(_ball(wicket: WicketType.lbw)).clip, 'Defence_Forward');

    // Every clip's contact point is known when it has contact, so the bat can be lined up with the ball.
    final drive = play(_ball(runs: 4, dir: ShotDirection.cover));
    expect(drive.contactTime, 1.0);
    expect(drive.contactPoint, isNotNull);
    expect(play(_ball(extra: ExtraType.wide)).contactPoint, isNull);

    // Deterministic: the same ball gives the same clip every time.
    final b = _ball(runs: 4, dir: ShotDirection.midOn);
    expect({for (var i = 0; i < 20; i++) clips.choose(b).clip}.length, 1);
  });
}
