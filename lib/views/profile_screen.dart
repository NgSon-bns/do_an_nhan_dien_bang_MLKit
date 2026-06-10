import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../core/theme/app_theme.dart';
import '../services/auth_service.dart';
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

  final AuthService _authService = AuthService();
  bool _isLoading = true;
  bool _isSaving = false;
  String _email = '';
  String? _message;
  bool _isSuccessMessage = true;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    _heightController.dispose();
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

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      final double weight = double.tryParse(_weightController.text) ?? 0.0;
      final double height = double.tryParse(_heightController.text) ?? 0.0;

      await _authService.updateUserProfile(
        fullName: _nameController.text.trim(),
        weight: weight,
        height: height,
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
                    const SizedBox(height: 20),

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
