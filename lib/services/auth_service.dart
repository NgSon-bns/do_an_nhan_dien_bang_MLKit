import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  SupabaseClient get _client => Supabase.instance.client;

  // 1. Đăng ký tài khoản mới bằng Email & Mật khẩu
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );

    // Sau khi đăng ký thành công, lưu thông tin email và họ tên vào bảng profiles công khai
    if (response.user != null) {
      await _client.from('profiles').insert({
        'id': response.user!.id,
        'email': email,
        'full_name': fullName,
      });
    }

    return response;
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

  // 7. Cập nhật thông số profile (chiều cao, cân nặng)
  Future<void> updateUserProfile({
    required String fullName,
    required double weight,
    required double height,
  }) async {
    final user = currentUser;
    if (user == null) return;

    await _client.from('profiles').update({
      'full_name': fullName,
      'weight': weight,
      'height': height,
    }).eq('id', user.id);
  }
}
