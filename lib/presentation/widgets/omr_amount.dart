import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/formatters/omr_currency.dart';

const String _omrSymbolAsset = 'assets/currency/omr_symbol_medium.png';
const String _omrSymbolWhiteAsset =
    'assets/currency/omr_symbol_medium_white.png';

/// The official Central Bank of Oman rial mark is a raster PNG, so it cannot
/// carry a [FontWeight]. To read at the same visual weight as bold amounts we
/// thicken the monochrome silhouette with a morphological dilation, which grows
/// the strokes uniformly without offset blur, without rescaling the glyph, and
/// without altering its proportions. The radius scales with the symbol height
/// so bolding stays proportional at every font size.
double _omrBoldDilationRadius(double height) =>
    (height * 0.045).clamp(0.4, 1.1);

class OmrSymbol extends StatelessWidget {
  const OmrSymbol({
    super.key,
    this.height,
    this.color,
    this.useWhiteAsset = false,
    this.bold = true,
  });

  final double? height;
  final Color? color;
  final bool useWhiteAsset;

  /// Renders the mark at a heavier visual weight. Defaults to `true` so every
  /// currency surface driven by this central widget shows a bold rial symbol.
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final effectiveHeight = height ?? 18;
    final effectiveColor = color ?? DefaultTextStyle.of(context).style.color;
    Widget symbol = Image.asset(
      useWhiteAsset ? _omrSymbolWhiteAsset : _omrSymbolAsset,
      height: effectiveHeight,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
    );
    final needsTint = effectiveColor != null &&
        effectiveColor != Colors.black &&
        !(useWhiteAsset && effectiveColor == Colors.white);
    if (needsTint) {
      symbol = ColorFiltered(
        colorFilter: ColorFilter.mode(effectiveColor, BlendMode.srcIn),
        child: symbol,
      );
    }
    if (bold) {
      final radius = _omrBoldDilationRadius(effectiveHeight);
      symbol = ImageFiltered(
        imageFilter: ui.ImageFilter.dilate(radiusX: radius, radiusY: radius),
        child: symbol,
      );
    }
    return symbol;
  }
}

/// Renders the official CBO sign immediately to the left of a three-decimal
/// rial value. The underlying amount remains an integer number of baisa.
class OmrAmount extends StatelessWidget {
  const OmrAmount({
    super.key,
    required this.amountBaisa,
    this.style,
    this.useWhiteSymbol = false,
  });

  final int amountBaisa;
  final TextStyle? style;
  final bool useWhiteSymbol;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    final fontSize = effectiveStyle.fontSize ?? 14;
    final number = formatOmaniRialNumber(amountBaisa);
    return Semantics(
      label: '$number ريال عُماني',
      excludeSemantics: true,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            OmrSymbol(
              height: fontSize,
              color: effectiveStyle.color,
              useWhiteAsset: useWhiteSymbol,
            ),
            Text(number, style: effectiveStyle),
          ],
        ),
      ),
    );
  }
}

class LabeledOmrAmount extends StatelessWidget {
  const LabeledOmrAmount({
    super.key,
    required this.label,
    required this.amountBaisa,
    this.trailingText,
    this.style,
  });

  final String label;
  final int amountBaisa;
  final String? trailingText;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(label, style: style),
          OmrAmount(amountBaisa: amountBaisa, style: style),
          if (trailingText != null) Text(trailingText!, style: style),
        ],
      );
}

class OmrAmountPairLine extends StatelessWidget {
  const OmrAmountPairLine({
    super.key,
    required this.firstLabel,
    required this.firstAmountBaisa,
    required this.secondLabel,
    required this.secondAmountBaisa,
    this.trailingText,
    this.style,
  });

  final String firstLabel;
  final int firstAmountBaisa;
  final String secondLabel;
  final int secondAmountBaisa;
  final String? trailingText;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 4,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(firstLabel, style: style),
          OmrAmount(amountBaisa: firstAmountBaisa, style: style),
          const Text('•'),
          Text(secondLabel, style: style),
          OmrAmount(amountBaisa: secondAmountBaisa, style: style),
          if (trailingText != null) Text(trailingText!, style: style),
        ],
      );
}

InputDecoration omrAmountInputDecoration({
  required String labelText,
  String? helperText,
  String? hintText,
}) =>
    InputDecoration(
      labelText: labelText,
      helperText: helperText,
      hintText: hintText,
      prefixIcon: const Padding(
        padding: EdgeInsets.all(14),
        child: OmrSymbol(height: 20),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    );
