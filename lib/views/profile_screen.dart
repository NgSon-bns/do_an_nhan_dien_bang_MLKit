import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../core/theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import 'auth/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const ProfileScreen({super.key, required this.cameras});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _ageController = TextEditingController();

  final AuthService _authService = AuthService();
  final DatabaseService _databaseService = DatabaseService();
  bool _isLoading = true;
  bool _isSaving = false;
  String _email = '';
  String? _message;
  bool _isSuccessMessage = true;

  // Lịch sử tập luyện
  List<Map<String, dynamic>> _recentWorkouts = [];
  bool _isLoadingWorkouts = true;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
    _loadRecentWorkouts();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    try {
      final user = _authService.currentUser;
      if (user != null) {
        setState(() {
          _email = user.email ?? '';
        });
      }

      final profile = await _authService.getCurrentUserProfile();
      if (profile != null) {
        setState(() {
          _nameController.text = profile['full_name'] ?? '';
          _weightController.text = (profile['weight'] ?? 0.0).toString();
          _heightController.text = (profile['height'] ?? 0.0).toString();
          _ageController.text = (profile['age'] ?? 0).toString();
        });
      }
    } catch (e) {
      debugPrint('Lỗi tải thông tin profile: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadRecentWorkouts() async {
    setState(() {
      _isLoadingWorkouts = true;
    });
    try {
      final list = await _databaseService.getRecentWorkouts(limit: 8);
      if (mounted) {
        setState(() {
          _recentWorkouts = list;
          _isLoadingWorkouts = false;
        });
      }
    } catch (e) {
      debugPrint('Lỗi tải lịch sử luyện tập: $e');
      if (mounted) {
        setState(() {
          _isLoadingWorkouts = false;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      final double weight = double.tryParse(_weightController.text) ?? 0.0;
      final double height = double.tryParse(_heightController.text) ?? 0.0;
      final int age = int.tryParse(_ageController.text) ?? 0;

      await _authService.updateUserProfile(
        fullName: _nameController.text.trim(),
        weight: weight,
        height: height,
        age: age,
      );

      setState(() {
        _message = 'Cập nhật thông tin thành công!';
        _isSuccessMessage = true;
      });
    } catch (e) {
      setState(() {
        _message = 'Lỗi cập nhật thông tin. Vui lòng thử lại!';
        _isSuccessMessage = false;
      });
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    // Hiển thị dialog xác nhận đăng xuất
    bool confirm = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppTheme.cardBackground,
            title: const Text('Đăng Xuất'),
            content: const Text('Bạn có chắc chắn muốn đăng xuất khỏi tài khoản không?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Đăng xuất', style: TextStyle(color: AppTheme.errorRed)),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    await _authService.signOut();

    if (!mounted) return;

    // Chuyển hướng về màn hình đăng nhập và xóa toàn bộ stack navigation
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => LoginScreen(cameras: widget.cameras),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trang Cá Nhân', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.neonGreen))
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Avatar & Email hiển thị tĩnh
                    Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 46,
                            backgroundColor: AppTheme.neonGreen.withValues(alpha: 0.15),
                            child: const Icon(Icons.person, size: 54, color: AppTheme.neonGreen),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _email,
                            style: const TextStyle(
                              fontSize: 15,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Thông điệp trạng thái lưu profile
                    if (_message != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isSuccessMessage
                              ? AppTheme.neonGreen.withValues(alpha: 0.12)
                              : AppTheme.errorRed.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _isSuccessMessage
                                ? AppTheme.neonGreen.withValues(alpha: 0.3)
                                : AppTheme.errorRed.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          _message!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _isSuccessMessage ? AppTheme.neonGreen : AppTheme.errorRed,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Ô chỉnh sửa Họ tên
                    TextFormField(
                      controller: _nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Họ và tên',
                        labelStyle: const TextStyle(color: AppTheme.textSecondary),
                        prefixIcon: const Icon(Icons.person_outline, color: AppTheme.textSecondary),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppTheme.neonGreen, width: 1.5),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Họ tên không được để trống';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Cân nặng & Chiều cao hàng ngang
                    Row(
                      children: [
                        // Cân nặng
                        Expanded(
                          child: TextFormField(
                            controller: _weightController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Cân nặng (kg)',
                              labelStyle: const TextStyle(color: AppTheme.textSecondary),
                              prefixIcon: const Icon(Icons.monitor_weight_outlined, color: AppTheme.textSecondary),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: Colors.white12),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppTheme.neonGreen, width: 1.5),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Bắt buộc';
                              if (double.tryParse(value) == null) return 'Sai định dạng';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Chiều cao
                        Expanded(
                          child: TextFormField(
                            controller: _heightController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Chiều cao (cm)',
                              labelStyle: const TextStyle(color: AppTheme.textSecondary),
                              prefixIcon: const Icon(Icons.height_outlined, color: AppTheme.textSecondary),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: Colors.white12),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppTheme.neonGreen, width: 1.5),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Bắt buộc';
                              if (double.tryParse(value) == null) return 'Sai định dạng';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Ô nhập Độ tuổi
                    TextFormField(
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Tuổi',
                        labelStyle: const TextStyle(color: AppTheme.textSecondary),
                        prefixIcon: const Icon(Icons.cake_outlined, color: AppTheme.textSecondary),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppTheme.neonGreen, width: 1.5),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Bắt buộc';
                        final val = int.tryParse(value);
                        if (val == null || val <= 5 || val > 120) {
                          return 'Tuổi không hợp lệ (5 - 120)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 36),

                    // Nút Lưu thông tin
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveProfile,
                      icon: _isSaving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.0),
                            )
                          : const Icon(Icons.save_outlined, color: Colors.black),
                      label: const Text(
                        'LƯU THAY ĐỔI',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.neonGreen,
                        disabledBackgroundColor: AppTheme.neonGreen.withValues(alpha: 0.4),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // Tiêu đề lịch sử tập luyện
                    const Row(
                      children: [
                        Icon(Icons.history, color: AppTheme.neonGreen, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'LỊCH SỬ HOẠT ĐỘNG GẦN ĐÂY',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    _isLoadingWorkouts
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: CircularProgressIndicator(color: AppTheme.neonGreen),
                            ),
                          )
                        : _recentWorkouts.isEmpty
                            ? Container(
                                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                                decoration: AppTheme.glassDecoration(
                                  color: Colors.white.withValues(alpha: 0.02),
                                  borderRadius: 16,
                                ),
                                child: const Center(
                                  child: Text(
                                    'Chưa có lịch sử hoạt động.\nHãy bắt đầu tập luyện để tích lũy kết quả!',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
                                  ),
                                ),
                              )
                            : Column(
                                children: _recentWorkouts.map((row) {
                                  final String exerciseId = row['exercise_id'] as String? ?? '';
                                  final parts = exerciseId.split('::');
                                  final String type = parts.isNotEmpty ? parts[0] : '';
                                  
                                  // Dịch tên bài tập
                                  String displayName = 'Hoạt động thể chất';
                                  IconData displayIcon = Icons.fitness_center;
                                  Color iconColor = AppTheme.neonGreen;

                                  if (type == 'check_in') {
                                    displayName = 'Điểm danh hàng ngày';
                                    displayIcon = Icons.today;
                                    iconColor = Colors.orangeAccent;
                                  } else if (type == 'push_up') {
                                    displayName = 'Chống đẩy (Push-up)';
                                    displayIcon = Icons.fitness_center;
                                  } else if (type == 'squat') {
                                    displayName = 'Gánh đùi (Squat)';
                                    displayIcon = Icons.accessibility_new;
                                  } else if (type == 'plank') {
                                    displayName = 'Tấm ván (Plank)';
                                    displayIcon = Icons.timer;
                                    iconColor = AppTheme.neonBlue;
                                  } else if (type == 'burpee') {
                                    displayName = 'Burpee liên hoàn';
                                    displayIcon = Icons.directions_run;
                                  } else if (type == 'walking_lunge') {
                                    displayName = 'Bước gập gối (Lunge)';
                                    displayIcon = Icons.directions_walk;
                                  } else if (type == 'jumping_jack') {
                                    displayName = 'Nhảy vung tay (Jumping Jack)';
                                    displayIcon = Icons.fitness_center;
                                  }

                                  // Định dạng thời gian
                                  String dateText = '';
                                  try {
                                    final String? createdAt = row['created_at'] as String?;
                                    if (createdAt != null) {
                                      final dt = DateTime.parse(createdAt).toLocal();
                                      final day = dt.day.toString().padLeft(2, '0');
                                      final month = dt.month.toString().padLeft(2, '0');
                                      final year = dt.year;
                                      final hour = dt.hour.toString().padLeft(2, '0');
                                      final minute = dt.minute.toString().padLeft(2, '0');
                                      dateText = '$day/$month/$year lúc $hour:$minute';
                                    }
                                  } catch (_) {
                                    dateText = (row['created_at'] as String?)?.substring(0, 10) ?? '';
                                  }

                                  final int reps = row['reps_count'] as int? ?? 0;
                                  final int secs = row['duration_seconds'] as int? ?? 0;
                                  final double kcal = (row['calories_burned'] as num?)?.toDouble() ?? 0.0;
                                  final int incorrect = row['incorrect_postures'] as int? ?? 0;

                                  final bool isCheckIn = type == 'check_in';
                                  
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(14),
                                    decoration: AppTheme.glassDecoration(
                                      color: AppTheme.cardBackground.withValues(alpha: 0.3),
                                      borderRadius: 16,
                                    ).copyWith(
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.04),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: iconColor.withValues(alpha: 0.12),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(displayIcon, color: iconColor, size: 20),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                displayName,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13.5,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                isCheckIn
                                                    ? 'Nhận +10 XP • $dateText'
                                                    : '$reps reps • $secs giây • ${kcal.toStringAsFixed(1)} kcal',
                                                style: TextStyle(
                                                  color: Colors.white.withValues(alpha: 0.5),
                                                  fontSize: 11,
                                                ),
                                              ),
                                              if (!isCheckIn) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  dateText,
                                                  style: TextStyle(
                                                    color: Colors.white.withValues(alpha: 0.3),
                                                    fontSize: 9.5,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        if (!isCheckIn) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: incorrect > 0
                                                  ? AppTheme.errorRed.withValues(alpha: 0.1)
                                                  : AppTheme.neonGreen.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              incorrect > 0 ? 'Lỗi: $incorrect ⚠️' : 'Đạt chuẩn ✅',
                                              style: TextStyle(
                                                color: incorrect > 0 ? AppTheme.errorRed : AppTheme.neonGreen,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                    const SizedBox(height: 32),

                    // Nút Đăng xuất
                    OutlinedButton.icon(
                      onPressed: _handleLogout,
                      icon: const Icon(Icons.logout, color: AppTheme.errorRed, size: 18),
                      label: const Text(
                        'ĐĂNG XUẤT TÀI KHOẢN',
                        style: TextStyle(color: AppTheme.errorRed, fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppTheme.errorRed, width: 1.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
