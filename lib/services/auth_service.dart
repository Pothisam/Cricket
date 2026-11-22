import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

/// Wraps Firebase Auth: Google sign-in and phone (SMS OTP) sign-in.
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  /// Web OAuth client (client_type 3) from google-services.json.
  static const _webClientId =
      '592739044483-t0m8vq01tqgelf35l910vdvnceej5cn1.apps.googleusercontent.com';

  final FirebaseAuth _auth;
  bool _googleReady = false;

  Stream<User?> get userChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> _initGoogle() async {
    if (_googleReady) return;
    await GoogleSignIn.instance.initialize(serverClientId: _webClientId);
    _googleReady = true;
  }

  ConfirmationResult? _webConfirmation;

  Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) return _auth.signInWithPopup(GoogleAuthProvider());
    await _initGoogle();
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return _auth.signInWithCredential(credential);
  }

  /// Sends an OTP. [onCodeSent] gets the verificationId to use in [verifyOtp].
  /// [onAutoVerified] fires when Android auto-reads the SMS.
  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(String message) onError,
    required void Function(UserCredential) onAutoVerified,
    int? resendToken,
  }) async {
    if (kIsWeb) {
      // Web uses signInWithPhoneNumber (invisible reCAPTCHA is handled by the SDK).
      try {
        _webConfirmation = await _auth.signInWithPhoneNumber(phoneNumber);
        onCodeSent('web', null);
      } on FirebaseAuthException catch (e) {
        onError(e.message ?? e.code);
      }
      return;
    }
    return _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      forceResendingToken: resendToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        try {
          onAutoVerified(await _auth.signInWithCredential(credential));
        } on FirebaseAuthException catch (e) {
          onError(e.message ?? e.code);
        }
      },
      verificationFailed: (e) => onError(e.message ?? e.code),
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<UserCredential> verifyOtp(String verificationId, String smsCode) {
    final web = _webConfirmation;
    if (kIsWeb && web != null) return web.confirm(smsCode);
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return _auth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    if (_googleReady) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await _auth.signOut();
  }
}
