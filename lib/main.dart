import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'data/app_repository.dart';
import 'ui/app_theme.dart';
import 'ui/calculator_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(HasrApp());
}

class HasrApp extends StatelessWidget {
  HasrApp({super.key, AppRepository? repository})
    : repository = repository ?? AppRepository();
  final AppRepository repository;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'حصر القواعد',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: appTheme(),
    home: CalculatorScreen(repository: repository),
  );
}
