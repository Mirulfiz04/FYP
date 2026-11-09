import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// Lets the user pick the app theme (Light / Dark / System). Drives the global
/// [themeController], which persists the choice across launches.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeader(
            title: 'Theme',
            icon: Icons.palette_outlined,
            color: MedsColors.purple,
          ),
          AppCard(
            child: AnimatedBuilder(
              animation: themeController,
              builder: (context, _) => RadioGroup<ThemeMode>(
                groupValue: themeController.mode,
                onChanged: (m) {
                  if (m != null) themeController.setMode(m);
                },
                child: const Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      contentPadding: EdgeInsets.zero,
                      value: ThemeMode.light,
                      secondary: Icon(Icons.light_mode_outlined),
                      title: Text('Light'),
                    ),
                    RadioListTile<ThemeMode>(
                      contentPadding: EdgeInsets.zero,
                      value: ThemeMode.dark,
                      secondary: Icon(Icons.dark_mode_outlined),
                      title: Text('Dark'),
                    ),
                    RadioListTile<ThemeMode>(
                      contentPadding: EdgeInsets.zero,
                      value: ThemeMode.system,
                      secondary: Icon(Icons.brightness_auto_outlined),
                      title: Text('System default'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
