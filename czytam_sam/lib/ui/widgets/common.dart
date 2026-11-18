import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Duży przycisk menu.
class BigButton extends StatelessWidget {
  const BigButton({super.key, required this.label, required this.icon, required this.onPressed, this.subtitle});
  final String label;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(88), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
        child: Row(
          children: [
            Icon(icon, size: 40),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                  if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.child, this.color = Palette.soft});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
        color: color,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      );
}

/// Prosta bramka dla dorosłych: działanie mnożenia wpisane z klawiatury.
Future<bool> adultGate(BuildContext context) async {
  final r = Random();
  final a = 6 + r.nextInt(4), b = 3 + r.nextInt(7);
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Tylko dla dorosłych'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ile to $a × $b?', style: const TextStyle(fontSize: 22)),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 22),
            decoration: const InputDecoration(hintText: 'wynik'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
        FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim()) == a * b), child: const Text('Dalej')),
      ],
    ),
  );
  if (ok != true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Niepoprawny wynik.')));
  }
  return ok == true;
}

Future<bool> confirm(BuildContext context, String title, String body, {String yes = 'Tak', String no = 'Nie'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(no)),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
      ],
    ),
  );
  return r == true;
}
