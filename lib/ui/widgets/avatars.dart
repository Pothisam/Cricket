import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/player.dart';
import '../../state/auth_controller.dart';

/// Round picture of a person: their photo when they have one (for example the
/// Google profile picture), otherwise the first letter of their name. A photo
/// that cannot be loaded quietly falls back to the letter.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.radius = 20,
  });

  final String name;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    final hasPhoto = url != null && url.isNotEmpty;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: radius,
      // The letter is always underneath: it shows while the photo loads or if it fails.
      foregroundImage: hasPhoto ? NetworkImage(url) : null,
      onForegroundImageError: hasPhoto ? (_, _) {} : null,
      child: Text(initial, style: TextStyle(fontSize: radius * 0.85)),
    );
  }
}

/// The signed-in user: the photo of their account (Google picture) or their initial.
class CurrentUserAvatar extends StatelessWidget {
  const CurrentUserAvatar({
    super.key,
    this.radius = 20,
    this.photoUrl,
    this.name,
  });

  final double radius;

  /// A photo already known from the server; the Firebase account photo is the fallback.
  final String? photoUrl;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    final label =
        name ?? user?.displayName ?? user?.email ?? user?.phoneNumber ?? '?';
    return UserAvatar(
      name: label,
      photoUrl: (photoUrl?.isNotEmpty ?? false) ? photoUrl : user?.photoURL,
      radius: radius,
    );
  }
}

/// A player in a list or header. The account owner's own player shows their
/// sign-in photo, other registered users show the photo they have on their profile.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar(this.player, {super.key, this.radius = 20});

  final Player player;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (player.isSelf) {
      return CurrentUserAvatar(
        radius: radius,
        photoUrl: player.photoUrl,
        name: player.name,
      );
    }
    return UserAvatar(
      name: player.name,
      photoUrl: player.photoUrl,
      radius: radius,
    );
  }
}
