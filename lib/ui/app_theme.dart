import 'package:flutter/material.dart';

const primaryGreen = Color(0xFF246B57);
const secondaryText = Color(0xFF75807B);
const borderColor = Color(0xFFE2E7E3);

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: primaryGreen,
    primary: primaryGreen,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Cairo',
    scaffoldBackgroundColor: const Color(0xFFF6F7F5),
    textTheme: ThemeData.light().textTheme.apply(
      fontFamily: 'Cairo',
      bodyColor: const Color(0xFF202A28),
      displayColor: const Color(0xFF202A28),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF6F7F5),
      foregroundColor: Color(0xFF202A28),
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Cairo',
        color: Color(0xFF202A28),
        fontSize: 23,
        fontWeight: FontWeight.w700,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryGreen, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        side: const BorderSide(color: primaryGreen),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: borderColor,
      thickness: 1,
      space: 1,
    ),
  );
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderColor),
    ),
    child: child,
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 19, color: primaryGreen),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
