import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:photobooth_app/providers/photo_provider.dart';
import 'package:photobooth_app/screens/splash_screen.dart';
import 'package:photobooth_app/services/api_service.dart'; // Import ini sudah benar

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 1. Provider untuk State Foto
        ChangeNotifierProvider(create: (_) => PhotoProvider()),

        // 2. Provider untuk API Service (INI YANG TADI KURANG)
        Provider(create: (_) => ApiService()),
      ],
      child: MaterialApp(
        title: 'Photobooth App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
          fontFamily: 'Poppins',
        ),
        home: const SplashScreen(),
      ),
    );
  }
}