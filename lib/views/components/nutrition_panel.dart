import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/recommended_meal.dart';
import '../../services/nutrition_service.dart';

class NutritionPanel extends StatefulWidget {
  final double weight;
  final double height;
  final int age;
  final String selectedGoal;
  final double bmi;
  final DateTime selectedDayDate;
  final List<Map<String, dynamic>> todayMealLogs;
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
    required this.onMealLogsUpdated,
  });

  @override
  State<NutritionPanel> createState() => _NutritionPanelState();
}

class _NutritionPanelState extends State<NutritionPanel> {
  bool _isMealPlanExpanded = false;

  void _showAddCustomMealDialog() {
    final nameController = TextEditingController();
    final caloriesController = TextEditingController();

    showDialog(
      context: context,
      builder: (builderContext) {
        return AlertDialog(
          backgroundColor: AppTheme.cardBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.add_circle_outline, color: AppTheme.neonBlue),
              SizedBox(width: 8),
              Text(
                'GHI NHẬN MÓN ĂN',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.0),
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
                  labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
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
                  labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
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
                  final newLogs = List<Map<String, dynamic>>.from(widget.todayMealLogs);
                  newLogs.add({
                    'mealKey': 'custom_${DateTime.now().millisecondsSinceEpoch}',
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Lưu', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMacroItem(String label, String value, String percent, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 2),
        Text('$value ($percent)', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.weight <= 0 || widget.height <= 0 || widget.age <= 0) return const SizedBox.shrink();

    double bmr = (10 * widget.weight) + (6.25 * widget.height) - (5 * widget.age) - 78;
    if (bmr < 1000) bmr = 1000;

    double activityFactor = 1.25;
    if (widget.bmi < 18.5) {
      activityFactor = 1.3;
    } else if (widget.bmi < 25.0) {
      activityFactor = 1.375;
    } else {
      activityFactor = 1.2;
    }

    double tdee = bmr * activityFactor;
    double targetCal = tdee;
    String strategy = '';
    String strategyDetail = '';
    double carbRatio = 0.5;
    double proteinRatio = 0.25;
    double fatRatio = 0.25;

    List<String> guidelines = [];
    int dayOfWeek = (widget.selectedDayDate.weekday - 1).clamp(0, 6);

    if (widget.bmi < 18.5) {
      targetCal = tdee + (tdee * 0.15); // Thặng dư 15%
      strategy = 'Tăng cân & Tăng cơ (Calorie Surplus)';
      strategyDetail = 'Để tăng cân lành mạnh, bạn cần nạp nhiều calo hơn lượng tiêu thụ, kết hợp bổ sung đạm để xây dựng cơ bắp.';
      guidelines = [
        'Chia nhỏ thành 5-6 bữa mỗi ngày (3 bữa chính, 2-3 bữa phụ).',
        'Tăng cường đạm chất lượng cao (thịt, cá, trứng, sữa, đạm thực vật).',
        'Ưu tiên tinh bột phức hợp (cơm, khoai tây, yến mạch) và chất béo tốt (bơ, các loại hạt).',
        'Uống đủ 2 - 2.5 lít nước, tránh uống nước trước bữa ăn để không bị no giả.'
      ];
    } else if (widget.bmi < 25.0) {
      if (widget.selectedGoal == 'build') {
        targetCal = tdee + (tdee * 0.10);
        strategy = 'Tăng cơ nạc (Lean Bulking)';
        strategyDetail = 'Duy trì thặng dư calo nhẹ để hỗ trợ tổng hợp cơ bắp mà không tích mỡ thừa.';
      } else {
        targetCal = tdee;
        strategy = 'Duy trì vóc dáng (Calorie Maintenance)';
        strategyDetail = 'Cân bằng giữa năng lượng nạp vào và tiêu thụ giúp giữ dáng săn chắc và tối ưu thể lực.';
      }
      guidelines = [
        'Duy trì lượng đạm ổn định (1.6g - 2g trên mỗi kg cân nặng).',
        'Ăn nhiều rau xanh và trái cây tươi để bổ sung vitamin, khoáng chất.',
        'Hạn chế thực phẩm chế biến sẵn, nhiều đường và dầu mỡ.',
        'Uống đủ 2 - 3 lít nước mỗi ngày để hỗ trợ trao đổi chất.'
      ];
    } else {
      targetCal = tdee - (tdee * 0.15); // Thâm hụt 15%
      strategy = 'Giảm mỡ & Giảm cân (Calorie Deficit)';
      strategyDetail = 'Duy trì thâm hụt calo lành mạnh giúp cơ thể đốt cháy mỡ thừa mà không bị mệt mỏi.';
      carbRatio = 0.4;
      proteinRatio = 0.3;
      fatRatio = 0.3;
      guidelines = [
        'Giảm khẩu phần tinh bột nhanh, thay bằng khoai lang, yến mạch, gạo lứt.',
        'Tăng lượng protein để bảo vệ cơ bắp và tạo cảm giác no lâu.',
        'Ăn nhiều rau xanh (bắp cải, súp lơ, xà lách) trước bữa ăn chính.',
        'Uống 1 cốc nước ấm trước bữa ăn 15 phút, tuyệt đối tránh ăn đêm sau 20:00.'
      ];
    }

    if (targetCal < bmr) targetCal = bmr;

    List<RecommendedMeal> mealList = NutritionService.getRecommendedMeals(widget.bmi, dayOfWeek, targetCal);

    // Tính số gam dinh dưỡng
    double carbGrams = (targetCal * carbRatio) / 4;
    double proteinGrams = (targetCal * proteinRatio) / 4;
    double fatGrams = (targetCal * fatRatio) / 9;

    // Tính tổng calo đã nạp từ nhật ký
    int totalLoggedCalories = 0;
    for (var log in widget.todayMealLogs) {
      totalLoggedCalories += (log['calories'] as num).toInt();
    }
    double progressVal = targetCal > 0 ? (totalLoggedCalories / targetCal).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B), // Màu Slate 800 tối đậm rõ ràng
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const PageStorageKey<String>('nutrition_panel'),
            initiallyExpanded: widget.bmi < 18.5,
            title: Row(
              children: [
                const Icon(Icons.restaurant_menu, color: AppTheme.neonBlue, size: 20),
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
              'Đã nạp: $totalLoggedCalories / ${targetCal.toStringAsFixed(0)} kcal (${(progressVal * 100).toStringAsFixed(0)}%) | $strategy',
              style: TextStyle(
                color: progressVal >= 1.0 ? AppTheme.neonGreen : Colors.white70,
                fontSize: 11,
                fontWeight: progressVal >= 1.0 ? FontWeight.bold : FontWeight.normal,
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TIẾN TRÌNH DINH DƯỠNG HÔM NAY',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          progressVal >= 1.0 ? 'Đã đạt mục tiêu! 🎉' : 'Còn thiếu ${(targetCal - totalLoggedCalories).clamp(0, 5000).toStringAsFixed(0)} kcal',
                          style: TextStyle(
                            color: progressVal >= 1.0 ? AppTheme.neonGreen : AppTheme.neonBlue,
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
                        valueColor: AlwaysStoppedAnimation<Color>(progressVal >= 1.0 ? AppTheme.neonGreen : AppTheme.neonBlue),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              Text(
                strategyDetail,
                style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4),
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
                  _buildMacroItem('Tinh bột', '${carbGrams.toStringAsFixed(0)}g', '${(carbRatio*100).toStringAsFixed(0)}%', AppTheme.neonGreen),
                  _buildMacroItem('Chất đạm', '${proteinGrams.toStringAsFixed(0)}g', '${(proteinRatio*100).toStringAsFixed(0)}%', AppTheme.neonBlue),
                  _buildMacroItem('Chất béo', '${fatGrams.toStringAsFixed(0)}g', '${(fatRatio*100).toStringAsFixed(0)}%', Colors.orange),
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
              ...guidelines.map((guide) => Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(color: AppTheme.neonBlue, fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Text(
                        guide,
                        style: const TextStyle(color: Colors.white, fontSize: 11.5, height: 1.4),
                      ),
                    ),
                  ],
                ),
              )),
              const Divider(color: Colors.white12, height: 24),
              Row(
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
                    _isMealPlanExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: AppTheme.neonBlue,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isMealPlanExpanded = !_isMealPlanExpanded;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_isMealPlanExpanded)
                        const Center(
                          child: Text(
                            'Bấm để xem thực đơn chi tiết từng bữa',
                            style: TextStyle(color: Colors.white, fontSize: 11, fontStyle: FontStyle.italic),
                          ),
                        ),
                      if (_isMealPlanExpanded) ...[
                        ...mealList.map((meal) {
                          final isEaten = widget.todayMealLogs.any((element) => element['mealKey'] == meal.key);
                          return GestureDetector(
                            onTap: () {
                              final newLogs = List<Map<String, dynamic>>.from(widget.todayMealLogs);
                              if (isEaten) {
                                newLogs.removeWhere((element) => element['mealKey'] == meal.key);
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
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: isEaten ? AppTheme.neonGreen.withValues(alpha: 0.08) : Colors.black12,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isEaten ? AppTheme.neonGreen.withValues(alpha: 0.25) : Colors.white10),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isEaten ? Icons.check_box : Icons.check_box_outline_blank,
                                    color: isEaten ? AppTheme.neonGreen : Colors.white70,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(meal.timeLabel, style: TextStyle(color: isEaten ? AppTheme.neonGreen : Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                            Text('${meal.calories} kcal', style: const TextStyle(color: AppTheme.neonBlue, fontSize: 11, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(meal.description, style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.4)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ]
                    ],
                  ),
                ),
              ),
              if (widget.todayMealLogs.any((element) => element['isRecommended'] == false)) ...[
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
                ...widget.todayMealLogs.where((element) => element['isRecommended'] == false).map((log) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                        child: Text(log['foodName'] as String, style: const TextStyle(color: Colors.white, fontSize: 11.5)),
                      ),
                      Row(
                        children: [
                          Text('+${log['calories']} kcal', style: const TextStyle(color: AppTheme.neonGreen, fontSize: 11.5, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppTheme.errorRed, size: 16),
                            onPressed: () {
                              final newLogs = List<Map<String, dynamic>>.from(widget.todayMealLogs);
                              newLogs.removeWhere((element) => element['mealKey'] == log['mealKey']);
                              widget.onMealLogsUpdated(newLogs);
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ],
                  ),
                )),
              ],
              const SizedBox(height: 16),
              Center(
                child: ElevatedButton.icon(
                  onPressed: _showAddCustomMealDialog,
                  icon: const Icon(Icons.add, size: 14, color: Colors.black),
                  label: const Text('Ghi nhận món ăn khác', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.neonBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
