import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  SupabaseClient get _client => Supabase.instance.client;

  // 1. Đăng ký tài khoản mới bằng Email & Mật khẩu (Chờ xác thực OTP)
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signUp(
      email: email,
      password: password,
    );
  }

  // 1b. Xác thực mã OTP đăng ký và tiến hành lưu thông tin profile
  Future<AuthResponse> verifySignUpOtp({
    required String email,
    required String token,
    required String fullName,
  }) async {
    final response = await _client.auth.verifyOTP(
      email: email,
      token: token,
      type: OtpType.signup,
    );

    // Sau khi xác thực OTP thành công, người dùng đã đăng nhập, tiến hành lưu profile vào bảng profiles
    if (response.user != null) {
      await _client.from('profiles').insert({
        'id': response.user!.id,
        'email': email,
        'full_name': fullName,
      });
    }

    return response;
  }

  // Tạo profile trực tiếp (dùng khi xác thực email bị tắt trên Supabase)
  Future<void> createProfile({
    required String userId,
    required String email,
    required String fullName,
  }) async {
    await _client.from('profiles').insert({
      'id': userId,
      'email': email,
      'full_name': fullName,
    });
  }

  // 1c. Gửi lại mã OTP xác nhận đăng ký
  Future<ResendResponse> resendSignUpOtp({required String email}) async {
    return await _client.auth.resend(
      type: OtpType.signup,
      email: email,
    );
  }

  // 1d. Gửi mã OTP khôi phục mật khẩu qua Email
  Future<void> sendPasswordResetOtp({required String email}) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  // 1e. Xác thực mã OTP khôi phục mật khẩu và đặt lại mật khẩu mới
  Future<UserResponse> resetPasswordWithOtp({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    // Xác thực mã OTP khôi phục (thiết lập phiên làm việc tạm thời cho user này)
    await _client.auth.verifyOTP(
      email: email,
      token: token,
      type: OtpType.recovery,
    );

    // Tiến hành cập nhật mật khẩu mới cho user
    return await _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  // 2. Đăng nhập bằng Email & Mật khẩu
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // 3. Đăng xuất
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // 4. Lấy thông tin người dùng hiện tại đang đăng nhập (nếu có)
  User? get currentUser => _client.auth.currentUser;

  // 5. Kiểm tra xem người dùng đã đăng nhập hay chưa
  bool get isAuthenticated => _client.auth.currentSession != null;

  // 6. Lấy profile chi tiết của người dùng hiện tại
  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      return data;
    } catch (e) {
      return null;
    }
  }

  // 7. Cập nhật thông số profile (chiều cao, cân nặng, độ tuổi)
  Future<void> updateUserProfile({
    required String fullName,
    required double weight,
    required double height,
    int? age,
  }) async {
    final user = currentUser;
    if (user == null) return;

    final Map<String, dynamic> updateData = {
      'full_name': fullName,
      'weight': weight,
      'height': height,
    };

    if (age != null) {
      updateData['age'] = age;
    }

    try {
      await _client.from('profiles').update(updateData).eq('id', user.id);
    } catch (e) {
      // Nếu cột 'age' chưa tồn tại trong Supabase, loại bỏ và cập nhật lại để tránh lỗi crash
      debugPrint('Lỗi cập nhật thông số profile (có thể do thiếu cột age): $e');
      if (age != null) {
        updateData.remove('age');
        await _client.from('profiles').update(updateData).eq('id', user.id);
      } else {
        rethrow;
      }
    }
  }
}
