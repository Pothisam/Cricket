import 'package:cricket/ui/widgets/squad_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SquadEntry entry(
  String id,
  String name, {
  bool captain = false,
  bool vice = false,
  bool admin = false,
  bool owner = false,
  bool canBeAdmin = false,
  String? removeNote,
}) => SquadEntry(
  id: id,
  avatar: CircleAvatar(child: Text(name[0])),
  title: name,
  subtitle: 'Batter',
  captain: captain,
  vice: vice,
  admin: admin,
  owner: owner,
  canBeAdmin: canBeAdmin,
  removeNote: removeNote,
);

Widget host(List<SquadEntry> entries, {void Function(String, bool)? onAdmin}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SquadList(
            entries: entries,
            onReorder: (_, _) {},
            onCaptain: (_, _) {},
            onVice: (_, _) {},
            onRemove: (_) {},
            onAdmin: onAdmin,
          ),
        ),
      ),
    );

void main() {
  testWidgets('shows OWNER, ADMIN, C and VC next to the names', (tester) async {
    await tester.pumpWidget(
      host([
        entry('1', 'Pothi', owner: true),
        entry('2', 'Kathir', captain: true),
        entry('3', 'Raj', vice: true, admin: true),
        entry('4', 'Siva'),
      ]),
    );

    expect(find.text('OWNER'), findsOneWidget);
    expect(find.text('ADMIN'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(find.text('VC'), findsOneWidget);
    // Raj is vice-captain AND admin: both labels are on his row
    expect(find.text('Raj'), findsOneWidget);
  });

  testWidgets(
    'a registered player can be made admin, a player without an account cannot',
    (tester) async {
      String? calledFor;
      bool? calledMake;
      await tester.pumpWidget(
        host(
          [
            entry('reg', 'Registered', canBeAdmin: true),
            entry('man', 'Manual'),
          ],
          onAdmin: (id, make) {
            calledFor = id;
            calledMake = make;
          },
        ),
      );

      // the menu of the registered player
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      expect(find.text('Make admin'), findsOneWidget);
      expect(find.text('Make captain'), findsOneWidget);
      expect(find.text('Make vice-captain'), findsOneWidget);
      await tester.tap(find.text('Make admin'));
      await tester.pumpAndSettle();
      expect(calledFor, 'reg');
      expect(calledMake, isTrue);

      // the menu of the manual player: admin is offered but explained
      await tester.tap(find.byIcon(Icons.more_vert).last);
      await tester.pumpAndSettle();
      expect(find.text('Needs an app account'), findsOneWidget);
      calledFor = null;
      await tester.tap(find.text('Make admin'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(calledFor, isNull); // disabled: nothing happened
    },
  );

  testWidgets('an admin can be taken away, and the owner cannot be removed', (
    tester,
  ) async {
    bool? make;
    await tester.pumpWidget(
      host([
        entry('a', 'Admin', admin: true, canBeAdmin: true),
        entry(
          'o',
          'Owner',
          owner: true,
          removeNote: 'The creator stays in the team',
        ),
      ], onAdmin: (_, m) => make = m),
    );

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove admin'));
    await tester.pumpAndSettle();
    expect(make, isFalse);

    await tester.tap(find.byIcon(Icons.more_vert).last);
    await tester.pumpAndSettle();
    expect(find.text('The creator stays in the team'), findsOneWidget);
  });

  testWidgets(
    'without an admin callback (a manager looking at the team) there is no admin option',
    (tester) async {
      await tester.pumpWidget(host([entry('1', 'Someone', canBeAdmin: true)]));
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Make admin'), findsNothing);
      expect(find.text('Make captain'), findsOneWidget);
    },
  );
}
