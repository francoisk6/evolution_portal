import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/online_customer_info.dart';

class OnlineCustomerInfoState {
  final String accountNumber;
  final int groupSubdetailId;
  final OnlineCustomerInfoResponse response;

  const OnlineCustomerInfoState({
    required this.accountNumber,
    required this.groupSubdetailId,
    required this.response,
  });
}

/// Holds the latest successful customer-info lookup (per session) so the next
/// step (order page) can reuse the provider tokens/amounts without re-calling
/// the API.
final onlineCustomerInfoProvider =
    StateProvider<OnlineCustomerInfoState?>((ref) => null);
