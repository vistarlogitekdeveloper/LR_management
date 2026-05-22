import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const plum = Color(0xFF7A1F6E);
  static const plumDark = Color(0xFF5E1654);
  static const plumLight = Color(0xFF9C3A90);

  static const orange = Color(0xFFF5821F);
  static const amber = Color(0xFFFFB422);
  static const red = Color(0xFFE8342A);

  static const ink = Color(0xFF241726);
  static const slate = Color(0xFF6B6473);
  static const mist = Color(0xFFF7F4F9);
  static const line = Color(0xFFECE6F0);

  static const white = Color(0xFFFFFFFF);
  static const ok = Color(0xFF1F9D6B);
  static const warn = Color(0xFFCF8A1E);
  static const danger = Color(0xFFD6453B);

  static const inputBg = Color(0xFFFCFBFD);

  static const brandGradient = LinearGradient(
    begin: Alignment(-1, -0.2),
    end: Alignment(1, 0.2),
    stops: [0, 0.34, 0.56, 1.0],
    colors: [red, orange, amber, plumLight],
  );

  static const loginHeroGradient = RadialGradient(
    center: Alignment(-1, -1),
    radius: 1.4,
    colors: [plumLight, plum, plumDark],
    stops: [0, 0.4, 1],
  );
}
