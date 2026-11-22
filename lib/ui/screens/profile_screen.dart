import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api/api_models.dart';
import '../../data/api/cricket_api.dart';
import '../../data/api/sync_manager.dart';
import '../../data/app_dependencies.dart';
import '../../models/player.dart';
import '../widgets/cloud_actions.dart';
import '../widgets/common.dart';

String _roleLabel(String name) =>
    PlayerRole.values.firstWhere((r) => r.name == name, orElse: () => PlayerRole.batter).label;

/// `GET/PUT /me/profile`: who I am as a cricketer. Saving also updates my own
/// player, which then shows up in the player list and can be picked for teams.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final CricketApi _api = context.read<AppDependencies>().api!;
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _phone = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _jersey = TextEditingController();

  PlayerProfile? _p;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _city, _phone, _height, _weight, _jersey]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await _api.profile();
      if (!mounted) return;
      setState(() {
        _p = p;
        _name.text = p.displayName;
        _city.text = p.city ?? '';
        _phone.text = p.phoneNumber ?? '';
        _height.text = p.heightCm == null ? '' : '${p.heightCm}';
        _weight.text = p.weightKg == null ? '' : '${p.weightKg}';
        _jersey.text = p.jerseyNumber == null ? '' : '${p.jerseyNumber}';
      });
    } catch (e) {
      if (mounted) setState(() => _error = apiMessage(e));
    }
  }

  Future<void> _pickDob() async {
    final p = _p!;
    final now = DateTime.now();
    final initial = DateTime.tryParse(p.dateOfBirth ?? '') ?? DateTime(now.year - 20);
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1940),
      lastDate: now,
    );
    if (d == null) return;
    setState(() => p.dateOfBirth =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
  }

  Future<void> _save() async {
    final p = _p!;
    if (!_form.currentState!.validate()) return;
    p
      ..displayName = _name.text.trim()
      ..city = _city.text.trim().isEmpty ? null : _city.text.trim()
      ..phoneNumber = _phone.text.trim().isEmpty ? null : _phone.text.trim()
      ..heightCm = double.tryParse(_height.text.trim())
      ..weightKg = double.tryParse(_weight.text.trim())
      ..jerseyNumber = int.tryParse(_jersey.text.trim());
    setState(() => _saving = true);
    final sync = context.read<SyncManager>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await _api.saveProfile(p);
      await sync.syncAll(); // brings my updated player into the local list
      if (!mounted) return;
      setState(() => _p = saved);
      messenger.showSnackBar(const SnackBar(content: Text('Profile saved')));
    } catch (e) {
      if (mounted) toast(context, apiMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      appBar: AppBar(title: const Text('My cricket profile')),
      body: p == null
          ? (_error != null
              ? ErrorRetry(message: _error!, onRetry: _load)
              : const Center(child: CircularProgressIndicator()))
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundImage: p.photoUrl == null ? null : NetworkImage(p.photoUrl!),
                      child: p.photoUrl == null
                          ? Text(p.displayName.isEmpty ? '?' : p.displayName[0].toUpperCase(),
                              style: const TextStyle(fontSize: 24))
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.email ?? p.phoneNumber ?? '', style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 4),
                        Text('${_roleLabel(p.role)} · ${p.battingStyle}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  const SectionHeader('ABOUT YOU'),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: p.gender,
                    decoration: const InputDecoration(labelText: 'Gender'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Prefer not to say')),
                      for (final g in genders)
                        DropdownMenuItem(value: g, child: Text(g[0].toUpperCase() + g.substring(1))),
                    ],
                    onChanged: (v) => setState(() => p.gender = v),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _pickDob,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Date of birth'),
                      child: Text(p.dateOfBirth ?? 'Not set'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _city,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'City'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone (optional)'),
                  ),
                  const SizedBox(height: 20),
                  const SectionHeader('PLAYING'),
                  DropdownButtonFormField<String>(
                    initialValue: p.role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: [
                      for (final r in PlayerRole.values) DropdownMenuItem(value: r.name, child: Text(r.label)),
                    ],
                    onChanged: (v) => setState(() => p.role = v!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: p.battingStyle,
                    decoration: const InputDecoration(labelText: 'Batting style'),
                    items: [for (final s in battingStyles) DropdownMenuItem(value: s, child: Text(s))],
                    onChanged: (v) => setState(() => p.battingStyle = v!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: p.bowlingStyle,
                    decoration: const InputDecoration(labelText: 'Bowling style'),
                    items: [for (final s in bowlingStyles) DropdownMenuItem(value: s, child: Text(s))],
                    onChanged: (v) => setState(() => p.bowlingStyle = v!),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        controller: _height,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Height (cm)'),
                        validator: (v) {
                          final n = double.tryParse((v ?? '').trim());
                          if ((v ?? '').trim().isEmpty) return null;
                          return n == null || n < 50 || n > 260 ? '50 to 260' : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _weight,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Weight (kg)'),
                        validator: (v) {
                          final n = double.tryParse((v ?? '').trim());
                          if ((v ?? '').trim().isEmpty) return null;
                          return n == null || n < 10 || n > 300 ? '10 to 300' : null;
                        },
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _jersey,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Jersey number'),
                    validator: (v) {
                      if ((v ?? '').trim().isEmpty) return null;
                      final n = int.tryParse(v!.trim());
                      return n == null || n < 0 || n > 999 ? '0 to 999' : null;
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Let other players find me'),
                    subtitle: const Text(
                        'Others can search your name, or your exact e-mail, and add you to their players. '
                        'Height, weight, birth date and phone are never shared.'),
                    value: p.isDiscoverable,
                    onChanged: (v) => setState(() => p.isDiscoverable = v),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save profile'),
                  ),
                ],
              ),
            ),
    );
  }
}
