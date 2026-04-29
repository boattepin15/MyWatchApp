import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/scan_screen.dart';
import 'services/seizure_detection_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize seizure detection notifications
  await SeizureDetectionService().initialize();

  runApp(const MyWatchApp());
}

class MyWatchApp extends StatelessWidget {
  const MyWatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Epilepsy Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF6C63FF),
          secondary: const Color(0xFF3F8CFF),
          surface: const Color(0xFF1B2838),
        ),
        scaffoldBackgroundColor: const Color(0xFF0D1B2A),
        textTheme: GoogleFonts.outfitTextTheme(
          ThemeData.dark().textTheme,
        ),
      ),
      home: const ScanScreen(),
    );
  }
}
