import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// An office order issued by the institute.
///
/// There is no Firebase Storage on the free Spark plan, so the scanned copy
/// is not a file at all — it's a small photo, base64-encoded directly into
/// the document ([imageBase64]). That only works because it's a photo (a few
/// hundred KB) rather than a multi-page PDF; a Firestore document tops out
/// at ~1 MB. Older orders were published as an external link instead
/// ([pdfUrl]) and still open that way.
class OfficeOrder {
  final String id;

  /// The order's own reference number, as printed on it. This is what people
  /// actually search by, so it is stored verbatim *and* normalised.
  final String orderNo;

  final String title;
  final String? description;

  /// Date printed on the order, which is not the date it was uploaded here.
  final DateTime? orderDate;

  /// Legacy field: a link to where the order already lives (institute site,
  /// Drive share). Null for orders published with an inline photo instead.
  final String? pdfUrl;

  /// Base64-encoded photo of the order. Null for legacy link-based orders.
  final String? imageBase64;

  /// MIME type of [imageBase64], e.g. `image/jpeg`.
  final String? imageMimeType;

  final String postedByUid;
  final String postedByName;
  final DateTime? createdAt;

  // --- the student and fine this order was issued for ---
  //
  // Null only for orders published before this link existed (see
  // ARCHITECTURE.md-style note in fine.dart) — every order created going
  // forward carries all six. Denormalised rather than a bare id so the
  // register and the student's detail page render without a second read.
  final String? studentUid;
  final String? studentName;
  final String? studentRegNo;
  final String? fineId;
  final num? fineAmount;
  final String? fineCategory;

  const OfficeOrder({
    required this.id,
    required this.orderNo,
    required this.title,
    this.description,
    this.orderDate,
    this.pdfUrl,
    this.imageBase64,
    this.imageMimeType,
    required this.postedByUid,
    required this.postedByName,
    this.createdAt,
    this.studentUid,
    this.studentName,
    this.studentRegNo,
    this.fineId,
    this.fineAmount,
    this.fineCategory,
  });

  factory OfficeOrder.fromMap(String id, Map<String, dynamic> m) => OfficeOrder(
    id: id,
    orderNo: m['orderNo'] as String? ?? '',
    title: m['title'] as String? ?? '',
    description: m['description'] as String?,
    orderDate: (m['orderDate'] as Timestamp?)?.toDate(),
    pdfUrl: m['pdfUrl'] as String?,
    imageBase64: m['imageBase64'] as String?,
    imageMimeType: m['imageMimeType'] as String?,
    postedByUid: m['postedByUid'] as String? ?? '',
    postedByName: m['postedByName'] as String? ?? 'Unknown',
    createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    studentUid: m['studentUid'] as String?,
    studentName: m['studentName'] as String?,
    studentRegNo: m['studentRegNo'] as String?,
    fineId: m['fineId'] as String?,
    fineAmount: m['fineAmount'] as num?,
    fineCategory: m['fineCategory'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'orderNo': orderNo,
    'title': title,
    'description': description,
    'orderDate': orderDate == null ? null : Timestamp.fromDate(orderDate!),
    'pdfUrl': pdfUrl,
    'imageBase64': imageBase64,
    'imageMimeType': imageMimeType,
    'postedByUid': postedByUid,
    'postedByName': postedByName,
    'studentUid': studentUid,
    'studentName': studentName,
    'studentRegNo': studentRegNo,
    'fineId': fineId,
    'fineAmount': fineAmount,
    'fineCategory': fineCategory,
  };

  /// False only for orders published before every order required a student —
  /// see the "leave legacy orders unlinked" call in the office-orders restructure.
  bool get hasFine => fineId != null;

  bool get hasImage => imageBase64 != null && imageBase64!.isNotEmpty;

  /// True for the older orders that were published as an external link.
  bool get hasLink => (pdfUrl ?? '').trim().isNotEmpty;

  bool get isPdf => (pdfUrl ?? '').toLowerCase().endsWith('.pdf');

  /// True when this order matches a free-text search of its number or title.
  /// Punctuation is ignored on the number, so "SLIET/HM/2024/17" is found by
  /// typing "hm 2024 17" — nobody remembers the exact slashes.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (title.toLowerCase().contains(q)) return true;
    if (orderNo.toLowerCase().contains(q)) return true;
    if ((studentName ?? '').toLowerCase().contains(q)) return true;
    if ((studentRegNo ?? '').toLowerCase().contains(q)) return true;
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

/// Decoded photo bytes, memoised by order id.
///
/// Without this, a register of forty orders re-runs `base64Decode` on a
/// ~700 KB string for every single one on every rebuild — which is enough to
/// make scrolling stutter. The cache is bounded because a long session
/// browsing hundreds of orders would otherwise grow without limit; anything
/// evicted is simply decoded again next time it is shown.
final Map<String, Uint8List> _decodedImages = {};

Uint8List? decodedOrderImage(OfficeOrder order) {
  if (!order.hasImage) return null;

  final hit = _decodedImages[order.id];
  if (hit != null) return hit;

  try {
    final bytes = base64Decode(order.imageBase64!);
    if (_decodedImages.length >= 40) _decodedImages.clear();
    _decodedImages[order.id] = bytes;
    return bytes;
  } catch (_) {
    // A corrupt or truncated string shouldn't take the whole register down —
    // the row falls back to its placeholder icon.
    return null;
  }
}
