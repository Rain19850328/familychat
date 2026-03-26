import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'home_page.dart';
import 'ui/design_tokens.dart';

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
  const FamilyChatApp({super.key, required this.appState});

  final FamilyChatAppState appState;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        return MaterialApp(
          title: '우리 가족 채팅',
          debugShowCheckedModeBanner: false,
          theme: buildFamilyTheme(
            textTheme: ThemeData.light(useMaterial3: true).textTheme,
            fontFamily: _appFontFamily,
            fontFallback: _appFontFallback,
          ),
          home: FamilyChatHome(appState: appState),
        );
      },
    );
  }
}
