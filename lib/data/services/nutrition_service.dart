import 'package:demo/domain/recommended_meal.dart';

class NutritionService {
  static List<RecommendedMeal> getRecommendedMeals(double bmi, int dayOfWeek, double targetCal) {
    List<RecommendedMeal> list = [];
    if (bmi < 18.5) {
      
      final int cBreakfast = (targetCal * 0.22).round();
      final int cSnackAm = (targetCal * 0.08).round();
      final int cLunch = (targetCal * 0.28).round();
      final int cSnackPm = (targetCal * 0.12).round();
      final int cDinner = (targetCal * 0.24).round();
      final int cSnackNight = (targetCal * 0.06).round();

      switch (dayOfWeek) {
        case 0: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Phở bò chín tái lớn + 1 ly sữa tươi nguyên kem', calories: cBreakfast, ingredients: ['Thịt bò', 'Bánh phở', 'Sữa tươi']),
            RecommendedMeal(key: 'snack_am', timeLabel: 'Bữa phụ sáng (09:30)', description: '1 quả chuối chín + 30g hạt hạnh nhân', calories: cSnackAm, ingredients: ['Chuối', 'Hạt hạnh nhân']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '2 bát cơm đầy + 150g sườn rim chả + canh cải xanh', calories: cLunch, ingredients: ['Cơm', 'Thịt heo', 'Chả lụa', 'Cải xanh']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '2 lát bánh mì sandwich phết bơ đậu phộng dầm', calories: cSnackPm, ingredients: ['Bánh mì', 'Bơ đậu phộng']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1.5 bát cơm + 150g cá thu sốt cà chua + bông cải xanh', calories: cDinner, ingredients: ['Cơm', 'Cá thu', 'Cà chua', 'Bông cải xanh']),
            RecommendedMeal(key: 'snack_night', timeLabel: 'Bữa phụ tối (21:30)', description: '1 hộp sữa chua có đường + mật ong', calories: cSnackNight, ingredients: ['Sữa chua', 'Mật ong']),
          ];
          break;
        case 1: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Hủ tiếu Nam Vang lòng heo trứng cút + 1 ly sữa đậu nành', calories: cBreakfast, ingredients: ['Hủ tiếu', 'Lòng heo', 'Trứng cút', 'Đậu nành']),
            RecommendedMeal(key: 'snack_am', timeLabel: 'Bữa phụ sáng (09:30)', description: 'Sinh tố bơ sữa đặc thơm béo', calories: cSnackAm, ingredients: ['Bơ', 'Sữa đặc']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '2 bát cơm + 150g đùi gà chiên mắm + canh bí đỏ', calories: cLunch, ingredients: ['Cơm', 'Thịt gà', 'Bí đỏ']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '1 cái bánh bao nhân thịt xá xíu trứng cút', calories: cSnackPm, ingredients: ['Bánh bao', 'Thịt heo', 'Trứng cút']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1.5 bát cơm + 150g thịt bò xào thiên lý + canh rau ngót', calories: cDinner, ingredients: ['Cơm', 'Thịt bò', 'Hoa thiên lý', 'Rau ngót']),
            RecommendedMeal(key: 'snack_night', timeLabel: 'Bữa phụ tối (21:30)', description: '1 cốc sữa ấm + 3 cái bánh quy lúa mạch', calories: cSnackNight, ingredients: ['Sữa tươi', 'Bánh quy lúa mạch']),
          ];
          break;
        case 2: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Xôi xéo chả lụa phi hành mỡ + 1 ly sữa tươi', calories: cBreakfast, ingredients: ['Xôi xéo', 'Chả lụa', 'Hành tím', 'Sữa tươi']),
            RecommendedMeal(key: 'snack_am', timeLabel: 'Bữa phụ sáng (09:30)', description: '1 củ khoai lang mật nướng lớn + đậu phộng luộc', calories: cSnackAm, ingredients: ['Khoai lang', 'Đậu phộng']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '2 bát cơm + 150g tôm rim thịt ba chỉ + cải thìa xào', calories: cLunch, ingredients: ['Cơm', 'Tôm', 'Thịt heo', 'Cải thìa']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: 'Sinh tố chuối bơ sữa đậu nành tăng cân', calories: cSnackPm, ingredients: ['Chuối', 'Bơ', 'Đậu nành', 'Sữa đặc']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1.5 bát cơm + 150g đậu phụ nhồi thịt sốt cà + canh chua', calories: cDinner, ingredients: ['Cơm', 'Đậu phụ', 'Thịt heo', 'Cà chua', 'Dứa', 'Me']),
            RecommendedMeal(key: 'snack_night', timeLabel: 'Bữa phụ tối (21:30)', description: '1 cốc sữa hạt sen ấm ngọt nhẹ', calories: cSnackNight, ingredients: ['Hạt sen', 'Sữa tươi']),
          ];
          break;
        case 3: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Phở gà ta da giòn lớn + 1 ly sữa tươi nguyên kem', calories: cBreakfast, ingredients: ['Bánh phở', 'Thịt gà', 'Sữa tươi']),
            RecommendedMeal(key: 'snack_am', timeLabel: 'Bữa phụ sáng (09:30)', description: '2 quả trứng gà luộc + 1 quả chuối chín', calories: cSnackAm, ingredients: ['Trứng gà', 'Chuối']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '2 bát cơm + 150g bò né khổ qua + canh khoai tây hầm sườn', calories: cLunch, ingredients: ['Cơm', 'Thịt bò', 'Khổ qua', 'Khoai tây', 'Thịt heo']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: 'Ngũ cốc dinh dưỡng tăng cân pha sữa đặc', calories: cSnackPm, ingredients: ['Bột ngũ cốc', 'Sữa đặc']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1.5 bát cơm + 150g thịt heo luộc chấm mắm nêm + canh cải', calories: cDinner, ingredients: ['Cơm', 'Thịt heo', 'Mắm nêm', 'Cải canh']),
            RecommendedMeal(key: 'snack_night', timeLabel: 'Bữa phụ tối (21:30)', description: '1 hộp sữa chua nếp cẩm mát lạnh', calories: cSnackNight, ingredients: ['Sữa chua nếp cẩm']),
          ];
          break;
        case 4: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Bánh mì kẹp chả thịt xá xíu trứng + 1 ly nước cam đường', calories: cBreakfast, ingredients: ['Bánh mì', 'Chả lụa', 'Thịt heo', 'Trứng gà', 'Cam', 'Đường']),
            RecommendedMeal(key: 'snack_am', timeLabel: 'Bữa phụ sáng (09:30)', description: 'Sinh tố xoài cát sữa tươi nguyên kem', calories: cSnackAm, ingredients: ['Xoài', 'Sữa tươi', 'Sữa đặc']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '2 bát cơm + 150g cá điêu hồng chiên giòn + canh chua rau muống', calories: cLunch, ingredients: ['Cơm', 'Cá điêu hồng', 'Rau muống', 'Me', 'Cà chua']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: 'Bánh bông lan trứng muối + 1 hộp sữa tươi', calories: cSnackPm, ingredients: ['Bánh bông lan','Trứng gà', 'Sữa tươi']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1.5 bát cơm + 150g bò sốt vang khoai tây + xà lách trộn', calories: cDinner, ingredients: ['Cơm', 'Thịt bò', 'Khoai tây', 'Cà rốt', 'Xà lách']),
            RecommendedMeal(key: 'snack_night', timeLabel: 'Bữa phụ tối (21:30)', description: 'Một nắm nhỏ hạt óc chó/macca dầm mật ong', calories: cSnackNight, ingredients: ['Hạt óc chó', 'Hạt macca', 'Mật ong']),
          ];
          break;
        case 5: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Mì Quảng tôm thịt trứng cút lớn + sữa bắp thơm', calories: cBreakfast, ingredients: ['Mì Quảng', 'Tôm', 'Thịt heo', 'Trứng cút', 'Bắp']),
            RecommendedMeal(key: 'snack_am', timeLabel: 'Bữa phụ sáng (09:30)', description: 'Phô mai miếng + 1 quả táo chín ngọt', calories: cSnackAm, ingredients: ['Phô mai', 'Táo']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '2 bát cơm + 150g mực nhồi thịt chiên + canh cua mồng tơi', calories: cLunch, ingredients: ['Cơm', 'Mực', 'Thịt heo', 'Cua', 'Rau mồng tơi']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: 'Bánh giò nóng nhân thịt nấm mộc nhĩ + sữa tươi', calories: cSnackPm, ingredients: ['Bánh giò', 'Thịt heo', 'Nấm mộc nhĩ', 'Sữa tươi']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1.5 bát cơm + 150g gà rang gừng + canh bí đao tôm băm', calories: cDinner, ingredients: ['Cơm', 'Thịt gà', 'Gừng', 'Bí đao', 'Tôm']),
            RecommendedMeal(key: 'snack_night', timeLabel: 'Bữa phụ tối (21:30)', description: '1 ly sữa yến mạch ấm pha mật ong', calories: cSnackNight, ingredients: ['Sữa yến mạch', 'Mật ong']),
          ];
          break;
        default: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Bún bò Huế giò khoanh lớn + 1 ly nước mía', calories: cBreakfast, ingredients: ['Bún', 'Thịt bò', 'Thịt heo', 'Mía']),
            RecommendedMeal(key: 'snack_am', timeLabel: 'Bữa phụ sáng (09:30)', description: '1 hộp sữa chua uống trái cây + hạt dẻ', calories: cSnackAm, ingredients: ['Sữa chua uống', 'Trái cây', 'Hạt dẻ']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '2 bát cơm + 150g thịt kho tàu trứng cút + canh rau má', calories: cLunch, ingredients: ['Cơm', 'Thịt heo', 'Trứng cút', 'Rau má']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '2 cái bánh tart trứng nóng hổi + sữa đậu xanh', calories: cSnackPm, ingredients: ['Bánh tart','Trứng gà', 'Đậu xanh']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1.5 bát cơm + 150g chả cá thác lác vân mây + canh cá hồi nấu ngót', calories: cDinner, ingredients: ['Cơm', 'Cá thác lác', 'Cá hồi', 'Cà chua', 'Thì là', 'Dứa']),
            RecommendedMeal(key: 'snack_night', timeLabel: 'Bữa phụ tối (21:30)', description: '1 ly sữa ấm nguyên kem mật ong trước ngủ', calories: cSnackNight, ingredients: ['Sữa tươi', 'Mật ong']),
          ];
          break;
      }
    } else if (bmi < 25.0) {
      
      final int cBreakfast = (targetCal * 0.25).round();
      final int cLunch = (targetCal * 0.35).round();
      final int cSnackPm = (targetCal * 0.12).round();
      final int cDinner = (targetCal * 0.28).round();

      switch (dayOfWeek) {
        case 0: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: '2 quả trứng ốp la + 2 lát bánh mì đen + 1 quả táo', calories: cBreakfast, ingredients: ['Trứng gà', 'Bánh mì', 'Táo']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1.5 bát cơm gạo lứt + 150g ức gà áp chảo + súp lơ xanh luộc', calories: cLunch, ingredients: ['Cơm gạo lứt', 'Thịt gà', 'Súp lơ xanh']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '1 hộp sữa chua không đường + hạt granola', calories: cSnackPm, ingredients: ['Sữa chua ', 'Hạt granola']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1 bát cơm + 150g tôm rim sả + canh rau muống luộc', calories: cDinner, ingredients: ['Cơm', 'Tôm', 'Sả', 'Rau muống']),
          ];
          break;
        case 1: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: '1 bát cháo yến mạch thịt băm + 1 cốc trà hoa cúc ấm', calories: cBreakfast, ingredients: ['Yến mạch', 'Thịt heo', 'Trà hoa cúc']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1.5 bát cơm gạo lứt + 150g cá hồi áp chảo + măng tây xào', calories: cLunch, ingredients: ['Cơm gạo lứt', 'Cá hồi', 'Măng tây']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '1 quả chuối chín + 1 ly sữa tươi không đường', calories: cSnackPm, ingredients: ['Chuối', 'Sữa tươi']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1 bát cơm + 150g bò xào hành tây + canh khoai tây cà rốt', calories: cDinner, ingredients: ['Cơm', 'Thịt bò', 'Hành tây', 'Khoai tây', 'Cà rốt']),
          ];
          break;
        case 2: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Bánh mì sandwich phết bơ đậu phộng + 1 ly sữa đậu nành', calories: cBreakfast, ingredients: ['Bánh mì', 'Bơ đậu phộng', 'Đậu nành']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1.5 bát cơm + 150g thịt thăn lợn rim nhạt + cải thảo luộc', calories: cLunch, ingredients: ['Cơm', 'Thịt heo', 'Cải thảo']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: 'Salad hoa quả trộn sữa chua Hy Lạp', calories: cSnackPm, ingredients: ['Trái cây', 'Sữa chua Hy Lạp']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1 bát cơm + 150g cá basa sốt dầu hào + canh cải thìa thịt băm', calories: cDinner, ingredients: ['Cơm', 'Cá basa', 'Dầu hào', 'Cải thìa', 'Thịt heo']),
          ];
          break;
        case 3: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Phở gà ta thơm ngọt + 1 ly nước cam nguyên chất ít đường', calories: cBreakfast, ingredients: ['Bánh phở', 'Thịt gà', 'Cam', 'Đường']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1.5 bát cơm + 150g bò cuốn lá lốt + canh bí đỏ nấu tôm', calories: cLunch, ingredients: ['Cơm', 'Thịt bò', 'Lá lốt', 'Bí đỏ', 'Tôm']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '1 hộp sữa chua uống men sống + 1 nắm hạt hạnh nhân', calories: cSnackPm, ingredients: ['Sữa chua uống', 'Hạt hạnh nhân']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1 bát cơm + 150g thịt viên sốt nấm + rau cải ngọt luộc', calories: cDinner, ingredients: ['Cơm', 'Thịt heo', 'Nấm', 'Cải ngọt']),
          ];
          break;
        case 4: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: '1 bát bún sườn heo nhiều rau xanh + nước lọc ấm', calories: cBreakfast, ingredients: ['Bún', 'Thịt heo', 'Rau xanh']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1.5 bát cơm gạo lứt + 150g mực xào cần tỏi + canh cải ngọt', calories: cLunch, ingredients: ['Cơm gạo lứt', 'Mực', 'Cần tây', 'Tỏi tây', 'Cải ngọt']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: 'Một nắm nhỏ hạt điều/hạnh nhân (khoảng 20g)', calories: cSnackPm, ingredients: ['Hạt điều', 'Hạt hạnh nhân']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1 bát cơm + 150g đậu phụ nhồi thịt canh cải cúc', calories: cDinner, ingredients: ['Cơm', 'Đậu phụ', 'Thịt heo', 'Cải cúc']),
          ];
          break;
        case 5: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Hủ tiếu Nam Vang thanh đạm + 1 quả quýt ngọt', calories: cBreakfast, ingredients: ['Hủ tiếu', 'Quýt']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1.5 bát cơm + 150g cá điêu hồng hấp gừng + canh bí đao thịt băm', calories: cLunch, ingredients: ['Cơm', 'Cá điêu hồng', 'Gừng', 'Bí đao', 'Thịt heo']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '2 lát khoai lang luộc + 1 ly nước ép dứa', calories: cSnackPm, ingredients: ['Khoai lang', 'Dứa']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1 bát cơm + 150g sườn non nướng mật ong + salad dầu giấm', calories: cDinner, ingredients: ['Cơm', 'Thịt heo', 'Mật ong', 'Xà lách', 'Dầu giấm']),
          ];
          break;
        default: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Cháo sườn sụn yến mạch + 1 ly sữa hạt sen', calories: cBreakfast, ingredients: ['Yến mạch', 'Thịt heo', 'Hạt sen']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1.5 bát cơm + 150g gà hấp lá chanh + canh cua rau đay', calories: cLunch, ingredients: ['Cơm', 'Thịt gà', 'Lá chanh', 'Cua', 'Rau đay']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '1 cốc thạch rau câu dừa thanh mát', calories: cSnackPm, ingredients: ['Thạch rau câu','Dừa']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1 bát cơm + 150g cá lóc kho tộ + canh chua miền Tây', calories: cDinner, ingredients: ['Cơm', 'Cá lóc', 'Me', 'Cà chua', 'Dứa', 'Giá']),
          ];
          break;
      }
    } else {
      
      final int cBreakfast = (targetCal * 0.25).round();
      final int cLunch = (targetCal * 0.35).round();
      final int cSnackPm = (targetCal * 0.08).round();
      final int cDinner = (targetCal * 0.32).round();

      switch (dayOfWeek) {
        case 0: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: '1 bát cháo yến mạch ức gà xé nhạt + trà xanh ấm', calories: cBreakfast, ingredients: ['Yến mạch', 'Thịt gà', 'Trà xanh']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1 bát cơm gạo lứt + 150g cá rô phi hấp sả + đĩa súp lơ xanh luộc', calories: cLunch, ingredients: ['Cơm gạo lứt', 'Cá rô phi', 'Sả', 'Súp lơ xanh']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '1 quả táo ta chín giòn', calories: cSnackPm, ingredients: ['Táo']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1/2 bát cơm gạo lứt + 150g thịt thăn bò áp chảo + đĩa salad lớn', calories: cDinner, ingredients: ['Cơm gạo lứt', 'Thịt bò', 'Xà lách', 'Cà chua', 'Dưa chuột']),
          ];
          break;
        case 1: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: '2 quả trứng luộc + 1 lát bánh mì đen nhỏ + dưa chuột', calories: cBreakfast, ingredients: ['Trứng gà', 'Bánh mì', 'Dưa chuột']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1 bát cơm gạo lứt + 150g mực hấp lá hành + canh cải thảo thịt băm', calories: cLunch, ingredients: ['Cơm gạo lứt', 'Mực', 'Hành lá', 'Cải thảo', 'Thịt heo']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '1 quả ổi vừa ngọt nhẹ', calories: cSnackPm, ingredients: ['Ổi']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1/2 bát cơm + 150g ức gà nướng nghệ + bông cải luộc', calories: cDinner, ingredients: ['Cơm', 'Thịt gà', 'Nghệ', 'Bông cải xanh']),
          ];
          break;
        case 2: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Khoai lang luộc + 1 cốc sữa đậu nành không đường', calories: cBreakfast, ingredients: ['Khoai lang', 'Đậu nành']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1 bát cơm gạo lứt + 150g tôm hấp sả + đĩa rau muống luộc lớn', calories: cLunch, ingredients: ['Cơm gạo lứt', 'Tôm', 'Sả', 'Rau muống']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '1 hộp sữa chua Hy Lạp không đường', calories: cSnackPm, ingredients: ['Sữa chua']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1/2 bát cơm gạo lứt + 150g cá hồi áp chảo + canh cải thìa canh nhạt', calories: cDinner, ingredients: ['Cơm gạo lứt', 'Cá hồi', 'Cải thìa']),
          ];
          break;
        case 3: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: '1 bát canh bánh đa cua đồng nhiều rau xanh + nước lọc', calories: cBreakfast, ingredients: ['Bánh đa', 'Cua', 'Rau xanh']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1 bát cơm gạo lứt + 150g ức gà xào ớt chuông nấm đông cô', calories: cLunch, ingredients: ['Cơm gạo lứt', 'Thịt gà', 'Ớt chuông', 'Nấm đông cô']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '1 quả lê thanh ngọt nhiều nước', calories: cSnackPm, ingredients: ['Lê']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1/2 bát cơm gạo lứt + 150g đậu hũ hấp trứng thịt băm + xà lách', calories: cDinner, ingredients: ['Cơm gạo lứt', 'Đậu phụ', 'Trứng gà', 'Thịt heo', 'Xà lách']),
          ];
          break;
        case 4: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: '1 bát súp ngô gà nấm thanh đạm + 1 quả chuối nhỏ', calories: cBreakfast, ingredients: ['Ngô ngọt', 'Thịt gà', 'Nấm', 'Chuối']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1 bát cơm gạo lứt + 150g cá lóc nướng giấy bạc + rau muống luộc', calories: cLunch, ingredients: ['Cơm gạo lứt', 'Cá lóc', 'Rau muống']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '1 nắm nhỏ hạt bí ngô rang khô (15g)', calories: cSnackPm, ingredients: ['Hạt bí ngô']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1/2 bát cơm gạo lứt + 150g thịt heo nạc luộc + canh rau ngót nấu tôm băm', calories: cDinner, ingredients: ['Cơm gạo lứt', 'Thịt heo', 'Rau ngót', 'Tôm']),
          ];
          break;
        case 5: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: '1 đĩa bánh cuốn chay ít mỡ hành + 1 quả cam ngọt', calories: cBreakfast, ingredients: ['Bánh cuốn', 'Hành lá', 'Cam']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1 bát cơm gạo lứt + 150g bò xào cần tây tỏi tây', calories: cLunch, ingredients: ['Cơm gạo lứt', 'Thịt bò', 'Cần tây', 'Tỏi tây']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '1 quả bưởi hồng 3 múi mọng nước', calories: cSnackPm, ingredients: ['Bưởi']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1/2 bát cơm gạo lứt + 150g tôm rim đậu phụ + canh bí đao tôm nõn', calories: cDinner, ingredients: ['Cơm gạo lứt', 'Tôm', 'Đậu phụ', 'Bí đao']),
          ];
          break;
        default: 
          list = [
            RecommendedMeal(key: 'breakfast', timeLabel: 'Bữa sáng (07:00)', description: 'Bắp ngô ngọt luộc + 1 cốc sữa đậu đen không đường', calories: cBreakfast, ingredients: ['Bắp', 'Đậu đen']),
            RecommendedMeal(key: 'lunch', timeLabel: 'Bữa trưa (12:00)', description: '1 bát cơm gạo lứt + 150g lườn gà áp chảo sốt chanh leo + măng tây', calories: cLunch, ingredients: ['Cơm gạo lứt', 'Thịt gà', 'Chanh leo', 'Măng tây']),
            RecommendedMeal(key: 'snack_pm', timeLabel: 'Bữa phụ chiều (15:30)', description: '1 hộp thạch rau câu rau má ít đường', calories: cSnackPm, ingredients: ['Thạch rau câu', 'Rau má']),
            RecommendedMeal(key: 'dinner', timeLabel: 'Bữa tối (19:00)', description: '1/2 bát cơm gạo lứt + 150g cá thu rim nước dừa xiêm nhạt + cải xanh', calories: cDinner, ingredients: ['Cơm gạo lứt', 'Cá thu', 'Dừa', 'Cải xanh']),
          ];
          break;
      }
    }
    return list;
  }
}