import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local display preference; never changes account or clinical data.
class ThemeController {
  static final mode = ValueNotifier<ThemeMode>(ThemeMode.system);
  static Future<void> initialize() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(
        'appearance_mode',
      );
      mode.value = ThemeMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => ThemeMode.system,
      );
    } catch (_) {
      /* Device settings remain the fallback. */
    }
  }

  static Future<void> setMode(ThemeMode value) async {
    mode.value = value;
    try {
      await (await SharedPreferences.getInstance()).setString(
        'appearance_mode',
        value.name,
      );
    } catch (_) {
      /* The selected theme still applies for this session. */
    }
  }
}

class ThemeModeButton extends StatelessWidget {
  const ThemeModeButton({super.key});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: isDark ? 'Switch to light theme' : 'Switch to dark theme',
      icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      onPressed: () =>
          ThemeController.setMode(isDark ? ThemeMode.light : ThemeMode.dark),
    );
  }
}
