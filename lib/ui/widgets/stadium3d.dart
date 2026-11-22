import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'mesh3d.dart';
import 'scene3d.dart';

const _m = 1 / 65;

/// Advertising boards along the rope and a bowl of stands full of spectators.
/// Everything is deterministic, so the stadium looks the same every frame.
void addStadium(MeshBuilder mb, {bool stands = true}) {
  const boardColors = [
    Color(0xFF123B5C),
    Color(0xFF0B0B0F),
    Color(0xFF1E7A46),
    Color(0xFFE9E9EE),
    Color(0xFF0E4D8A),
    Color(0xFFD5342B),
  ];
  const crowd = [
    Color(0xFF2B2E36),
    Color(0xFF5B606E),
    Color(0xFF8B909C),
    Color(0xFF27425F),
    Color(0xFF5A3030),
    Color(0xFF9C8466),
    Color(0xFF1E1E22),
    Color(0xFF3B5A42),
    Color(0xFF8E8A55),
    Color(0xFF6B4528),
  ];
  // Skip sections that can't be on screen: project the middle of each one.
  bool onScreen(V3 p) {
    final pr = mb.cam.project(p);
    final w = mb.cam.size.width, hh = mb.cam.size.height;
    return pr.depth > 0.02 && pr.pt.dx > -0.4 * w && pr.pt.dx < 1.4 * w && pr.pt.dy > -1.0 * hh && pr.pt.dy < 2.0 * hh;
  }

  // Cheap deterministic hash -> 0..1.
  double h(int a, int b) {
    final x = math.sin(a * 127.1 + b * 311.7) * 43758.5453;
    return x - x.floorToDouble();
  }

  const boardR = 1.02;
  final boardH = 1.0 * _m;
  const nBoard = 90;
  for (var i = 0; i < nBoard; i++) {
    final a0 = 2 * math.pi * i / nBoard, a1 = 2 * math.pi * (i + 1) / nBoard;
    final inward = V3(-math.sin((a0 + a1) / 2), -math.cos((a0 + a1) / 2), 0);
    final c = boardColors[(i ~/ 3) % boardColors.length];
    final p0 = V3(math.sin(a0) * boardR, math.cos(a0) * boardR, 0);
    final p1 = V3(math.sin(a1) * boardR, math.cos(a1) * boardR, 0);
    mb.quad(p0, p1, p1 + V3(0, 0, boardH), p0 + V3(0, 0, boardH), c, inward);
    // A bright stripe across every board so they read as advertising.
    final s0 = V3(p0.x, p0.y, boardH * 0.42), s1 = V3(p1.x, p1.y, boardH * 0.42);
    mb.quad(s0, s1, s1 + V3(0, 0, boardH * 0.16), s0 + V3(0, 0, boardH * 0.16), Colors.white.withValues(alpha: 1), inward);
  }

  if (!stands) return;

  // Stands: sloped rows of spectators.
  const nSeg = 300;
  const rows = 10;
  for (var r = 0; r < rows; r++) {
    final r0 = 1.045 + 0.0145 * r, r1 = 1.045 + 0.0145 * (r + 1);
    final z0 = 2.5 * _m + 1.7 * _m * r, z1 = z0 + 1.7 * _m;
    for (var i = 0; i < nSeg; i++) {
      final a0 = 2 * math.pi * i / nSeg, a1 = 2 * math.pi * (i + 1) / nSeg;
      final mid = (a0 + a1) / 2;
      if (!onScreen(V3(math.sin(mid) * r0, math.cos(mid) * r0, (z0 + z1) / 2))) continue;
      final inward = V3(-math.sin(mid), -math.cos(mid), 0.35);
      final base = crowd[(h(i, r) * crowd.length).floor() % crowd.length];
      // Seats / people: vary the brightness per block.
      final shade = 0.62 + 0.4 * h(i * 3 + 1, r * 5 + 2);
      final c = Color.fromARGB(255, (base.r * 255 * shade).clamp(0, 255).round(), (base.g * 255 * shade).clamp(0, 255).round(),
          (base.b * 255 * shade).clamp(0, 255).round());
      V3 p(double a, double rad, double z) => V3(math.sin(a) * rad, math.cos(a) * rad, z);
      mb.quad(p(a0, r0, z0), p(a1, r0, z0), p(a1, r1, z1), p(a0, r1, z1), c, inward);
    }
  }

  // Dark roof band and the fence in front of the crowd.
  const roofR = 1.045 + 0.0145 * rows;
  for (var i = 0; i < nBoard; i++) {
    final a0 = 2 * math.pi * i / nBoard, a1 = 2 * math.pi * (i + 1) / nBoard;
    final inward = V3(-math.sin((a0 + a1) / 2), -math.cos((a0 + a1) / 2), 0);
    final z0 = 2.5 * _m + 1.7 * _m * rows;
    V3 p(double a, double z) => V3(math.sin(a) * roofR, math.cos(a) * roofR, z);
    mb.quad(p(a0, z0), p(a1, z0), p(a1, z0 + 5 * _m), p(a0, z0 + 5 * _m), const Color(0xFF1B1D22), inward);
  }
  for (var i = 0; i < nBoard; i++) {
    final a0 = 2 * math.pi * i / nBoard, a1 = 2 * math.pi * (i + 1) / nBoard;
    final inward = V3(-math.sin((a0 + a1) / 2), -math.cos((a0 + a1) / 2), 0);
    V3 p(double a, double z) => V3(math.sin(a) * 1.035, math.cos(a) * 1.035, z);
    mb.quad(p(a0, boardH), p(a1, boardH), p(a1, 2.6 * _m), p(a0, 2.6 * _m), const Color(0xFF2A2F38), inward);
  }
}
