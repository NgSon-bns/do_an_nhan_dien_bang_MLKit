import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:demo/core/theme/app_theme.dart';
import 'package:demo/data/services/auth_service.dart';
import 'package:demo/presentation/screens/auth/login_screen.dart';
import 'package:demo/presentation/screens/exercise_list_screen.dart';

void main() async {
  
  WidgetsFlutterBinding.ensureInitialized();

  
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  
  bool isSupabaseInitialized = false;

  const String supabaseUrl = 'https://cldjakuqxojmtethpbyg.supabase.co';
  const String supabaseAnonKey =
      'sb_publishable_SKRxupuxLeGaOO7FuvZY6g_OZ_poy5t';

  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey, 
    );
    isSupabaseInitialized = true;
  } catch (e) {
    debugPrint('Lỗi khởi tạo Supabase: $e');
  }

  
  List<CameraDescription> cameras = [];
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Lỗi không lấy được danh sách camera: $e');
  }

  runApp(MyApp(cameras: cameras, isSupabaseInitialized: isSupabaseInitialized));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  final bool isSupabaseInitialized;

  const MyApp({
    super.key,
    required this.cameras,
    required this.isSupabaseInitialized,
  });

  @override
  Widget build(BuildContext context) {
    final bool showDashboardDirectly =
        isSupabaseInitialized && AuthService().isAuthenticated;

    return MaterialApp(
      title: 'AuraFit AI',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: showDashboardDirectly
          ? ExerciseListScreen(cameras: cameras)
          : LoginScreen(cameras: cameras),
    );
  }
}