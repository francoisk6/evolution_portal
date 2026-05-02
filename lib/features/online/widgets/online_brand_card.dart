import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../app/app_env.dart';
import '../../../app/app_cache_manager.dart';
import '../../../data/models/online_brand_payload.dart';
import '../../../utils/money_format.dart';

class OnlineBrandCard extends StatelessWidget {
  final OnlineBrand brand;
  final String mainLogoUrl;
  final String subdetailLabel;
  final String? overridePriceRaw;
  final String? overridePriceCurrency;
  final bool selected;
  final VoidCallback? onTap;

  const OnlineBrandCard({
    super.key,
    required this.brand,
    required this.mainLogoUrl,
    required this.subdetailLabel,
    this.overridePriceRaw,
    this.overridePriceCurrency,
    required this.selected,
    required this.onTap,
  });

  String _mediaUrl(String avatar) {
    // API returns "/media/..." → make absolute using base (…/api/ → /)
    final root = AppEnv.base.replaceFirst(RegExp(r'/api/?$'), '/');
    if (avatar.isEmpty) return '';
    if (avatar.startsWith('http')) return avatar;
    return '$root${avatar.replaceFirst(RegExp(r'^/'), '')}';
  }

  @override
  Widget build(BuildContext context) {
    final title = (brand.displayTitle.isNotEmpty
            ? brand.displayTitle
            : (brand.displayName.isNotEmpty
                ? brand.displayName
                : (brand.alt.isNotEmpty ? brand.alt : brand.name)))
        .trim();

    final logoUrl =
        _mediaUrl(mainLogoUrl.isNotEmpty ? mainLogoUrl : brand.avatar);
    final logo2Url =
        _mediaUrl(brand.logo2Url.isNotEmpty ? brand.logo2Url : brand.logo2);


    final rawPrice = (overridePriceRaw?.trim().isNotEmpty == true)
        ? overridePriceRaw!.trim()
        : brand.customerPrice.trim();

    final priceCur = (overridePriceCurrency?.trim().isNotEmpty == true)
        ? overridePriceCurrency!.trim()
        : (brand.customerPriceCurrency.trim().isNotEmpty
                ? brand.customerPriceCurrency
                : brand.currency)
            .trim();

    // Some provider-driven overrides (e.g. Ogero bills) return a pre-formatted
    // amount string that already includes the currency (e.g. "380,000 LBP").
    // In that case, appending currency again would render "... LBP LBP".
    final rawUpper = rawPrice.toUpperCase();
    final rawAlreadyHasCurrency = rawUpper.contains(RegExp(r'\b(LBP|USD)\b'));

    final priceVal = MoneyFormat.tryParse(rawPrice);
    final leftPrice = rawAlreadyHasCurrency
        ? rawPrice
        : (priceVal == null || priceCur.isEmpty)
            ? '$rawPrice $priceCur'.trim()
            : '${MoneyFormat.format(priceVal, currencyCode: priceCur)} $priceCur';
    final unitLabel = brand.unit.trim();
    final unitValue = brand.unitValue.trim();

    final subtitle =
        (brand.description.isNotEmpty ? brand.description : subdetailLabel)
            .trim();
    // IMPORTANT: If details is empty, do NOT fall back to name/alt/product.
    // Keep it empty.
    final detailLine = brand.details.trim();

    final fg = _parseHexColor(brand.cardTheme?.fontColor) ?? Colors.white;
    final subFg = fg.withValues(alpha: .92);
    final mutedFg = fg.withValues(alpha: .80);
    final cardGradient = _gradientFromTheme(brand.cardTheme) ??
        const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0A8AA0),
            Color(0xFF18A8BC),
          ],
        );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.all(3), // 3px selection gap
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          width: 2,
          color: selected ? const Color(0xFFDC3545) : Colors.transparent,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            constraints: const BoxConstraints(minHeight: 140),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 40,
                  offset: Offset(0, 14),
                  color: Color.fromRGBO(0, 0, 0, .18),
                ),
              ],
              gradient: cardGradient,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _LogoStack(
                      logoUrl: logoUrl,
                      logo2Url: logo2Url,
                      fallbackText: _fallbackText(title),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: fg,
                          letterSpacing: .2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: subFg,
                    letterSpacing: .2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  detailLine,
                  textAlign: TextAlign.left,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: mutedFg,
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      leftPrice,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: fg,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          unitValue,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: fg,
                            letterSpacing: .2,
                          ),
                        ),
                        if (unitLabel.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              unitLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: fg,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fallbackText(String s) {
    final t = s.trim();
    if (t.isEmpty) return '?';
    return t.characters.first.toUpperCase();
  }
}

Color? _parseHexColor(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return null;

  String hex = s;
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.startsWith('0x')) hex = hex.substring(2);

  // Support RGB, RRGGBB, AARRGGBB
  if (hex.length == 3) {
    hex = '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}';
  }
  if (hex.length == 6) {
    hex = 'FF$hex';
  }
  if (hex.length != 8) return null;

  final v = int.tryParse(hex, radix: 16);
  if (v == null) return null;
  return Color(v);
}

LinearGradient? _gradientFromTheme(OnlineCardTheme? theme) {
  if (theme == null) return null;

  final from = _parseHexColor(theme.colorFrom);
  final mid = _parseHexColor(theme.colorMid);
  final to = _parseHexColor(theme.colorTo);

  // Require at least one color
  if (from == null && to == null && mid == null) return null;

  // Build colors list (must be >= 2)
  final colors = <Color>[];
  if (from != null) colors.add(from);
  if (theme.themeType.toLowerCase() == 'triple' && mid != null) colors.add(mid);
  if (to != null) colors.add(to);

  if (colors.isEmpty) return null;
  if (colors.length == 1) colors.add(colors.first);

  // CSS-style angle: 0deg=up, 90deg=right. Screen coords: +y down.
  final rad = (theme.angleDeg.toDouble()) * math.pi / 180.0;
  final dx = math.sin(rad);
  final dy = -math.cos(rad);

  return LinearGradient(
    begin: Alignment(-dx, -dy),
    end: Alignment(dx, dy),
    colors: colors,
  );
}

class _LogoStack extends StatelessWidget {
  final String logoUrl;
  final String logo2Url;
  final String fallbackText;

  const _LogoStack({
    required this.logoUrl,
    required this.logo2Url,
    required this.fallbackText,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 56,
              height: 56,
              color: const Color.fromRGBO(255, 255, 255, .10),
              child: logoUrl.isEmpty
                  ? Center(
                      child: Text(
                        fallbackText,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color.fromRGBO(255, 255, 255, .85),
                        ),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: logoUrl,
                      cacheManager: AppCacheManager.images,
                      fit: BoxFit.contain,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder: (context, _) => const SizedBox.shrink(),
                      errorWidget: (context, _, __) => Center(
                        child: Text(
                          fallbackText,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Color.fromRGBO(255, 255, 255, .85),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          if (logo2Url.isNotEmpty)
            Positioned(
              top: -6,
              right: -6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: logo2Url,
                  cacheManager: AppCacheManager.images,
                  width: 34,
                  fit: BoxFit.contain,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholder: (context, _) => const SizedBox.shrink(),
                  errorWidget: (context, _, __) => const SizedBox.shrink(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
