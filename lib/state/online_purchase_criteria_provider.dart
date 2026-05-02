import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds criteria_info used for the order GET/POST endpoints.
///
/// Examples:
/// - CableVision (CV) criteria: full_name, cv_master, cv_quantity, selected options, etc.
/// - Customer-info provider tokens returned by /api/online/customer-info/
final onlinePurchaseCriteriaProvider =
    StateProvider<Map<String, dynamic>?>((ref) => null);
