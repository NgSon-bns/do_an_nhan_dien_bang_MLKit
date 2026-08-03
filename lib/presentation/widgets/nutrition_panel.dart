import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:demo/core/theme/app_theme.dart';
import 'package:demo/domain/recommended_meal.dart';
import 'package:demo/data/services/nutrition_service.dart';
import 'package:demo/data/services/auth_service.dart';
import 'package:demo/domain/allergens_dataset.dart';
class NutritionPanel extends StatefulWidget {
  final double weight;
  final double height;
  final int age;
  final String selectedGoal;
  final double bmi;
  final DateTime selectedDayDate;
  final List<Map<String, dynamic>> todayMealLogs;
  final String gender;
  final Function(List<Map<String, dynamic>> updatedLogs) onMealLogsUpdated;

  const NutritionPanel({
    super.key,
    required this.weight,
    required this.height,
    required this.age,
    required this.selectedGoal,
    required this.bmi,
    required this.selectedDayDate,
    required this.todayMealLogs,
    required this.gender,
    required this.onMealLogsUpdated,
  });

  @override
  State<NutritionPanel> createState() => _NutritionPanelState();
}

class _NutritionPanelState extends State<NutritionPanel> {
  bool _isMealPlanExpanded = false;
  final AuthService _authService = AuthService();
  
  

  // Biến lưu trữ calo mục tiêu ở cấp State để đồng bộ dữ liệu an toàn
  double _targetCal = 2000.0;

  // Lưu trữ danh sách món ăn đang hiển thị hiện tại cho ngày hôm nay
  List<RecommendedMeal> _currentDayMeals = [];

  // Lưu trữ chỉ số (index) xoay vòng đổi món của từng buổi
  final Map<String, int> _mealSwapIndexes = {};

  // --- BỘ LỌC DỊ ỨNG ĐƯỢC ĐỒNG BỘ VỚI SUPABASE ---
  List<String> _excludedIngredients = [];
  bool _isLoadingAllergens = true;

  // --- BỘ LỌC NGUYÊN LIỆU ĐỘNG TRÊN GIAO DIỆN ---
 
  String _activeIngredientQuery = "";
  bool _isExcludeMode =
      true; // true: Lọc bỏ món chứa từ khóa | false: Chỉ hiện món chứa từ khóa

  // Controller để thêm nguyên liệu dị ứng lên Supabase
  late  TextEditingController _allergyInputController;
  late  TextEditingController _ingredientFilterController;
  @override
  void initState() {
    super.initState();
    // Bước 1: Khởi tạo danh sách món ăn mặc định ngay lập tức để tránh danh sách bị rỗng gây crash khi build lần đầu
    _calculateTargetCal();
    _generateDefaultMeals();
    // Bước 2: Bắt đầu tải dữ liệu bộ lọc dị ứng từ Supabase dưới nền
    _loadExcludedIngredientsFromSupabase();
    _allergyInputController = TextEditingController();
    _ingredientFilterController =
      TextEditingController();
  }

