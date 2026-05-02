import 'package:flutter_riverpod/flutter_riverpod.dart';

class OnlineBrandSelection {
  final int brandId;
  final int subdetailId;

  const OnlineBrandSelection({
    required this.brandId,
    required this.subdetailId,
  });
}

/// Stateless mobile flow requirement:
/// Store `brand_id + subdetail_id` locally and send later to the order endpoint.
final onlineBrandSelectionProvider =
    StateProvider<OnlineBrandSelection?>((ref) => null);
