import 'package:cricket/ui/widgets/shot_direction_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('drag draws a path and saves it', (tester) async {
    ShotChoice? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => result = await pickShot(ctx, title: '4 runs', runs: 4),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final canvas = find.byType(CustomPaint).last;
    final box = tester.getRect(find.byType(AspectRatio).first);
    final start = box.center + const Offset(0, 20);
    final g = await tester.startGesture(start);
    for (var i = 1; i <= 12; i++) {
      await g.moveTo(start + Offset(i * 12.0, -i * 14.0));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('Save shot'), findsOneWidget);
    await tester.tap(find.text('Save shot'));
    await tester.pumpAndSettle();
    expect(canvas, findsOneWidget);
    expect(result, isNotNull);
    expect(result!.path, isNotNull);
    expect(result!.path!.last.distance, greaterThanOrEqualTo(0.98)); // a four runs to the rope
  });
}
