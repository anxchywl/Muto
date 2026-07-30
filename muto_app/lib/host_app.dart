import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// Standalone host. It owns the application shell — theme, locale, and
/// lifecycle — and mounts the marketplace feature inside it.
class HostApp extends StatelessWidget {
  const HostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: const Scaffold(body: SizedBox.shrink()),
    );
  }
}
