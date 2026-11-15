import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'project/repository.dart';
import 'ui/app_theme.dart';
import 'ui/project_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(HasrApp());
}

class HasrApp extends StatelessWidget {
  HasrApp({super.key, ProjectRepository? repository})
    : repository = repository ?? ProjectRepository();
  final ProjectRepository repository;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'حصر المشروع',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: appTheme(),
    home: ProjectShell(repository: repository),
  );
}
