import '../models/recommended_meal.dart';

class NutritionService {
  static List<RecommendedMeal> getRecommendedMeals(double bmi, int dayOfWeek, double targetCal) {
    List<RecommendedMeal> list = [];
    if (bmi < 18.5) {
      // 6 bữa cho người thiếu cân
      final int cBreakfast = (targetCal * 0.22).round();
      final int cSnackAm = (targetCal * 0.08).round();
      final int cLunch = (targetCal * 0.28).round();
      final int cSnackPm = (targetCal * 0.12).round();
      final int cDinner = (targetCal * 0.24).round();
      final int cSnackNight = (targetCal * 0.06).round();

      switch (dayOfWeek) {
        case 0: // Thứ Hai
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Phở bò chín tái lớn + 1 ly sữa tươi nguyên kem', calories: cBreakfast),
            RecommendedMeal(key: 'snack_am', timeLabel: 'Bữa phụ sáng (09:30)', description: '1 quả chuối chín + 30g hạt hạnh nhân', calories: cSnackAm),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '2 bát cơm đầy + 150g sườn rim chả + canh cải xanh', calories: cLunch),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '2 lát bánh mì sandwich phết bơ đậu phộng dầm', calories: cSnackPm),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1.5 bát cơm + 150g cá thu sốt cà chua + bông cải xanh', calories: cDinner),
            RecommendedMeal(key: 'snack_night', timeLabel: 'Bữa phụ tối (21:30)', description: '1 hộp sữa chua có đường + mật ong', calories: cSnackNight),
          ];
          break;
        case 1: // Thứ Ba
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Hủ tiếu Nam Vang lòng heo trứng cút + 1 ly sữa đậu nành', calories: cBreakfast),
            RecommendedMeal(key: 'snack_am', timeLabel: 'Bữa phụ sáng (09:30)', description: 'Sinh tố bơ sữa đặc thơm béo', calories: cSnackAm),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '2 bát cơm + 150g đùi gà chiên mắm + canh bí đỏ', calories: cLunch),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '1 cái bánh bao nhân thịt xá xíu trứng cút', calories: cSnackPm),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1.5 bát cơm + 150g thịt bò xào thiên lý + canh rau ngót', calories: cDinner),
            RecommendedMeal(key: 'snack_night', timeLabel: 'Bữa phụ tối (21:30)', description: '1 cốc sữa ấm + 3 cái bánh quy lúa mạch', calories: cSnackNight),
          ];
          break;
        case 2: // Thứ Tư
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Xôi xéo chả lụa phi hành mỡ + 1 ly sữa tươi', calories: cBreakfast),
            RecommendedMeal(key: 'snack_am', timeLabel: 'Bữa phụ sáng (09:30)', description: '1 củ khoai lang mật nướng lớn + đậu phộng luộc', calories: cSnackAm),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '2 bát cơm + 150g tôm rim thịt ba chỉ + cải thìa xào', calories: cLunch),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: 'Sinh tố chuối bơ sữa đậu nành tăng cân', calories: cSnackPm),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1.5 bát cơm + 150g đậu phụ nhồi thịt sốt cà + canh chua', calories: cDinner),
            RecommendedMeal(key: 'snack_night', timeLabel: 'Bữa phụ tối (21:30)', description: '1 cốc sữa hạt sen ấm ngọt nhẹ', calories: cSnackNight),
          ];
          break;
        case 3: // Thứ Năm
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Phở gà ta da giòn lớn + 1 ly sữa tươi nguyên kem', calories: cBreakfast),
            RecommendedMeal(key: 'snack_am', timeLabel: 'Bữa phụ sáng (09:30)', description: '2 quả trứng gà luộc + 1 quả chuối chín', calories: cSnackAm),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '2 bát cơm + 150g bò né khổ qua + canh khoai tây hầm sườn', calories: cLunch),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: 'Ngũ cốc dinh dưỡng tăng cân pha sữa đặc', calories: cSnackPm),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1.5 bát cơm + 150g thịt heo luộc chấm mắm nêm + canh cải', calories: cDinner),
            RecommendedMeal(key: 'snack_night', timeLabel: 'Bữa phụ tối (21:30)', description: '1 hộp sữa chua nếp cẩm mát lạnh', calories: cSnackNight),
          ];
          break;
        case 4: // Thứ Sáu
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Bánh mì kẹp chả thịt xá xíu trứng + 1 ly nước cam đường', calories: cBreakfast),
            RecommendedMeal(key: 'snack_am', timeLabel: 'Bữa phụ sáng (09:30)', description: 'Sinh tố xoài cát sữa tươi nguyên kem', calories: cSnackAm),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '2 bát cơm + 150g cá điêu hồng chiên giòn + canh chua rau muống', calories: cLunch),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: 'Bánh bông lan trứng muối + 1 hộp sữa tươi', calories: cSnackPm),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1.5 bát cơm + 150g bò sốt vang khoai tây + xà lách trộn', calories: cDinner),
            RecommendedMeal(key: 'snack_night', timeLabel: 'Bữa phụ tối (21:30)', description: 'Một nắm nhỏ hạt óc chó/macca dầm mật ong', calories: cSnackNight),
          ];
          break;
        default: // Cuối tuần (Thứ 7 & Chủ Nhật)
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Mì Quảng tôm thịt trứng cút lớn + sữa bắp thơm', calories: cBreakfast),
            RecommendedMeal(key: 'snack_am', timeLabel: 'Bữa phụ sáng (09:30)', description: 'Phô mai miếng + 1 quả táo chín ngọt', calories: cSnackAm),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '2 bát cơm + 150g mực nhồi thịt chiên + canh cua mồng tơi', calories: cLunch),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: 'Bánh giò nóng nhân thịt nấm mộc nhĩ + sữa tươi', calories: cSnackPm),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1.5 bát cơm + 150g gà rang gừng + canh bí đao tôm băm', calories: cDinner),
            RecommendedMeal(key: 'snack_night', timeLabel: 'Bữa phụ tối (21:30)', description: '1 ly sữa yến mạch ấm pha mật ong', calories: cSnackNight),
          ];
          break;
      }
    } else if (bmi < 25.0) {
      // 4 bữa cho người bình thường
      final int cBreakfast = (targetCal * 0.25).round();
      final int cLunch = (targetCal * 0.35).round();
      final int cSnackPm = (targetCal * 0.12).round();
      final int cDinner = (targetCal * 0.28).round();

      switch (dayOfWeek) {
        case 0: // Thứ Hai
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: '2 quả trứng ốp la + 2 lát bánh mì đen + 1 quả táo', calories: cBreakfast),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1.5 bát cơm gạo lứt + 150g ức gà áp chảo + súp lơ xanh luộc', calories: cLunch),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '1 hộp sữa chua không đường + hạt granola', calories: cSnackPm),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1 bát cơm + 150g tôm rim sả + canh rau muống luộc', calories: cDinner),
          ];
          break;
        case 1: // Thứ Ba
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: '1 bát cháo yến mạch thịt băm + 1 cốc trà hoa cúc ấm', calories: cBreakfast),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1.5 bát cơm gạo lứt + 150g cá hồi áp chảo + măng tây xào', calories: cLunch),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '1 quả chuối chín + 1 ly sữa tươi không đường', calories: cSnackPm),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1 bát cơm + 150g bò xào hành tây + canh khoai tây cà rốt', calories: cDinner),
          ];
          break;
        case 2: // Thứ Tư
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Bánh mì sandwich phết bơ bơ đậu phộng + 1 ly sữa đậu nành', calories: cBreakfast),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1.5 bát cơm + 150g thịt thăn lợn rim nhạt + cải thảo luộc', calories: cLunch),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: 'Salad hoa quả trộn sữa chua Hy Lạp', calories: cSnackPm),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1 bát cơm + 150g cá basa sốt dầu hào + canh cải thìa thịt băm', calories: cDinner),
          ];
          break;
        default: // Các ngày khác
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: '1 bát bún sườn heo nhiều rau xanh + nước lọc ấm', calories: cBreakfast),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1.5 bát cơm gạo lứt + 150g mực xào cần tỏi + canh cải ngọt', calories: cLunch),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: 'Một nắm nhỏ hạt điều/hạnh nhân (khoảng 20g)', calories: cSnackPm),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1 bát cơm + 150g đậu phụ nhồi thịt canh cải cúc', calories: cDinner),
          ];
          break;
      }
    } else {
      // 4 bữa cho người béo phì / thừa cân
      final int cBreakfast = (targetCal * 0.25).round();
      final int cLunch = (targetCal * 0.35).round();
      final int cSnackPm = (targetCal * 0.08).round();
      final int cDinner = (targetCal * 0.32).round();

      switch (dayOfWeek) {
        case 0: // Thứ Hai
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: '1 bát cháo yến mạch ức gà xé nhạt + trà xanh ấm', calories: cBreakfast),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1 bát cơm gạo lứt + 150g cá rô phi hấp sả + đĩa súp lơ xanh luộc', calories: cLunch),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '1 quả táo ta chín giòn', calories: cSnackPm),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1/2 bát cơm gạo lứt + 150g thịt thăn bò áp chảo + đĩa salad lớn', calories: cDinner),
          ];
          break;
        case 1: // Thứ Ba
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: '2 quả trứng luộc + 1 lát bánh mì đen nhỏ + dưa chuột', calories: cBreakfast),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1 bát cơm gạo lứt + 150g mực hấp lá hành + canh cải thảo thịt băm', calories: cLunch),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '1 quả ổi vừa ngọt nhẹ', calories: cSnackPm),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1/2 bát cơm + 150g ức gà nướng nghệ + bông cải luộc', calories: cDinner),
          ];
          break;
        default: // Các ngày khác
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Khoai lang luộc + 1 cốc sữa đậu nành không đường', calories: cBreakfast),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1 bát cơm gạo lứt + 150g tôm hấp sả + đĩa rau muống luộc lớn', calories: cLunch),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '1 hộp sữa chua Hy Lạp không đường', calories: cSnackPm),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1/2 bát cơm gạo lứt + 150g cá hồi áp chảo + canh cải thìa canh nhạt', calories: cDinner),
          ];
          break;
      }
    }
    return list;
  }
}
