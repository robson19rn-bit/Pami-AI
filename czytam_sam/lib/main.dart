import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart' show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import 'app_state.dart';
import 'content/models.dart';
import 'data/database.dart';
import 'services/speech_input.dart';
import 'services/speech_output.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/setup_screen.dart';
import 'ui/theme.dart';

Future<ContentBundle> loadContent(AssetBundle bundle) async {
  Future<Map<String, dynamic>> j(String n) async =>
      jsonDecode(await bundle.loadString('assets/content/$n.json')) as Map<String, dynamic>;
  return ContentBundle.fromJsonMaps(
    letters: await j('letters'),
    syllables: await j('syllables'),
    words: await j('words'),
    sentences: await j('sentences'),
    readings: await j('readings'),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final content = await loadContent(rootBundle);
  final path = p.join(await sqflite.getDatabasesPath(), 'czytam_sam.db');
  final db = await ProgressDb.open(sqflite.databaseFactory, path);
  final state = AppState(content: content, db: db, tts: FlutterTtsOutput(), asr: VoskSpeechInput());
  await state.load();
  await state.tts.setRate(state.ttsRate);
  runApp(CzytamSamApp(state: state));
}

class CzytamSamApp extends StatelessWidget {
  const CzytamSamApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Czytam Sam',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: const Locale('pl', 'PL'),
        supportedLocales: const [Locale('pl', 'PL')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: state.setupDone ? const HomeScreen() : const SetupScreen(),
      ),
    );
  }
}
