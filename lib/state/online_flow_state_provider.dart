import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/online_customer_info.dart';
import '../data/models/online_cv_receiver_info.dart';

class OnlineCvPricingFlowState {
  final int subdetailId;
  final String receiverNumber;
  final String resolvedReceiverNumber;
  final String masterSerial;
  final String customerName;
  final int? days;
  final Map<int, bool> selectedOptions;
  final int slaveCount;
  final List<String> slaveSerials;
  final String? lookupError;
  final OnlineCvReceiverInfo? lookupInfo;

  const OnlineCvPricingFlowState({
    required this.subdetailId,
    required this.receiverNumber,
    required this.resolvedReceiverNumber,
    required this.masterSerial,
    required this.customerName,
    required this.days,
    required this.selectedOptions,
    required this.slaveCount,
    required this.slaveSerials,
    required this.lookupError,
    required this.lookupInfo,
  });

  OnlineCvPricingFlowState copyWith({
    int? subdetailId,
    String? receiverNumber,
    String? resolvedReceiverNumber,
    String? masterSerial,
    String? customerName,
    int? days,
    bool clearDays = false,
    Map<int, bool>? selectedOptions,
    int? slaveCount,
    List<String>? slaveSerials,
    String? lookupError,
    bool clearLookupError = false,
    OnlineCvReceiverInfo? lookupInfo,
    bool clearLookupInfo = false,
  }) {
    return OnlineCvPricingFlowState(
      subdetailId: subdetailId ?? this.subdetailId,
      receiverNumber: receiverNumber ?? this.receiverNumber,
      resolvedReceiverNumber:
          resolvedReceiverNumber ?? this.resolvedReceiverNumber,
      masterSerial: masterSerial ?? this.masterSerial,
      customerName: customerName ?? this.customerName,
      days: clearDays ? null : (days ?? this.days),
      selectedOptions: selectedOptions ?? this.selectedOptions,
      slaveCount: slaveCount ?? this.slaveCount,
      slaveSerials: slaveSerials ?? this.slaveSerials,
      lookupError:
          clearLookupError ? null : (lookupError ?? this.lookupError),
      lookupInfo: clearLookupInfo ? null : (lookupInfo ?? this.lookupInfo),
    );
  }
}

class OnlineBrandFlowState {
  final String routeKey;
  final int selectedGsd;
  final String searchText;
  final String accountText;
  final double pageScrollOffset;
  final double tabsScrollOffset;
  final bool didFetchCustomerInfo;
  final String? customerInfoCurrency;
  final OnlineCustomerInfoResponse? customerInfoResponse;
  final String? customerInfoError;
  final OnlineCvPricingFlowState? cvPricingState;

  const OnlineBrandFlowState({
    required this.routeKey,
    required this.selectedGsd,
    required this.searchText,
    required this.accountText,
    required this.pageScrollOffset,
    required this.tabsScrollOffset,
    required this.didFetchCustomerInfo,
    required this.customerInfoCurrency,
    required this.customerInfoResponse,
    required this.customerInfoError,
    required this.cvPricingState,
  });

  OnlineBrandFlowState copyWith({
    String? routeKey,
    int? selectedGsd,
    String? searchText,
    String? accountText,
    double? pageScrollOffset,
    double? tabsScrollOffset,
    bool? didFetchCustomerInfo,
    String? customerInfoCurrency,
    bool clearCustomerInfoCurrency = false,
    OnlineCustomerInfoResponse? customerInfoResponse,
    bool clearCustomerInfoResponse = false,
    String? customerInfoError,
    bool clearCustomerInfoError = false,
    OnlineCvPricingFlowState? cvPricingState,
    bool clearCvPricingState = false,
  }) {
    return OnlineBrandFlowState(
      routeKey: routeKey ?? this.routeKey,
      selectedGsd: selectedGsd ?? this.selectedGsd,
      searchText: searchText ?? this.searchText,
      accountText: accountText ?? this.accountText,
      pageScrollOffset: pageScrollOffset ?? this.pageScrollOffset,
      tabsScrollOffset: tabsScrollOffset ?? this.tabsScrollOffset,
      didFetchCustomerInfo:
          didFetchCustomerInfo ?? this.didFetchCustomerInfo,
      customerInfoCurrency: clearCustomerInfoCurrency
          ? null
          : (customerInfoCurrency ?? this.customerInfoCurrency),
      customerInfoResponse: clearCustomerInfoResponse
          ? null
          : (customerInfoResponse ?? this.customerInfoResponse),
      customerInfoError: clearCustomerInfoError
          ? null
          : (customerInfoError ?? this.customerInfoError),
      cvPricingState: clearCvPricingState
          ? null
          : (cvPricingState ?? this.cvPricingState),
    );
  }
}

class OnlinePurchaseFlowState {
  final String selectionKey;
  final String pin;
  final String fullName;
  final int quantity;
  final bool showPriceDetails;
  final Map<String, String> params;
  final Map<String, dynamic>? criteriaInfo;
  final double pageScrollOffset;

  const OnlinePurchaseFlowState({
    required this.selectionKey,
    required this.pin,
    required this.fullName,
    required this.quantity,
    required this.showPriceDetails,
    required this.params,
    required this.criteriaInfo,
    required this.pageScrollOffset,
  });
}

class OnlineFlowState {
  final OnlineBrandFlowState? brand;
  final OnlinePurchaseFlowState? purchase;

  const OnlineFlowState({this.brand, this.purchase});

  OnlineFlowState copyWith({
    OnlineBrandFlowState? brand,
    OnlinePurchaseFlowState? purchase,
    bool clearBrand = false,
    bool clearPurchase = false,
  }) {
    return OnlineFlowState(
      brand: clearBrand ? null : (brand ?? this.brand),
      purchase: clearPurchase ? null : (purchase ?? this.purchase),
    );
  }
}

class OnlineFlowNotifier extends StateNotifier<OnlineFlowState> {
  OnlineFlowNotifier() : super(const OnlineFlowState());

  void saveBrand(OnlineBrandFlowState value) {
    state = state.copyWith(brand: value);
  }

  void updateBrandCvPricing({
    required String routeKey,
    required OnlineCvPricingFlowState? value,
  }) {
    final current = state.brand;
    if (current == null || current.routeKey != routeKey) return;
    state = state.copyWith(
      brand: current.copyWith(
        cvPricingState: value,
        clearCvPricingState: value == null,
      ),
    );
  }

  void savePurchase(OnlinePurchaseFlowState value) {
    state = state.copyWith(purchase: value);
  }

  void clearBrand() {
    state = state.copyWith(clearBrand: true);
  }

  void clearPurchase() {
    state = state.copyWith(clearPurchase: true);
  }

  void resetAll() {
    state = const OnlineFlowState();
  }
}

final onlineFlowProvider =
    StateNotifierProvider<OnlineFlowNotifier, OnlineFlowState>(
  (ref) => OnlineFlowNotifier(),
);
