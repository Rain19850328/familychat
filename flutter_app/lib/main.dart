import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'home_page.dart';

const String _appFontFamily = 'Pretendard Variable';
const List<String> _appFontFallback = <String>[
  'SUIT Variable',
  'Apple SD Gothic Neo',
  'Malgun Gothic',
];

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
        final baseTheme = ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0E7A6B),
            brightness: Brightness.light,
          ),
          fontFamily: _appFontFamily,
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
        );

        return MaterialApp(
          title: '우리 가족 채팅',
          debugShowCheckedModeBanner: false,
          theme: baseTheme.copyWith(
            textTheme: _withAppFontFallback(baseTheme.textTheme),
            primaryTextTheme: _withAppFontFallback(baseTheme.primaryTextTheme),
          ),
          home: FamilyChatHome(appState: appState),
        );
      },
    );
  }
}

TextTheme _withAppFontFallback(TextTheme textTheme) {
  return textTheme.copyWith(
    displayLarge: _withFontFallback(textTheme.displayLarge),
    displayMedium: _withFontFallback(textTheme.displayMedium),
    displaySmall: _withFontFallback(textTheme.displaySmall),
    headlineLarge: _withFontFallback(textTheme.headlineLarge),
    headlineMedium: _withFontFallback(textTheme.headlineMedium),
    headlineSmall: _withFontFallback(textTheme.headlineSmall),
    titleLarge: _withFontFallback(textTheme.titleLarge),
    titleMedium: _withFontFallback(textTheme.titleMedium),
    titleSmall: _withFontFallback(textTheme.titleSmall),
    bodyLarge: _withFontFallback(textTheme.bodyLarge),
    bodyMedium: _withFontFallback(textTheme.bodyMedium),
    bodySmall: _withFontFallback(textTheme.bodySmall),
    labelLarge: _withFontFallback(textTheme.labelLarge),
    labelMedium: _withFontFallback(textTheme.labelMedium),
    labelSmall: _withFontFallback(textTheme.labelSmall),
  );
}

TextStyle? _withFontFallback(TextStyle? style) {
  return style?.copyWith(
    fontFamily: _appFontFamily,
    fontFamilyFallback: _appFontFallback,
  );
}
