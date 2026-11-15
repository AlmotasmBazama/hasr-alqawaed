// Retained v1 UI regression harness. The production entry point uses ProjectShell.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hasr_alqawaed/data/app_repository.dart';
import 'package:hasr_alqawaed/ui/app_theme.dart';
import 'package:hasr_alqawaed/ui/calculator_screen.dart';

class LegacyHasrApp extends StatelessWidget {
  const LegacyHasrApp({super.key, required this.repository});
  final AppRepository repository;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: appTheme(),
    home: CalculatorScreen(repository: repository),
  );
}
