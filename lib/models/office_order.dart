import 'package:cloud_firestore/cloud_firestore.dart';

/// An office order issued by the institute.
///
/// The PDF itself is not stored here — [pdfUrl] points at wherever it already
/// lives (the institute site, a Drive share). That keeps the project on the
/// free Firebase plan, and office orders are usually published somewhere
/// public anyway, so re-hosting them would just create a second copy to keep
/// in step.
class OfficeOrder {
  final String id;

  /// The order's own reference number, as printed on it. This is what people
  /// actually search by, so it is stored verbatim *and* normalised.
  final String orderNo;

  final String title;
  final String? description;

  /// Date printed on the order, which is not the date it was uploaded here.
  final DateTime? orderDate;

  final String pdfUrl;

  final String postedByUid;
  final String postedByName;
  final DateTime? createdAt;

  const OfficeOrder({
    required this.id,
    required this.orderNo,
    required this.title,
    this.description,
    this.orderDate,
    required this.pdfUrl,
    required this.postedByUid,
    required this.postedByName,
    this.createdAt,
  });

  factory OfficeOrder.fromMap(String id, Map<String, dynamic> m) => OfficeOrder(
    id: id,
    orderNo: m['orderNo'] as String? ?? '',
    title: m['title'] as String? ?? '',
    description: m['description'] as String?,
    orderDate: (m['orderDate'] as Timestamp?)?.toDate(),
    pdfUrl: m['pdfUrl'] as String? ?? '',
    postedByUid: m['postedByUid'] as String? ?? '',
    postedByName: m['postedByName'] as String? ?? 'Unknown',
    createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
  );

  Map<String, dynamic> toMap() => {
    'orderNo': orderNo,
    'title': title,
    'description': description,
    'orderDate': orderDate == null ? null : Timestamp.fromDate(orderDate!),
    'pdfUrl': pdfUrl,
    'postedByUid': postedByUid,
    'postedByName': postedByName,
  };

  bool get isPdf => pdfUrl.toLowerCase().endsWith('.pdf');

  /// True when this order matches a free-text search of its number or title.
  /// Punctuation is ignored on the number, so "SLIET/HM/2024/17" is found by
  /// typing "hm 2024 17" — nobody remembers the exact slashes.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (title.toLowerCase().contains(q)) return true;
    if (orderNo.toLowerCase().contains(q)) return true;
    return _loose(orderNo).contains(_loose(q));
  }

  static String _loose(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// "17 Mar 2026", or null when no date was recorded.
  String? get dateLabel {
    final d = orderDate;
    if (d == null) return null;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  /// True when [orderDate] falls on the same calendar day as [day].
  bool isOn(DateTime day) {
    final d = orderDate;
    if (d == null) return false;
    return d.year == day.year && d.month == day.month && d.day == day.day;
  }
}
