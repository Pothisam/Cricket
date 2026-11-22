import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api/api_client.dart';
import '../../data/api/api_models.dart';
import '../../data/api/cricket_api.dart';
import '../../data/app_dependencies.dart';
import '../widgets/cloud_actions.dart';
import '../widgets/common.dart';

/// `GET /devices`, `PATCH /devices/{id}`, `DELETE /devices/{id}`.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late final CricketApi _api = context.read<AppDependencies>().api!;
  List<ApiDevice>? _devices;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await _api.devices();
      if (mounted) setState(() => _devices = d);
    } catch (e) {
      if (mounted) setState(() => _error = apiMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _devices;
    return Scaffold(
      appBar: AppBar(title: const Text('Signed-in devices')),
      body: _error != null && list == null
          ? ErrorRetry(message: _error!, onRetry: _load)
          : RefreshIndicator(
        onRefresh: _load,
        child: list == null
            ? ListView(children: const [
                SizedBox(height: 120),
                Center(child: CircularProgressIndicator()),
              ])
            : ListView(
                children: [
                  for (final d in list)
                    ListTile(
                      leading: Icon(switch (d.platform) {
                        'android' => Icons.phone_android,
                        'ios' => Icons.phone_iphone,
                        _ => Icons.language,
                      }),
                      title: Text('${d.deviceModel?.isNotEmpty == true ? d.deviceModel : d.platform}'
                          '${d.isCurrent ? '  (this device)' : ''}'),
                      subtitle: Text('v${d.appVersion ?? '?'} · last seen ${_fmt(d.lastSeenAt)}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Switch(
                          value: d.notificationsEnabled,
                          onChanged: (v) async {
                            try {
                              await _api.updateDevice(d.id, notificationsEnabled: v);
                              await _load();
                            } on ApiException catch (e) {
                              if (context.mounted) toast(context, e.message);
                            }
                          },
                        ),
                        if (!d.isCurrent)
                          IconButton(
                            icon: const Icon(Icons.logout),
                            tooltip: 'Remove device',
                            onPressed: () async {
                              if (!await confirm(context, 'Remove device?',
                                  'It will stop receiving notifications.',
                                  action: 'Remove')) {
                                return;
                              }
                              try {
                                await _api.deleteDevice(d.id);
                                await _load();
                              } on ApiException catch (e) {
                                if (context.mounted) toast(context, e.message);
                              }
                            },
                          ),
                      ]),
                    ),
                  if (list.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No devices')),
                ],
              ),
      ),
    );
  }

  static String _fmt(DateTime? t) {
    if (t == null) return '-';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 2) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}
