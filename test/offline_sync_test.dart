import 'package:cricket/data/api/sync_manager.dart';
import 'package:cricket/data/api/sync_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('failed attempts back off: 30 s, 1 min, 2 min, 4 min, then 5 min at most', () {
    expect(SyncManager.backoff(1), const Duration(seconds: 30));
    expect(SyncManager.backoff(2), const Duration(seconds: 60));
    expect(SyncManager.backoff(3), const Duration(seconds: 120));
    expect(SyncManager.backoff(4), const Duration(seconds: 240));
    expect(SyncManager.backoff(5), const Duration(seconds: 300));
    expect(SyncManager.backoff(50), const Duration(seconds: 300));
  });

  test('changes made offline stay marked as waiting until they are sent', () async {
    SharedPreferences.setMockInitialValues({});
    final state = SyncState(await SharedPreferences.getInstance());
    expect(state.hasPending, isFalse);

    // offline: a new team, an edited player, a deleted match
    await state.markDirty(SyncState.teams, 't1');
    await state.markDirty(SyncState.players, 'p1');
    await state.markDeleted(SyncState.matches, 'm1');
    expect(state.hasPending, isTrue);
    expect(state.dirty(SyncState.teams), {'t1'});
    expect(state.deleted(SyncState.matches), {'m1'});

    // back online: the server accepted the team and the player, but not the delete yet
    await state.clearDirty(SyncState.teams, ['t1']);
    await state.clearDirty(SyncState.players, ['p1']);
    expect(state.hasPending, isTrue);

    await state.clearDeleted(SyncState.matches, ['m1']);
    expect(state.hasPending, isFalse);
  });

  test('deleting something that was never sent cancels its waiting change', () async {
    SharedPreferences.setMockInitialValues({});
    final state = SyncState(await SharedPreferences.getInstance());
    await state.markDirty(SyncState.teams, 't9');
    await state.markDeleted(SyncState.teams, 't9');
    expect(state.dirty(SyncState.teams), isEmpty);
    expect(state.deleted(SyncState.teams), {'t9'});
  });
}
