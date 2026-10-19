import 'package:flutter/material.dart';

const ink = Color(0xFF0C141B);
const panel = Color(0xFF17232D);
const lime = Color(0xFFD4F878);
const muted = Color(0xFF9AABB7);
const recoveryBlue = Color(0xFF8BD6EA);

final runningTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: ink,
  colorScheme: ColorScheme.fromSeed(
    seedColor: lime,
    brightness: Brightness.dark,
    primary: lime,
    surface: panel,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: ink,
    foregroundColor: Colors.white,
    centerTitle: false,
    elevation: 0,
  ),
  cardTheme: CardThemeData(
    color: panel,
    elevation: 0,
    margin: const EdgeInsets.symmetric(vertical: 6),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 54),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: panel,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
  ),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: ink,
    indicatorColor: Color(0xFF31432A),
  ),
  dividerTheme: const DividerThemeData(color: Color(0xFF2B3B46)),
);

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w700,
            letterSpacing: -.5,
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(subtitle!, style: const TextStyle(color: muted)),
          ),
      ],
    ),
  );
}
