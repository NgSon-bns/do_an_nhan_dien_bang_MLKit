import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  SupabaseClient get _client => Supabase.instance.client;

  
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signUp(
      email: email,
      password: password,
    );
  }

  
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

    
    if (response.user != null) {
      await _client.from('ho_so_nguoi_dung').insert({
        'ma_nguoi_dung': response.user!.id,
        'email': email,
        'ho_ten': fullName,
      });
    }

    return response;
  }

  
  Future<void> createProfile({
    required String userId,
    required String email,
    required String fullName,
  }) async {
    await _client.from('ho_so_nguoi_dung').insert({
      'ma_nguoi_dung': userId,
      'email': email,
      'ho_ten': fullName,
    });
  }

  
  Future<ResendResponse> resendSignUpOtp({required String email}) async {
    return await _client.auth.resend(
      type: OtpType.signup,
      email: email,
    );
  }

  
  Future<void> sendPasswordResetOtp({required String email}) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  
  Future<UserResponse> resetPasswordWithOtp({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    await _client.auth.verifyOTP(
      email: email,
      token: token,
      type: OtpType.recovery,
    );

    return await _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  
  User? get currentUser => _client.auth.currentUser;

  
  bool get isAuthenticated => _client.auth.currentSession != null;

  
  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final data = await _client
          .from('ho_so_nguoi_dung')
          .select('ma_nguoi_dung, email, ho_ten, can_nang, chieu_cao, tuoi, gioi_tinh, muc_tieu')
          .eq('ma_nguoi_dung', user.id)
          .maybeSingle();
      return data;
    } catch (e) {
      return null;
    }
  }

  
  Future<void> updateUserProfile({
    required String fullName,
    required double weight,
    required double height,
    int? age,
    String? gender,
  }) async {
    final user = currentUser;
    if (user == null) return;

    final Map<String, dynamic> updateData = {
      'ho_ten': fullName,
      'can_nang': weight,
      'chieu_cao': height,
    };

    if (age != null) {
      updateData['tuoi'] = age;
    }
    if (gender != null) {
      updateData['gioi_tinh'] = gender;
    }

    try {
      await _client.from('ho_so_nguoi_dung').update(updateData).eq('ma_nguoi_dung', user.id);
    } catch (e) {
      debugPrint('Lỗi cập nhật thông số profile: $e');
      if (age != null || gender != null) {
        updateData.remove('tuoi');
        updateData.remove('gioi_tinh');
        await _client.from('ho_so_nguoi_dung').update(updateData).eq('ma_nguoi_dung', user.id);
      } else {
        rethrow;
      }
    }
  }
}
