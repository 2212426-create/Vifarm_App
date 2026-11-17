/// Utility class cho xử lý chuỗi tiếng Việt và tìm kiếm
class TextUtils {
  TextUtils._();

  /// Chuẩn hóa từ khóa: xóa dấu tiếng Việt, chuyển chữ thường, xóa khoảng trắng thừa
  static String removeDiacritics(String str) {
    if (str.isEmpty) return '';

    // Một lượt duyệt qua bảng tra dựng sẵn (trước đây ~130 lần replaceAll mỗi chuỗi,
    // mỗi lần tạo một chuỗi mới; hàm này chạy cho từng sản phẩm/video khi lọc, tìm kiếm).
    final units = str.trim().toLowerCase().codeUnits;
    final out = List<int>.filled(units.length, 0);
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      out[i] = _diacriticMap[unit] ?? unit;
    }

    return String.fromCharCodes(out).replaceAll(_whitespace, ' ');
  }

  static final RegExp _whitespace = RegExp(r'\s+');

  /// Bảng tra ký tự có dấu -> ký tự gốc, dựng một lần từ [_vietnameseGroups].
  static final Map<int, int> _diacriticMap = () {
    final map = <int, int>{};
    for (final group in _vietnameseGroups) {
      final target = group.codeUnitAt(0);
      for (final unit in group.substring(1).codeUnits) {
        map[unit] = target;
      }
    }
    return map;
  }();

  static const _vietnameseGroups = [
    'aáàảãạăắằẳẵặâấầẩẫậ',
    'AÁÀẢÃẠĂẮẰẲẴẶÂẤẦẨẪẬ',
    'dđ',
    'DĐ',
    'eéèẻẽẹêếềểễệ',
    'EÉÈẺẼẸÊẾỀỂỄỆ',
    'iíìỉĩị',
    'IÍÌỈĨỊ',
    'oóòỏõọôốồổỗộơớờởỡợ',
    'OÓÒỎÕỌÔỐỒỔỖỘƠỚỜỞỠỢ',
    'uúùủũụưứừửữự',
    'UÚÙỦŨỤƯỨỪỬỮỰ',
    'yýỳỷỹỵ',
    'YÝỲỶỸỴ',
  ];

  /// Chuẩn hóa hashtag (bỏ dấu #, xóa khoảng trắng, chữ thường)
  static String normalizeHashtag(String tag) {
    final clean = tag.trim().replaceAll('#', '');
    return removeDiacritics(clean);
  }
}
