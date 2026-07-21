import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import để dùng SystemChrome
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:demo/core/theme/app_theme.dart';
import 'package:demo/data/services/auth_service.dart';
import 'package:demo/presentation/screens/auth/login_screen.dart';
import 'package:demo/presentation/screens/exercise_list_screen.dart';

void main() async {
  // 1. Đảm bảo các dịch vụ hệ thống của Flutter được khởi tạo trước
  WidgetsFlutterBinding.ensureInitialized();

  // 2. KHÓA MÀN HÌNH CHỈ CHO PHÉP CHIỀU DỌC (PORTRAIT)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Khởi tạo Supabase
  bool isSupabaseInitialized = false;

  const String supabaseUrl = 'https://cldjakuqxojmtethpbyg.supabase.co';
  const String supabaseAnonKey =
      'sb_publishable_SKRxupuxLeGaOO7FuvZY6g_OZ_poy5t';

  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey, // Đã đổi publishableKey -> anonKey theo chuẩn Supabase Flutter
    );
    isSupabaseInitialized = true;
  } catch (e) {
    debugPrint('Lỗi khởi tạo Supabase: $e');
  }

  // Lấy danh sách camera có sẵn trên thiết bị di động
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