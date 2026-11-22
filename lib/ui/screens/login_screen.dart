import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  String _dial = '+91';

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.sports_cricket,
                      size: 72, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('Cricket Scorer',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text('Sign in or create an account',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: auth.busy ? null : () => auth.google(),
                    icon: const Icon(Icons.g_mobiledata, size: 28),
                    label: const Text('Continue with Google'),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Row(children: [
                      Expanded(child: Divider()),
                      Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('or')),
                      Expanded(child: Divider()),
                    ]),
                  ),
                  if (!auth.otpSent) ..._phoneStep(auth) else ..._otpStep(auth),
                  if (auth.busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (auth.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(auth.error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.error)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _phoneStep(AuthController auth) => [
        Row(children: [
          SizedBox(
            width: 110,
            child: DropdownButtonFormField<String>(
              initialValue: _dial,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              ),
              items: const ['+91', '+1', '+44', '+61', '+92', '+94', '+880']
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _dial = v ?? _dial),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Mobile number', border: OutlineInputBorder()),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: auth.busy
              ? null
              : () {
                  final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
                  if (digits.length < 6) return;
                  auth.sendOtp('$_dial$digits');
                },
          child: const Text('Send OTP'),
        ),
      ];

  List<Widget> _otpStep(AuthController auth) => [
        TextField(
          controller: _otp,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
              labelText: 'Enter 6-digit OTP', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: auth.busy ? null : () => auth.verifyOtp(_otp.text.trim()),
          child: const Text('Verify & continue'),
        ),
        TextButton(
            onPressed: auth.changeNumber, child: const Text('Change number')),
      ];
}
