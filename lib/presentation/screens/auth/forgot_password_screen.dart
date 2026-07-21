import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:demo/core/theme/app_theme.dart';
import 'package:demo/data/services/auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const ForgotPasswordScreen({super.key, required this.cameras});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  String? _errorMessage;

  bool _isOtpSent = false;
  Timer? _resendTimer;
  int _resendCountdown = 60;
  bool _canResend = false;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() {
      _resendCountdown = 60;
      _canResend = false;
    });
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_resendCountdown == 0) {
        setState(() {
          _canResend = true;
          _resendTimer?.cancel();
        });
      } else {
        setState(() {
          _resendCountdown--;
        });
      }
    });
  }

  Future<void> _handleSendResetOtp() async {
    if (!_emailFormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.sendPasswordResetOtp(
        email: _emailController.text.trim(),
      );

      if (!mounted) return;

      setState(() {
        _isOtpSent = true;
        _errorMessage = null;
      });
      _startResendTimer();
    } catch (e) {
      String msg = e.toString();
      if (e is AuthException) {
        msg = e.message;
      }
      setState(() {
        _errorMessage = 'Gửi mã khôi phục thất bại: $msg';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleResetPassword() async {
    if (!_resetFormKey.currentState!.validate()) return;

    final otpCode = _otpController.text.trim();
    if (otpCode.isEmpty) {
      setState(() {
        _errorMessage = 'Vui lòng nhập mã OTP khôi phục';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.resetPasswordWithOtp(
        email: _emailController.text.trim(),
        token: otpCode,
        newPassword: _newPasswordController.text.trim(),
      );

      if (!mounted) return;

      _resendTimer?.cancel();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Đặt lại mật khẩu thành công. Vui lòng đăng nhập lại.',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppTheme.neonGreen,
        ),
      );

      // Quay lại màn hình Login
      Navigator.pop(context);
    } catch (e) {
      String msg = e.toString();
      if (e is AuthException) {
        msg = e.message;
      }
      setState(() {
        _errorMessage = 'Đặt lại mật khẩu thất bại: $msg';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleResendOtp() async {
    if (!_canResend) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.sendPasswordResetOtp(
        email: _emailController.text.trim(),
      );

      if (!mounted) return;

      setState(() {
        _errorMessage = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mã OTP khôi phục mới đã được gửi lại vào email của bạn.',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppTheme.neonGreen,
        ),
      );

      _startResendTimer();
    } catch (e) {
      String msg = e.toString();
      if (e is AuthException) {
        msg = e.message;
      }
      setState(() {
        _errorMessage = 'Gửi lại mã OTP thất bại: $msg';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildEmailInputView() {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Quên Mật Khẩu?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Nhập địa chỉ Email đăng ký của bạn để nhận mã khôi phục OTP.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 32),

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.errorRed.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.errorRed.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppTheme.errorRed, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Địa chỉ Email',
              labelStyle: const TextStyle(color: AppTheme.textSecondary),
              prefixIcon: const Icon(Icons.email_outlined, color: AppTheme.textSecondary),
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
                return 'Vui lòng nhập email';
              }
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
                return 'Định dạng email không hợp lệ';
              }
              return null;
            },
          ),
          const SizedBox(height: 32),

          ElevatedButton(
            onPressed: _isLoading ? null : _handleSendResetOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neonGreen,
              disabledBackgroundColor: AppTheme.neonGreen.withValues(alpha: 0.4),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 4,
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
                  )
                : const Text(
                    'GỬI MÃ KHÔI PHỤC',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpAndPasswordView() {
    return Form(
      key: _resetFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Khôi Phục Mật Khẩu',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Mã OTP khôi phục đã được gửi đến email:\n${_emailController.text.trim()}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 32),

          // Hộp thông báo gửi mã thành công (màu xanh)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.neonGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.neonGreen.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: AppTheme.neonGreen, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Đã gửi mã OTP khôi phục mật khẩu đến email ${_emailController.text.trim()}.',
                    style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.errorRed.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.errorRed.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppTheme.errorRed, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Nhập OTP
          TextFormField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 6,
            ),
            maxLength: 10,
            decoration: InputDecoration(
              counterText: '',
              labelText: 'Nhập mã OTP khôi phục',
              labelStyle: const TextStyle(color: AppTheme.textSecondary, letterSpacing: 0),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.neonGreen, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Mật khẩu mới
          TextFormField(
            controller: _newPasswordController,
            obscureText: !_isPasswordVisible,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Mật khẩu mới',
              labelStyle: const TextStyle(color: AppTheme.textSecondary),
              prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.textSecondary),
              suffixIcon: IconButton(
                icon: Icon(
                  _isPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: AppTheme.textSecondary,
                ),
                onPressed: () {
                  setState(() {
                    _isPasswordVisible = !_isPasswordVisible;
                  });
                },
              ),
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
              if (value == null || value.isEmpty) {
                return 'Vui lòng nhập mật khẩu mới';
              }
              if (value.length < 6) {
                return 'Mật khẩu phải tối thiểu 6 ký tự';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          // Xác nhận mật khẩu mới
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Xác nhận mật khẩu mới',
              labelStyle: const TextStyle(color: AppTheme.textSecondary),
              prefixIcon: const Icon(Icons.lock_clock_outlined, color: AppTheme.textSecondary),
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
              if (value == null || value.isEmpty) {
                return 'Vui lòng xác nhận mật khẩu mới';
              }
              if (value != _newPasswordController.text) {
                return 'Mật khẩu nhập lại không trùng khớp';
              }
              return null;
            },
          ),
          const SizedBox(height: 32),

          ElevatedButton(
            onPressed: _isLoading ? null : _handleResetPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neonGreen,
              disabledBackgroundColor: AppTheme.neonGreen.withValues(alpha: 0.4),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 4,
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
                  )
                : const Text(
                    'CẬP NHẬT MẬT KHẨU',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
          ),
          const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Chưa nhận được mã? ',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
              ),
              TextButton(
                onPressed: _canResend && !_isLoading ? _handleResendOtp : null,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _canResend ? 'Gửi lại' : 'Gửi lại sau ${_resendCountdown}s',
                  style: TextStyle(
                    color: _canResend ? AppTheme.neonGreen : AppTheme.textSecondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Center(
            child: TextButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      setState(() {
                        _isOtpSent = false;
                        _errorMessage = null;
                      });
                      _resendTimer?.cancel();
                    },
              child: const Text(
                'Quay lại nhập Email',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (_isOtpSent) {
              setState(() {
                _isOtpSent = false;
                _errorMessage = null;
              });
              _resendTimer?.cancel();
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: _isOtpSent ? _buildOtpAndPasswordView() : _buildEmailInputView(),
          ),
        ),
      ),
    );
  }
}