  @override
  void dispose() {
    _ingredientFilterController.dispose();
    _allergyInputController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NutritionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDayDate != widget.selectedDayDate ||
        oldWidget.bmi != widget.bmi ||
        oldWidget.weight != widget.weight ||
        oldWidget.height != widget.height ||
        oldWidget.age != widget.age) {
      // Cập nhật trực tiếp — KHÔNG gọi setState bởi vì Flutter đã tự gọi build() sau didUpdateWidget.
      // Gọi setState trong didUpdateWidget làm framework assert '_elements.contains(element)' fail.
      _calculateTargetCal();
      final int dayOfWeek = (widget.selectedDayDate.weekday - 1).clamp(0, 6);
      final List<RecommendedMeal> originalMeals = NutritionService.getRecommendedMeals(
        widget.bmi,
        dayOfWeek,
        _targetCal,
      );
      _currentDayMeals = originalMeals.map((meal) {
        if (_isAllergic(meal)) return _getAlternativeMeal(meal.key, _targetCal) ?? meal;
        return meal;
      }).toList();
    }
  }

  // Tính toán lượng calo mục tiêu dựa trên thể trạng hiện tại
  void _calculateTargetCal() {
    if (widget.weight <= 0 || widget.height <= 0 || widget.age <= 0) return;

    double bmr = 0.0;
    if (widget.gender.toLowerCase() == 'female') {
      bmr = (10 * widget.weight) + (6.25 * widget.height) - (5 * widget.age) - 161;
    } else {
      bmr = (10 * widget.weight) + (6.25 * widget.height) - (5 * widget.age) + 5;
    }
    if (bmr < 1000) bmr = 1000;

    double activityFactor = widget.bmi < 18.5
        ? 1.3
        : (widget.bmi < 25.0 ? 1.375 : 1.2);
    double tdee = bmr * activityFactor;
    
    double target = widget.bmi < 18.5
        ? tdee + (tdee * 0.15)
        : (widget.bmi >= 25.0 ? tdee - (tdee * 0.15) : tdee);
    
    if (target < bmr) target = bmr;
    _targetCal = target;
  }

  // Hàm khởi tạo danh sách món ăn ban đầu (tránh mảng rỗng khi khởi chạy)
  void _generateDefaultMeals() {
    int dayOfWeek = (widget.selectedDayDate.weekday - 1).clamp(0, 6);
    _currentDayMeals = NutritionService.getRecommendedMeals(
      widget.bmi,
      dayOfWeek,
      _targetCal,
    );
  }

  // --- TRUY XUẤT DỮ LIỆU TỪ SUPABASE ---
  Future<void> _loadExcludedIngredientsFromSupabase() async {
    // Không gọi setState() ở đây — _isLoadingAllergens đã được khởi tạo = true, và
    // gọi setState trong initState có thể gây lỗi '_elements.contains(element)'
    if (!mounted) return;

    List<String> loadedList = [];
    try {
      final profile = await _authService.getCurrentUserProfile();
      // Kiểm tra mounted sau await — widget có thể đã bị dispose trong lúc chờ
      if (!mounted) return;

      if (profile != null) {
        // Xử lý dữ liệu lấy về một cách an toàn đề phòng sai kiểu dữ liệu (Cast Error)
        final rawIngredients = profile['ExcludedIngredients'];

        if (rawIngredients is List) {
          loadedList = rawIngredients.map((e) => e.toString()).toList();
        } else if (rawIngredients is String) {
          if (rawIngredients.startsWith('{') && rawIngredients.endsWith('}')) {
            loadedList = rawIngredients
                .substring(1, rawIngredients.length - 1)
                .split(',')
                .where((element) => element.trim().isNotEmpty)
                .toList();
          } else if (rawIngredients.isNotEmpty) {
            loadedList = [rawIngredients];
          }
        }
      }
    } catch (e) {
      debugPrint("Lỗi khi tải bộ lọc dị ứng: $e");
    } finally {
      if (!mounted) return;

      // Tính toán thực đơn TRƯỚC khi gọi setState — tránh gọi setState nhiều lần liên tiếp
      // (nguyên nhân trực tiếp gây lỗi '_elements.contains(element)')
      _calculateTargetCal();
      final int dayOfWeek = (widget.selectedDayDate.weekday - 1).clamp(0, 6);
      final List<RecommendedMeal> originalMeals = NutritionService.getRecommendedMeals(
        widget.bmi,
        dayOfWeek,
        _targetCal,
      );
      // Tạm thời dùng loadedList vừa tải để lọc (vì _excludedIngredients chưa được cập nhật)
      final List<String> validExclusions =
          loadedList.where((ex) => ex.trim().isNotEmpty).toList();
      final List<RecommendedMeal> newMeals = originalMeals.map((meal) {
        final bool allergic = meal.ingredients.isNotEmpty &&
            validExclusions.isNotEmpty &&
            meal.ingredients.any(
              (ing) => validExclusions.any(
                (ex) => ing.toLowerCase().contains(ex.toLowerCase()),
              ),
            );
        if (allergic) {
          return _getAlternativeMeal(meal.key, _targetCal) ?? meal;
        }
        return meal;
      }).toList();

      // Một lần setState duy nhất — cập nhật toàn bộ trạng thái cùng lúc
      setState(() {
        _excludedIngredients = loadedList;
        _currentDayMeals = newMeals;
        _isLoadingAllergens = false;
      });
    }
  }

  // --- CẬP NHẬT DỮ LIỆU LÊN SUPABASE ---
  Future<void> _updateExcludedIngredientsToSupabase(
    List<String> newList,
  ) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Sử dụng đồng bộ tên cột viết thường chuẩn hóa database: 'ho_so_nguoi_dung'
      await Supabase.instance.client
          .from('ho_so_nguoi_dung')
          .update({'thanh_phan_di_ung': newList})
          .eq('ma_nguoi_dung', user.id);

      if (!mounted) return;

      // Tính toán newMeals TRƯỚC setState — tránh gọi setState 2 lần liên tiếp
      _calculateTargetCal();
      final int dayOfWeek = (widget.selectedDayDate.weekday - 1).clamp(0, 6);
      final List<RecommendedMeal> originalMeals = NutritionService.getRecommendedMeals(
        widget.bmi, dayOfWeek, _targetCal);
      final List<String> validExclusions =
          newList.where((ex) => ex.trim().isNotEmpty).toList();
      final List<RecommendedMeal> newMeals = originalMeals.map((meal) {
        final bool allergic = meal.ingredients.isNotEmpty &&
            validExclusions.isNotEmpty &&
            meal.ingredients.any(
              (ing) => validExclusions.any(
                (ex) => ing.toLowerCase().contains(ex.toLowerCase()),
              ),
            );
        if (allergic) return _getAlternativeMeal(meal.key, _targetCal) ?? meal;
        return meal;
      }).toList();

      // Một lần setState duy nhất cho cả _excludedIngredients lẫn _currentDayMeals
      setState(() {
        _excludedIngredients = newList;
        _currentDayMeals = newMeals;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi đồng bộ lên Supabase: $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
  }

  // Khởi tạo hoặc lọc danh sách món ăn hôm nay dựa trên danh sách dị ứng cố định từ Supabase
  void _generateOrFilterMeals() {
    _calculateTargetCal();
    int dayOfWeek = (widget.selectedDayDate.weekday - 1).clamp(0, 6);

    final List<RecommendedMeal> originalMeals = NutritionService.getRecommendedMeals(
      widget.bmi,
      dayOfWeek,
      _targetCal,
    );

    // Tách computation ra ngoài setState — setState chỉ được làm phép gán thuần túy
    final List<RecommendedMeal> newMeals = originalMeals.map((meal) {
      if (_isAllergic(meal)) {
        return _getAlternativeMeal(meal.key, _targetCal) ?? meal;
      }
      return meal;
    }).toList();

    if (!mounted) return;
    setState(() {
      _currentDayMeals = newMeals;
    });
  }

  // Kiểm tra xem món ăn có chứa nguyên liệu bị dị ứng hay không
  bool _isAllergic(RecommendedMeal meal) {
    if (meal.ingredients.isEmpty) return false;
    if (_excludedIngredients.isEmpty) return false;
    // Lọc bỏ chuỗi rỗng để tránh .contains("") luôn trả true cho mọi nguyên liệu
    final validExclusions = _excludedIngredients.where((ex) => ex.trim().isNotEmpty).toList();
    if (validExclusions.isEmpty) return false;
    return meal.ingredients.any(
      (ing) => validExclusions.any(
        (ex) => ing.toLowerCase().contains(ex.toLowerCase()),
      ),
    );
  }

  // Lấy món ăn thay thế an toàn
  RecommendedMeal? _getAlternativeMeal(String mealKey, double targetCal) {
    List<RecommendedMeal> alternatives = [];

    for (int i = 0; i < 7; i++) {
      final weekMeals = NutritionService.getRecommendedMeals(
        widget.bmi,
        i,
        targetCal,
      );
      for (var m in weekMeals) {
        if (m.key == mealKey && !_isAllergic(m)) {
          if (!alternatives.any((alt) => alt.description == m.description)) {
            alternatives.add(m);
          }
        }
      }
    }

    if (alternatives.isEmpty) return null;

    int currentIndex = _mealSwapIndexes[mealKey] ?? 0;
    int nextIndex = (currentIndex + 1) % alternatives.length;
    _mealSwapIndexes[mealKey] = nextIndex;

    return alternatives[currentIndex % alternatives.length];
  }

  // Hàm kích hoạt khi bấm nút "Đổi món"
  void _swapMeal(RecommendedMeal oldMeal, double targetCal) {
    final alternative = _getAlternativeMeal(oldMeal.key, targetCal);
    if (alternative != null) {
      setState(() {
        int index = _currentDayMeals.indexWhere((m) => m.key == oldMeal.key);
        if (index != -1) {
          _currentDayMeals[index] = alternative;
        }
      });

      final isEaten = widget.todayMealLogs.any(
        (element) => element['mealKey'] == oldMeal.key,
      );
      if (isEaten) {
        final newLogs = List<Map<String, dynamic>>.from(widget.todayMealLogs);
        newLogs.removeWhere((element) => element['mealKey'] == oldMeal.key);
        newLogs.add({
          'mealKey': alternative.key,
          'foodName': alternative.description,
          'calories': alternative.calories,
          'isRecommended': true,
        });
        widget.onMealLogsUpdated(newLogs);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Không tìm thấy món ăn thay thế nào phù hợp với bộ lọc dị ứng!',
          ),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
  }

  // Lọc động thực đơn dựa trên thanh tìm kiếm nguyên liệu tại chỗ
  List<RecommendedMeal> _getFilteredMeals() {
    if (_activeIngredientQuery.isEmpty) return _currentDayMeals;

    final query = _activeIngredientQuery.toLowerCase().trim();
    return _currentDayMeals.where((meal) {
      final hasMatchingIngredient = meal.ingredients.any(
        (ing) => ing.toLowerCase().contains(query),
      );
      if (_isExcludeMode) {
        return !hasMatchingIngredient;
      } else {
        return hasMatchingIngredient;
      }
    }).toList();
  }

  void _showAddCustomMealDialog() {
    final nameController = TextEditingController();
    final caloriesController = TextEditingController();

    showDialog(
      context: context,
      builder: (builderContext) {
        return AlertDialog(
          backgroundColor: AppTheme.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.add_circle_outline, color: AppTheme.neonBlue),
              SizedBox(width: 8),
              Text(
                'GHI NHẬN MÓN ĂN',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Tên món ăn / Đồ uống',
                  labelStyle: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: AppTheme.neonBlue),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: caloriesController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Lượng Calo (kcal)',
                  labelStyle: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: AppTheme.neonBlue),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(builderContext),
              child: const Text('Hủy', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                final cal = int.tryParse(caloriesController.text.trim()) ?? 0;
                if (name.isNotEmpty && cal > 0) {
                  final newLogs = List<Map<String, dynamic>>.from(
                    widget.todayMealLogs,
                  );
                  newLogs.add({
                    'mealKey':
                        'custom_${DateTime.now().millisecondsSinceEpoch}',
                    'foodName': name,
                    'calories': cal,
                    'isRecommended': false,
                  });
                  widget.onMealLogsUpdated(newLogs);
                  Navigator.pop(builderContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Đã ghi nhận món ăn thành công!'),
                      backgroundColor: AppTheme.neonGreen,
                      duration: Duration(seconds: 2),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Vui lòng nhập đầy đủ thông tin hợp lệ!'),
                      backgroundColor: AppTheme.errorRed,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.neonBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Lưu',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMacroItem(
    String label,
    String value,
    String percent,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '$value ($percent)',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.weight <= 0 || widget.height <= 0 || widget.age <= 0) {
      return const SizedBox.shrink();
    }

    String strategy = '';
    String strategyDetail = '';
    double carbRatio = 0.5;
    double proteinRatio = 0.25;
    double fatRatio = 0.25;

    List<String> guidelines = [];

    if (widget.bmi < 18.5) {
      strategy = 'Tăng cân & Tăng cơ (Calorie Surplus)';
      strategyDetail =
          'Để tăng cân lành mạnh, bạn cần nạp nhiều calo hơn lượng tiêu thụ, kết hợp bổ sung đạm để xây dựng cơ bắp.';
      guidelines = [
        'Chia nhỏ thành 5-6 bữa mỗi ngày (3 bữa chính, 2-3 bữa phụ).',
        'Tăng cường đạm chất lượng cao (thịt, cá, trứng, sữa, đạm thực vật).',
        'Ưu tiên tinh bột phức hợp (cơm, khoai tây, yến mạch) và chất béo tốt (bơ, các loại hạt).',
        'Uống đủ 2 - 2.5 lít nước, tránh uống nước trước bữa ăn để không bị no giả.',
      ];
    } else if (widget.bmi < 25.0) {
      if (widget.selectedGoal == 'build') {
        strategy = 'Tăng cơ nạc (Lean Bulking)';
        strategyDetail =
            'Duy trì thặng dư calo nhẹ để hỗ trợ tổng hợp cơ bắp mà không tích mỡ thừa.';
      } else {
        strategy = 'Duy trì vóc dáng (Calorie Maintenance)';
        strategyDetail =
            'Cân bằng giữa năng lượng nạp vào và tiêu thụ giúp giữ dáng săn chắc và tối ưu thể lực.';
      }
      guidelines = [
        'Duy trì lượng đạm ổn định (1.6g - 2g trên mỗi kg cân nặng).',
        'Ăn nhiều rau xanh và trái cây tươi để bổ sung vitamin, khoáng chất.',
        'Hạn chế thực phẩm chế biến sẵn, nhiều đường và dầu mỡ.',
        'Uống đủ 2 - 3 lít nước mỗi ngày để hỗ trợ trao đổi chất.',
      ];
    } else {
      strategy = 'Giảm mỡ & Giảm cân (Calorie Deficit)';
      strategyDetail =
          'Duy trì thâm hụt calo lành mạnh giúp cơ thể đốt cháy mỡ thừa mà không bị mệt mỏi.';
      carbRatio = 0.4;
      proteinRatio = 0.3;
      fatRatio = 0.3;
      guidelines = [
        'Giảm khẩu phần tinh bột nhanh, thay bằng khoai lang, yến mạch, gạo lứt.',
        'Tăng lượng protein để bảo vệ cơ bắp và tạo cảm giác no lâu.',
        'Ăn nhiều rau xanh (bắp cabbage, súp lơ, xà lách) trước bữa ăn chính.',
        'Uống 1 cốc nước ấm trước bữa ăn 15 phút, tuyệt đối tránh ăn đêm sau 20:00.',
      ];
    }

    double carbGrams = (_targetCal * carbRatio) / 4;
    double proteinGrams = (_targetCal * proteinRatio) / 4;
    double fatGrams = (_targetCal * fatRatio) / 9;

    int totalLoggedCalories = 0;
    for (var log in widget.todayMealLogs) {
      final cal = log['calories'];
      if (cal != null) {
        totalLoggedCalories += (cal as num).toInt();
      }
    }
    double progressVal = _targetCal > 0
        ? (totalLoggedCalories / _targetCal).clamp(0.0, 1.0)
        : 0.0;

    final displayMeals = _getFilteredMeals();

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const ValueKey<String>('nutrition_panel_expansion_tile'),
            initiallyExpanded: widget.bmi < 18.5,
            title: Row(
              children: [
                const Icon(
                  Icons.restaurant_menu,
                  color: AppTheme.neonBlue,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.bmi < 18.5
                        ? '🥗 CHẾ ĐỘ DINH DƯỠNG (BẮT BUỘC CHO THIẾU CÂN)'
                        : '🥗 CHẾ ĐỘ DINH DƯỠNG ĐỀ XUẤT',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.neonBlue,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              'Đã nạp: $totalLoggedCalories / ${_targetCal.toStringAsFixed(0)} kcal (${(progressVal * 100).toStringAsFixed(0)}%) | $strategy',
              style: TextStyle(
                color: progressVal >= 1.0 ? AppTheme.neonGreen : Colors.white70,
                fontSize: 11,
                fontWeight: progressVal >= 1.0
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            childrenPadding: const EdgeInsets.all(16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thanh tiến trình Calo
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TIẾN TRÌNH DINH DƯỠNG HÔM NAY',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          progressVal >= 1.0
                              ? 'Đã đạt mục tiêu! 🎉'
                              : 'Còn thiếu ${(_targetCal - totalLoggedCalories).clamp(0, 5000).toStringAsFixed(0)} kcal',
                          style: TextStyle(
                            color: progressVal >= 1.0
                                ? AppTheme.neonGreen
                                : AppTheme.neonBlue,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progressVal,
                        backgroundColor: Colors.white10,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          progressVal >= 1.0
                              ? AppTheme.neonGreen
                              : AppTheme.neonBlue,
                        ),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ================= QUẢN LÝ BỘ LỌC DỊ ỨNG (SUPABASE REALTIME) =================
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.no_food, color: AppTheme.errorRed, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'BỘ LỌC DỊ ỨNG / KIÊNG ĂN (CỐ ĐỊNH)',
                          style: TextStyle(
                            color: AppTheme.errorRed,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Thực đơn mẫu sẽ tự động thay thế các món có chứa thành phần này.',
                      style: TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                    const SizedBox(height: 8),
                    
                    // Xử lý trạng thái loading một cách độc lập và sạch sẽ
                    if (_isLoadingAllergens)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppTheme.neonBlue,
                              ),
                            ),
                          ),
                        ),
                      )
                    else ...[
                      // Row chứa TextField bắt buộc phải bọc Expanded để không bị tràn màn hình
                      // ================= HỘP CHỌN NGUYÊN LIỆU CỐ ĐỊNH =================
                      Row(
                        children: [
                          Expanded(
                            child: Autocomplete<String>(
                              optionsBuilder: (TextEditingValue textEditingValue) {
                                if (textEditingValue.text.isEmpty) {
                                  return const Iterable<String>.empty();
                                }
                                return kAllergensDataset.where((String option) {
                                  return option
                                      .toLowerCase()
                                      .contains(textEditingValue.text.toLowerCase());
                                });
                              },
                              fieldViewBuilder: (
                                BuildContext context,
                                TextEditingController fieldTextEditingController,
                                FocusNode fieldFocusNode,
                                VoidCallback onFieldSubmitted,
                              ) {
                                // Đồng bộ controller nội bộ của Autocomplete với controller của bạn (nếu cần dùng xóa chữ)
                                _allergyInputController = fieldTextEditingController;
                                return TextField(
                                  controller: fieldTextEditingController,
                                  focusNode: fieldFocusNode,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Tìm từ khóa (vd: Tôm, Sữa, Đậu phộng)...',
                                    hintStyle: const TextStyle(
                                      color: Colors.white30,
                                      fontSize: 11,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    isDense: true,
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: const BorderSide(
                                        color: Colors.white12,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: const BorderSide(
                                        color: AppTheme.errorRed,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                );
                              },
                              optionsViewBuilder: (
                                BuildContext context,
                                AutocompleteOnSelected<String> onSelected,
                                Iterable<String> options,
                              ) {
                                return Align(
                                  alignment: Alignment.topLeft,
                                  child: Material(
                                    color: const Color(0xFF1E293B), // Đồng bộ màu nền card của bạn
                                    elevation: 4.0,
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: MediaQuery.of(context).size.width * 0.6, // Giới hạn chiều rộng hộp đề xuất
                                      
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.white10),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: ListView.builder(
                                        padding: EdgeInsets.zero,
                                        shrinkWrap: true,
                                        itemCount: options.length,
                                        itemBuilder: (BuildContext context, int index) {
                                          final String option = options.elementAt(index);
                                          return InkWell(
                                            onTap: () => onSelected(option),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 10,
                                              ),
                                              
                                              child: Text(
                                                option,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                );
                              },
                              onSelected: (String selection) {
                                if (!_excludedIngredients.contains(selection)) {
                                  final newList = List<String>.from(_excludedIngredients)
                                    ..add(selection);
                                  _updateExcludedIngredientsToSupabase(newList);
                                }
                                _allergyInputController.clear();
                                FocusScope.of(context).unfocus();
                              },
                            ),
                          ),
                          
                        ],
                      ),
                      const SizedBox(height: 8),
                      
                      // Hiển thị danh sách các món bị dị ứng (InputChip)
                      if (_excludedIngredients.isEmpty)
                        const Text(
                          'Chưa có bộ lọc dị ứng nào được chọn.',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: _excludedIngredients.map((item) {
                            return InputChip(
                              key: ValueKey(item),
                              label: Text(
                                item,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                ),
                              ),
                              backgroundColor: Colors.red.withOpacity(0.2),
                              side: const BorderSide(
                                color: Colors.redAccent,
                                width: 0.5,
                              ),
                              onDeleted: () {
                                final newList = List<String>.from(
                                  _excludedIngredients,
                                )..remove(item);
                                _updateExcludedIngredientsToSupabase(newList);
                              },
                              deleteIcon: const Icon(
                                Icons.close,
                                size: 12,
                                color: Colors.white70,
                              ),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Text(
                strategyDetail,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'TỶ LỆ DINH DƯỠNG ĐỀ XUẤT',
                style: TextStyle(
                  color: AppTheme.neonBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    flex: (carbRatio * 100).round(),
                    child: Container(
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppTheme.neonGreen,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(4),
                          bottomLeft: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: (proteinRatio * 100).round(),
                    child: Container(height: 8, color: AppTheme.neonBlue),
                  ),
                  Expanded(
                    flex: (fatRatio * 100).round(),
                    child: Container(
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(4),
                          bottomRight: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildMacroItem(
                    'Tinh bột',
                    '${carbGrams.toStringAsFixed(0)}g',
                    '${(carbRatio * 100).toStringAsFixed(0)}%',
                    AppTheme.neonGreen,
                  ),
                  _buildMacroItem(
                    'Chất đạm',
                    '${proteinGrams.toStringAsFixed(0)}g',
                    '${(proteinRatio * 100).toStringAsFixed(0)}%',
                    AppTheme.neonBlue,
                  ),
                  _buildMacroItem(
                    'Chất béo',
                    '${fatGrams.toStringAsFixed(0)}g',
                    '${(fatRatio * 100).toStringAsFixed(0)}%',
                    Colors.orange,
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 24),
              const Text(
                'NGUYÊN TẮC DINH DƯỠNG',
                style: TextStyle(
                  color: AppTheme.neonBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              ...guidelines.map(
                (guide) => Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '• ',
                        style: TextStyle(
                          color: AppTheme.neonBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          guide,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(color: Colors.white12, height: 24),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    _isMealPlanExpanded = !_isMealPlanExpanded;
                  });
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'THỰC ĐƠN GỢI Ý MẪU',
                      style: TextStyle(
                        color: AppTheme.neonBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    Icon(
                      _isMealPlanExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: AppTheme.neonBlue,
                      size: 18,
                    ),
                  ],
                ),
              ),
              if (_isMealPlanExpanded) ...[
                const SizedBox(height: 12),

                // ================= BỘ LỌC NGUYÊN LIỆU ĐỘNG =================
                // Container(
                //   padding: const EdgeInsets.symmetric(
                //     horizontal: 10,
                //     vertical: 8,
                //   ),
                //   decoration: BoxDecoration(
                //     color: Colors.black26,
                //     borderRadius: BorderRadius.circular(10),
                //     border: Border.all(color: Colors.white12),
                //   ),
                //   child: Column(
                //     crossAxisAlignment: CrossAxisAlignment.start,
                //     children: [
                //       Row(
                //         children: [
                //           const Icon(
                //             Icons.filter_list,
                //             color: AppTheme.neonBlue,
                //             size: 16,
                //           ),
                //           const SizedBox(width: 6),
                //           const Text(
                //             'Lọc nguyên liệu tại chỗ',
                //             style: TextStyle(
                //               color: Colors.white70,
                //               fontSize: 11,
                //               fontWeight: FontWeight.bold,
                //             ),
                //           ),
                //           const Spacer(),
                //           GestureDetector(
                //             onTap: () {
                //               setState(() {
                //                 _isExcludeMode = !_isExcludeMode;
                //               });
                //             },
                //             child: Container(
                //               padding: const EdgeInsets.symmetric(
                //                 horizontal: 8,
                //                 vertical: 3,
                //               ),
                //               decoration: BoxDecoration(
                //                 color: _isExcludeMode
                //                     ? AppTheme.errorRed.withOpacity(0.2)
                //                     : AppTheme.neonGreen.withOpacity(0.2),
                //                 borderRadius: BorderRadius.circular(6),
                //                 border: Border.all(
                //                   color: _isExcludeMode
                //                       ? AppTheme.errorRed
                //                       : AppTheme.neonGreen,
                //                   width: 0.5,
                //                 ),
                //               ),
                //               child: Text(
                //                 _isExcludeMode ? 'Loại bỏ' : 'Bao gồm',
                //                 style: TextStyle(
                //                   color: _isExcludeMode
                //                       ? AppTheme.errorRed
                //                       : AppTheme.neonGreen,
                //                   fontSize: 10,
                //                   fontWeight: FontWeight.bold,
                //                 ),
                //               ),
                //             ),
                //           ),
                //         ],
                //       ),
                //       const SizedBox(height: 8),
                //       TextField(
                //         controller: _ingredientFilterController,
                //         style: const TextStyle(
                //           color: Colors.white,
                //           fontSize: 11,
                //         ),
                //         decoration: InputDecoration(
                //           hintText:
                //               'Nhập tên nguyên liệu (Ví dụ: Trứng, Sữa...)',
                //           hintStyle: const TextStyle(
                //             color: Colors.white38,
                //             fontSize: 11,
                //           ),
                //           contentPadding: const EdgeInsets.symmetric(
                //             horizontal: 10,
                //             vertical: 8,
                //           ),
                //           isDense: true,
                //           suffixIcon:
                //               _ingredientFilterController.text.isNotEmpty
                //               ? IconButton(
                //                   icon: const Icon(
                //                     Icons.clear,
                //                     color: Colors.white60,
                //                     size: 14,
                //                   ),
                //                   onPressed: () {
                //                     setState(() {
                //                       _ingredientFilterController.clear();
                //                       _activeIngredientQuery = "";
                //                     });
                //                   },
                //                 )
                //               : null,
                //           enabledBorder: OutlineInputBorder(
                //             borderSide: const BorderSide(color: Colors.white12),
                //             borderRadius: BorderRadius.circular(8),
                //           ),
                //           focusedBorder: OutlineInputBorder(
                //             borderSide: const BorderSide(
                //               color: AppTheme.neonBlue,
                //             ),
                //             borderRadius: BorderRadius.circular(8),
                //           ),
                //         ),
                //         onChanged: (val) {
                //           setState(() {
                //             _activeIngredientQuery = val;
                //           });
                //         },
                //       ),
                //       if (_activeIngredientQuery.isNotEmpty) ...[
                //         const SizedBox(height: 6),
                //         Wrap(
                //           children: [
                //             InputChip(
                //               label: Text(
                //                 '${_isExcludeMode ? "Không chứa" : "Phải chứa"}: $_activeIngredientQuery',
                //                 style: const TextStyle(
                //                   color: Colors.black,
                //                   fontSize: 9,
                //                   fontWeight: FontWeight.bold,
                //                 ),
                //               ),
                //               backgroundColor: AppTheme.neonBlue,
                //               onDeleted: () {
                //                 setState(() {
                //                   _ingredientFilterController.clear();
                //                   _activeIngredientQuery = "";
                //                 });
                //               },
                //               deleteIcon: const Icon(
                //                 Icons.cancel,
                //                 size: 12,
                //                 color: Colors.black,
                //               ),
                //               padding: EdgeInsets.zero,
                //               materialTapTargetSize:
                //                   MaterialTapTargetSize.shrinkWrap,
                //             ),
                //           ],
                //         ),
                //       ],
                //     ],
                //   ),
                // ),
                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      
                      const SizedBox(height: 12),

                      if (displayMeals.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              'Không tìm thấy món ăn nào phù hợp với bộ lọc nguyên liệu!',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        )
                      else
                        ...displayMeals.map((meal) {
                          final isEaten = widget.todayMealLogs.any(
                            (element) => element['mealKey'] == meal.key,
                          );

                          return Container(
                            padding: const EdgeInsets.all(10),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: isEaten
                                  ? AppTheme.neonGreen.withOpacity(0.08)
                                  : Colors.black12,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isEaten
                                    ? AppTheme.neonGreen.withOpacity(0.25)
                                    : Colors.white10,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () {
                                        final newLogs =
                                            List<Map<String, dynamic>>.from(
                                              widget.todayMealLogs,
                                            );
                                        if (isEaten) {
                                          newLogs.removeWhere(
                                            (element) =>
                                                element['mealKey'] == meal.key,
                                          );
                                        } else {
                                          newLogs.add({
                                            'mealKey': meal.key,
                                            'foodName': meal.description,
                                            'calories': meal.calories,
                                            'isRecommended': true,
                                          });
                                        }
                                        widget.onMealLogsUpdated(newLogs);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 2.0,
                                        ),
                                        child: Icon(
                                          isEaten
                                              ? Icons.check_box
                                              : Icons.check_box_outline_blank,
                                          color: isEaten
                                              ? AppTheme.neonGreen
                                              : Colors.white70,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                meal.timeLabel,
                                                style: TextStyle(
                                                  color: isEaten
                                                      ? AppTheme.neonGreen
                                                      : Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            '${meal.calories} kcal',
                                            style: const TextStyle(
                                              color: AppTheme.neonBlue,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            meal.description,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      onPressed: () =>
                                          _swapMeal(meal, _targetCal), // Sử dụng biến _targetCal của State an toàn
                                      icon: const Icon(
                                        Icons.autorenew,
                                        color: AppTheme.neonBlue,
                                        size: 18,
                                      ),
                                      tooltip: 'Đổi món ăn này',
                                      constraints: const BoxConstraints(),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ],
                                ),

                                if (meal.ingredients.isNotEmpty) ...[
                                  const Divider(
                                    color: Colors.white10,
                                    height: 12,
                                  ),
                                  const Text(
                                    'Nguyên liệu:',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: meal.ingredients.map((ing) {
                                      final isMatch =
                                          _activeIngredientQuery.isNotEmpty &&
                                          ing.toLowerCase().contains(
                                            _activeIngredientQuery
                                                .toLowerCase(),
                                          );
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isMatch
                                              ? (_isExcludeMode
                                                    ? AppTheme.errorRed
                                                          .withOpacity(0.2)
                                                    : AppTheme.neonGreen
                                                          .withOpacity(0.2))
                                              : Colors.white.withOpacity(0.05),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          border: Border.all(
                                            color: isMatch
                                                ? (_isExcludeMode
                                                      ? AppTheme.errorRed
                                                      : AppTheme.neonGreen)
                                                : Colors.white12,
                                          ),
                                        ),
                                        child: Text(
                                          ing,
                                          style: TextStyle(
                                            color: isMatch
                                                ? (_isExcludeMode
                                                      ? AppTheme.errorRed
                                                      : AppTheme.neonGreen)
                                                : Colors.white70,
                                            fontSize: 9,
                                            fontWeight: isMatch
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                    ],
                  ),
                ),
              ],
              if (widget.todayMealLogs.any(
                (element) => element['isRecommended'] == false,
              )) ...[
                const SizedBox(height: 20),
                const Text(
                  'BỮA ĂN TỰ GHI NHẬN',
                  style: TextStyle(
                    color: AppTheme.neonBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                ...widget.todayMealLogs
                    .where((element) => element['isRecommended'] == false)
                    .map(
                      (log) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                log['foodName']?.toString() ?? '',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  '+${log['calories']} kcal',
                                  style: const TextStyle(
                                    color: AppTheme.neonGreen,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: AppTheme.errorRed,
                                    size: 16,
                                  ),
                                  onPressed: () {
                                    final newLogs =
                                        List<Map<String, dynamic>>.from(
                                          widget.todayMealLogs,
                                        );
                                    newLogs.removeWhere(
                                      (element) =>
                                          element['mealKey'] == log['mealKey'],
                                    );
                                    widget.onMealLogsUpdated(newLogs);
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
              const SizedBox(height: 16),
              Center(
                child: ElevatedButton.icon(
                  onPressed: _showAddCustomMealDialog,
                  icon: const Icon(Icons.add, size: 14, color: Colors.black),
                  label: const Text(
                    'Ghi nhận món ăn khác',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.neonBlue,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
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