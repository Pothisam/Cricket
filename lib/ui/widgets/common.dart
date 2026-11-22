import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/ball_event.dart';
import '../../models/team.dart';

class TeamAvatar extends StatelessWidget {
  const TeamAvatar({super.key, required this.short, this.colorIndex = 0, this.size = 40});

  final String short;
  final int colorIndex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final text = short.length > 3 ? short.substring(0, 3) : short;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: teamColors[colorIndex % teamColors.length],
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size * (text.length > 2 ? 0.3 : 0.38),
        ),
      ),
    );
  }

  factory TeamAvatar.of(Team t, {double size = 40}) =>
      TeamAvatar(short: t.shortName, colorIndex: t.colorIndex, size: size);
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: cs.outline),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (message case final msg?) ...[
              const SizedBox(height: 6),
              Text(msg,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Small round marker for a single delivery in an over.
class BallBubble extends StatelessWidget {
  const BallBubble(this.ball, {super.key, this.size = 30});
  final BallEvent ball;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color bg = cs.surfaceContainerHighest;
    Color fg = cs.onSurface;
    if (ball.isWicket) {
      bg = Colors.red.shade600;
      fg = Colors.white;
    } else if (ball.extra == ExtraType.none && ball.runs == 6) {
      bg = Colors.purple.shade600;
      fg = Colors.white;
    } else if (ball.extra == ExtraType.none && ball.runs == 4) {
      bg = Colors.blue.shade600;
      fg = Colors.white;
    } else if (ball.extra != ExtraType.none) {
      bg = Colors.orange.shade700;
      fg = Colors.white;
    }
    final label = ball.label;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(label,
          style: TextStyle(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: label.length > 2 ? size * 0.3 : size * 0.4)),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

String two(num n) => n.toStringAsFixed(2);

String formatDate(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

Future<bool> confirm(BuildContext context, String title, String message,
    {String action = 'Delete'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ],
    ),
  );
  return r ?? false;
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}
