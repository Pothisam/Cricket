import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../data/api/sync_manager.dart';
import '../services/auth_service.dart';

class AuthController extends ChangeNotifier {
  AuthController(this._service, {SyncManager? sync}) : _sync = sync {
    user = _service.currentUser;
    if (user != null) _sync?.startSession(user!.uid);
    _service.userChanges.listen((u) {
      user = u;
      notifyListeners();
      // Login hook: register this device (FCM token) and sync data.
      if (u != null) _sync?.startSession(u.uid);
    });
  }

  final AuthService _service;
  final SyncManager? _sync;

  User? user;
  bool busy = false;
  String? error;
  String? _verificationId;
  int? _resendToken;
  bool get otpSent => _verificationId != null;
  bool get signedIn => user != null;

  void _set({bool? busy, String? error}) {
    if (busy != null) this.busy = busy;
    this.error = error;
    notifyListeners();
  }

  Future<void> google() async {
    _set(busy: true);
    try {
      await _service.signInWithGoogle();
      _set(busy: false);
    } on GoogleSignInException catch (e) {
      _set(
        busy: false,
        error: e.code == GoogleSignInExceptionCode.canceled
            ? null
            : 'Google sign-in failed: ${e.description ?? e.code.name}',
      );
    } on FirebaseAuthException catch (e) {
      _set(busy: false, error: e.message ?? e.code);
    } catch (e) {
      _set(busy: false, error: '$e');
    }
  }

  Future<void> sendOtp(String phone) async {
    _set(busy: true);
    await _service.sendOtp(
      phoneNumber: phone,
      resendToken: _resendToken,
      onCodeSent: (id, token) {
        _verificationId = id;
        _resendToken = token;
        _set(busy: false);
      },
      onError: (m) => _set(busy: false, error: m),
      onAutoVerified: (_) => _set(busy: false),
    );
  }

  Future<void> verifyOtp(String code) async {
    final id = _verificationId;
    if (id == null) return;
    _set(busy: true);
    try {
      await _service.verifyOtp(id, code);
      _set(busy: false);
    } on FirebaseAuthException catch (e) {
      _set(busy: false, error: e.message ?? e.code);
    }
  }

  void changeNumber() {
    _verificationId = null;
    _resendToken = null;
    _set();
  }

  Future<void> signOut() async {
    await _sync
        ?.endSession(); // POST /auth/logout while the token is still valid
    await _service.signOut();
    changeNumber();
  }

  /// `DELETE /me` removes the account and all server data, then clears this device.
  Future<void> deleteAccount() async {
    _set(busy: true);
    try {
      await _sync?.api.deleteMe();
      await _sync?.wipeLocal();
      try {
        await _service.signOut();
      } catch (_) {}
      changeNumber();
      _set(busy: false);
    } catch (e) {
      _set(busy: false, error: '$e');
      rethrow;
    }
  }
}
