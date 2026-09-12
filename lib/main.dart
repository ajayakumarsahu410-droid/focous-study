import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/alarm_service.dart';
import 'services/notification_service.dart';
import 'state/study_controller.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await NotificationService.instance.init();
  await AlarmService.instance.init();

  final controller = StudyController();
  await controller.bootstrap();

  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const FocusStudyApp(),
    ),
  );
}

class FocusStudyApp extends StatelessWidget {
  const FocusStudyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6366F1),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'Focus Study',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF0B1020),
        cardTheme: CardTheme(
          color: const Color(0xFF151B30),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      home: const HomeShell(),
    );
  }
}
