import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: kSupabaseUrl,
    anonKey: kSupabaseAnonKey,
    debug: false,
  );

  final prefs = await SharedPreferences.getInstance();
  final appState = FamilyChatAppState(prefs);
  await appState.bootstrap();

  runApp(FamilyChatApp(appState: appState));
}

class FamilyChatApp extends StatelessWidget {
  const FamilyChatApp({
    super.key,
    required this.appState,
  });

  final FamilyChatAppState appState;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        return MaterialApp(
          title: '우리 가족 채팅',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0E7A6B),
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: const Color(0xFFF7F3EA),
            useMaterial3: true,
            snackBarTheme: const SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
            ),
            cardTheme: const CardThemeData(
              elevation: 0,
              color: Colors.white,
              margin: EdgeInsets.zero,
            ),
          ),
          home: FamilyChatHome(appState: appState),
        );
      },
    );
  }
}
