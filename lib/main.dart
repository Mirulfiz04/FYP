import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth_gate.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/session_readiness_screen.dart';
import 'services/local_notifications.dart';
import 'services/notification_prefs.dart';
import 'services/notification_router.dart';
import 'services/notification_service.dart';
import 'services/sensor_config.dart';
import 'services/supabase_service.dart';
import 'theme/app_theme.dart';
import 'widgets/meds_bottom_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.init();
  await themeController.load();
  await sensorConfig.load();
  await notificationPrefs.load();

  // Wire the notification system: backend persistence, OS push and settings
  // sync. These are injected here so the services stay decoupled/testable.
  notifications.repo = SupabaseService();
  notifications.push = LocalNotifications.show;
  notificationPrefs.onSync =
      (settings) => SupabaseService().saveNotificationSettings(settings);

  await LocalNotifications.init(onSelect: handleDeepLink);
  await LocalNotifications.requestPermission();

  // Load per-user notifications + synced settings on sign-in; clear on sign-out.
  Supabase.instance.client.auth.onAuthStateChange.listen((state) async {
    final signedIn = Supabase.instance.client.auth.currentUser != null;
    switch (state.event) {
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.initialSession:
        if (signedIn) {
          await notifications.loadFromRepo();
          try {
            await notificationPrefs
                .mergeFromServer(await SupabaseService().loadNotificationSettings());
          } catch (_) {/* offline — keep local prefs */}
        }
        break;
      case AuthChangeEvent.signedOut:
        notifications.reset();
        break;
      default:
        break;
    }
  });

  final cameras = await availableCameras();

  // If the app was launched by tapping a notification (terminated state),
  // capture its deep link so we can route once the first frame is up.
  final launchDeepLink = await LocalNotifications.launchDeepLink();

  runApp(MEDSApp(cameras: cameras, launchDeepLink: launchDeepLink));
}

class MEDSApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  final String? launchDeepLink;

  const MEDSApp({super.key, required this.cameras, this.launchDeepLink});

  @override
  Widget build(BuildContext context) {
    if (launchDeepLink != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => handleDeepLink(launchDeepLink));
    }
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) => MaterialApp(
        navigatorKey: navigatorKey,
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
  // Page index: 0 Home · 1 History · 2 Insights · 3 Profile.
  int _index = 0;
  int _sessionsReloadToken = 0;

  Future<void> _startLive() async {
    final ran = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SessionReadinessScreen(
          cameras: widget.cameras,
          onOpenTab: (i) => setState(() => _index = i),
        ),
      ),
    );
    if (ran == true && mounted) {
      setState(() {
        _sessionsReloadToken++;
        _index = 1; // jump to History so the new session is visible
      });
    }
  }

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
          HistoryScreen(
            key: ValueKey(_sessionsReloadToken),
            cameras: widget.cameras,
            onOpenTab: (i) => setState(() => _index = i),
          ),
          InsightsScreen(
            cameras: widget.cameras,
            onOpenTab: (i) => setState(() => _index = i),
          ),
          const ProfileScreen(),
        ],
      ),
      floatingActionButton: SizedBox(
        width: 58,
        height: 58,
        child: FloatingActionButton(
          onPressed: _startLive,
          backgroundColor: medsNavAccent,
          foregroundColor: Colors.white,
          elevation: 3,
          shape: const CircleBorder(),
          tooltip: 'Start a live session',
          child: const Icon(Icons.center_focus_strong, size: 26),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: MedsBottomBar(
        index: _index,
        onSelect: (i) => setState(() => _index = i),
      ),
    );
  }
}
