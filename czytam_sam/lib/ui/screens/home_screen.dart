import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'guardian_panel.dart';
import 'lesson_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 24),
                Text('Czytam Sam', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge!.copyWith(fontSize: 40)),
                const SizedBox(height: 8),
                Text(s.childName == null ? 'Dzień dobry!' : 'Dzień dobry, ${s.childName}!',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 22)),
                const SizedBox(height: 32),
                BigButton(
                  label: 'Uczę się',
                  icon: Icons.menu_book_rounded,
                  onPressed: () => startLesson(context),
                ),
                BigButton(
                  label: 'Moje postępy',
                  subtitle: 'panel opiekuna',
                  icon: Icons.insights_rounded,
                  onPressed: () async {
                    if (await adultGate(context) && context.mounted) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const GuardianPanel()));
                    }
                  },
                ),
                BigButton(
                  label: 'Ustawienia',
                  subtitle: 'dla dorosłych',
                  icon: Icons.settings_rounded,
                  onPressed: () async {
                    if (await adultGate(context) && context.mounted) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                    }
                  },
                ),
                const SizedBox(height: 24),
                const Text('Bez reklam, bez kont, bez internetu.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Palette.border)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
