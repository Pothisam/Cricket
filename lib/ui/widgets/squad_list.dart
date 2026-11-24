import 'package:flutter/material.dart';

/// One row of a squad.
class SquadEntry {
  const SquadEntry({
    required this.id,
    required this.avatar,
    required this.title,
    required this.subtitle,
    this.captain = false,
    this.vice = false,
    this.admin = false,
    this.owner = false,
    this.canBeAdmin = false,
    this.removeNote,
    this.onTap,
  });

  final String id;
  final Widget avatar;
  final String title;
  final String subtitle;
  final bool captain;
  final bool vice;

  /// Admin: a registered player the team was handed over to. Can run the team, not delete it.
  final bool admin;

  /// The creator of the team.
  final bool owner;

  /// Only players with an app account can be admins.
  final bool canBeAdmin;

  /// When set, the player cannot be removed and this is shown as the reason.
  final String? removeNote;
  final VoidCallback? onTap;
}

/// The squad of a team in batting order.
///
/// * drag the handle to change the order
/// * the menu gives the roles: captain, vice-captain and (for registered players) admin,
///   or removes the player. Captain and vice-captain belong to this team only.
class SquadList extends StatelessWidget {
  const SquadList({
    super.key,
    required this.entries,
    required this.onReorder,
    required this.onCaptain,
    required this.onVice,
    required this.onRemove,
    this.onAdmin,
  });

  final List<SquadEntry> entries;

  /// [newIndex] is the position after the player was taken out (ReorderableListView.onReorderItem).
  final void Function(int oldIndex, int newIndex) onReorder;

  /// [make] = true gives the role, false takes it away.
  final void Function(String id, bool make) onCaptain;
  final void Function(String id, bool make) onVice;
  final void Function(String id) onRemove;

  /// Null hides the admin option (only the creator hands a team over).
  final void Function(String id, bool make)? onAdmin;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: entries.length,
      onReorderItem: onReorder,
      itemBuilder: (context, i) {
        final e = entries[i];
        return ListTile(
          key: ValueKey(e.id),
          leading: e.avatar,
          title: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 2,
            children: [
              Text(e.title, overflow: TextOverflow.ellipsis),
              if (e.owner) const RoleBadge(RoleKind.owner),
              if (e.admin) const RoleBadge(RoleKind.admin),
              if (e.captain) const RoleBadge(RoleKind.captain),
              if (e.vice) const RoleBadge(RoleKind.vice),
            ],
          ),
          subtitle: Text(e.subtitle),
          onTap: e.onTap,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<String>(
                tooltip: 'Player options',
                onSelected: (v) {
                  switch (v) {
                    case 'captain':
                      onCaptain(e.id, !e.captain);
                    case 'vice':
                      onVice(e.id, !e.vice);
                    case 'admin':
                      onAdmin?.call(e.id, !e.admin);
                    case 'remove':
                      onRemove(e.id);
                  }
                },
                itemBuilder: (_) => [
                  _item(
                    'captain',
                    Icons.workspace_premium_outlined,
                    e.captain ? 'Remove captain' : 'Make captain',
                  ),
                  _item(
                    'vice',
                    Icons.military_tech_outlined,
                    e.vice ? 'Remove vice-captain' : 'Make vice-captain',
                  ),
                  if (onAdmin != null) ...[
                    const PopupMenuDivider(),
                    _item(
                      'admin',
                      Icons.admin_panel_settings_outlined,
                      e.admin ? 'Remove admin' : 'Make admin',
                      enabled: e.canBeAdmin || e.admin,
                      note: e.canBeAdmin || e.admin
                          ? (e.admin ? null : 'Can run the team, not delete it')
                          : 'Needs an app account',
                    ),
                  ],
                  const PopupMenuDivider(),
                  _item(
                    'remove',
                    Icons.person_remove_outlined,
                    'Remove from team',
                    enabled: e.removeNote == null,
                    note: e.removeNote,
                  ),
                ],
              ),
              ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.drag_handle),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  PopupMenuItem<String> _item(
    String value,
    IconData icon,
    String label, {
    bool enabled = true,
    String? note,
  }) {
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label),
                if (note != null)
                  Text(note, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum RoleKind { owner, admin, captain, vice }

/// Small label next to a player's name: OWNER, ADMIN, C or VC.
class RoleBadge extends StatelessWidget {
  const RoleBadge(this.kind, {super.key});
  final RoleKind kind;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (label, bg, fg, tip) = switch (kind) {
      RoleKind.owner => (
        'OWNER',
        cs.surfaceContainerHighest,
        cs.onSurface,
        'Created the team',
      ),
      RoleKind.admin => (
        'ADMIN',
        cs.tertiaryContainer,
        cs.onTertiaryContainer,
        'Admin: can run the team',
      ),
      RoleKind.captain => (
        'C',
        cs.primaryContainer,
        cs.onPrimaryContainer,
        'Captain',
      ),
      RoleKind.vice => (
        'VC',
        cs.secondaryContainer,
        cs.onSecondaryContainer,
        'Vice-captain',
      ),
    };
    return Tooltip(
      message: tip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: fg,
          ),
        ),
      ),
    );
  }
}
