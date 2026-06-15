import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'screens/auth_gate.dart';
import 'screens/home_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/settings_screen.dart';
import 'services/sensor_config.dart';
import 'services/supabase_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.init();
  await themeController.load();
  await sensorConfig.load();
  final cameras = await availableCameras();
  runApp(MEDSApp(cameras: cameras));
}

class MEDSApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MEDSApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) => MaterialApp(
        title: 'MEDS',
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: themeController.mode,
        home: AuthGate(cameras: cameras),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  final List<CameraDescription> cameras;

  const MainShell({super.key, required this.cameras});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  int _sessionsReloadToken = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(
            cameras: widget.cameras,
            onOpenTab: (i) => setState(() => _index = i),
            onSessionEnded: () => setState(() {
              _sessionsReloadToken++;
              _index = 1;
            }),
          ),
          SessionsScreen(key: ValueKey(_sessionsReloadToken)),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.event_note_outlined),
            activeIcon: Icon(Icons.event_note),
            label: 'Sessions',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
