import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api/api_client.dart';
import '../../data/api/api_models.dart';
import '../../data/api/cricket_api.dart';
import '../../data/app_dependencies.dart';
import '../widgets/common.dart';

IconData _iconFor(String type) => switch (type) {
      'six' || 'four' => Icons.sports_cricket,
      'wicket' => Icons.close,
      'milestone' => Icons.emoji_events_outlined,
      'match_start' => Icons.play_circle_outline,
      'innings_end' => Icons.flag_outlined,
      'match_result' => Icons.emoji_events,
      'login' => Icons.login,
      _ => Icons.notifications_none,
    };

/// `GET /notifications`, read / read-all / delete, preferences and test push.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final CricketApi _api = context.read<AppDependencies>().api!;
  final List<ApiNotification> _items = [];
  String? _cursor;
  int _unread = 0;
  bool _unreadOnly = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _cursor = null;
      }
    });
    try {
      final r = await _api.inbox(unreadOnly: _unreadOnly, cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _items.addAll(r.items);
        _cursor = r.nextCursor;
        _unread = r.unreadCount;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_unread > 0 ? 'Notifications ($_unread)' : 'Notifications'),
        actions: [
          IconButton(
            tooltip: _unreadOnly ? 'Show all' : 'Unread only',
            icon: Icon(_unreadOnly ? Icons.mark_email_unread : Icons.filter_list),
            onPressed: () {
              _unreadOnly = !_unreadOnly;
              _load(reset: true);
            },
          ),
          IconButton(
            tooltip: 'Mark all read',
            icon: const Icon(Icons.done_all),
            onPressed: () => _run(() async {
              await _api.markAllRead();
              await _load(reset: true);
            }),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_items.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 120),
        Center(
          child: _loading
              ? const CircularProgressIndicator()
              : Text(_error ?? (_unreadOnly ? 'No unread notifications' : 'No notifications yet')),
        ),
      ]);
    }
    return ListView.builder(
      itemCount: _items.length + (_cursor != null ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _items.length) {
          return TextButton(
            onPressed: _loading ? null : () => _load(),
            child: const Text('Load more'),
          );
        }
        final n = _items[i];
        return Dismissible(
          key: ValueKey(n.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Theme.of(context).colorScheme.errorContainer,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete_outline),
          ),
          onDismissed: (_) {
            setState(() => _items.removeAt(i));
            _run(() => _api.deleteNotification(n.id));
          },
          child: ListTile(
            leading: Icon(_iconFor(n.type)),
            title: Text(n.title, style: TextStyle(fontWeight: n.unread ? FontWeight.bold : null)),
            subtitle: Text('${n.body}\n${_ago(n.createdAt)}'),
            isThreeLine: true,
            trailing: n.unread ? const Icon(Icons.circle, size: 10) : null,
            onTap: n.unread
                ? () => _run(() async {
                      await _api.markRead(n.id);
                      if (mounted) {
                        setState(() {
                          n.readAt = DateTime.now();
                          if (_unread > 0) _unread--;
                        });
                      }
                    })
                : null,
          ),
        );
      },
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

/// `GET/PUT /notifications/preferences` and `POST /notifications/test`.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  late final CricketApi _api = context.read<AppDependencies>().api!;
  NotificationPrefs? _p;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api.preferences().then((p) {
      if (mounted) setState(() => _p = p);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : '$e');
    });
  }

  Future<void> _save() async {
    try {
      final saved = await _api.savePreferences(_p!);
      if (mounted) setState(() => _p = saved);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _pickTime(bool start) async {
    final cur = (start ? _p!.quietHoursStart : _p!.quietHoursEnd) ?? (start ? '23:00' : '07:00');
    final parts = cur.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (t == null) return;
    final v = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() => start ? _p!.quietHoursStart = v : _p!.quietHoursEnd = v);
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      appBar: AppBar(title: const Text('Notification settings')),
      body: p == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : ListView(children: [
              _sw('New sign-in alerts', p.loginAlerts, (v) => p.loginAlerts = v),
              _sw('Match started', p.matchStart, (v) => p.matchStart = v),
              _sw('Fours and sixes', p.boundaries, (v) => p.boundaries = v),
              _sw('Wickets', p.wickets, (v) => p.wickets = v),
              _sw('Milestones (50 / 100)', p.milestones, (v) => p.milestones = v),
              _sw('Innings break', p.inningsEnd, (v) => p.inningsEnd = v),
              _sw('Match result', p.matchResult, (v) => p.matchResult = v),
              const SectionHeader('QUIET HOURS'),
              ListTile(
                title: const Text('From'),
                trailing: Text(p.quietHoursStart ?? 'Off'),
                onTap: () => _pickTime(true),
              ),
              ListTile(
                title: const Text('Until'),
                trailing: Text(p.quietHoursEnd ?? 'Off'),
                onTap: () => _pickTime(false),
              ),
              if (p.quietHoursStart != null || p.quietHoursEnd != null)
                TextButton(
                  onPressed: () {
                    setState(() {
                      p.quietHoursStart = null;
                      p.quietHoursEnd = null;
                    });
                    _save();
                  },
                  child: const Text('Clear quiet hours'),
                ),
              const SectionHeader('TEST'),
              ListTile(
                leading: const Icon(Icons.send_outlined),
                title: const Text('Send a test notification'),
                subtitle: const Text('Sent to your signed-in devices'),
                onTap: () async {
                  try {
                    final (sent, failed) = await _api.sendTest();
                    if (context.mounted) toast(context, 'Sent: $sent, failed: $failed');
                  } on ApiException catch (e) {
                    if (context.mounted) toast(context, e.message);
                  }
                },
              ),
            ]),
    );
  }

  Widget _sw(String label, bool value, void Function(bool) set) => SwitchListTile(
        title: Text(label),
        value: value,
        onChanged: (v) {
          setState(() => set(v));
          _save();
        },
      );
}
