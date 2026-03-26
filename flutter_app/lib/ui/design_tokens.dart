import 'dart:math' as math;

import 'package:flutter/material.dart';

// Color tokens
class AppColors {
  static const Color cream = Color(0xFFFFFAF3);
  static const Color creamSoft = Color(0xFFFFF5EA);
  static const Color creamDeep = Color(0xFFF7EBDC);
  static const Color paper = Color(0xFFFFFEFB);
  static const Color lavender = Color(0xFFCDBDFF);
  static const Color lavenderDeep = Color(0xFFA78BFA);
  static const Color pink = Color(0xFFFFC7DE);
  static const Color pinkDeep = Color(0xFFF29BC2);
  static const Color sky = Color(0xFFDFF1FF);
  static const Color butter = Color(0xFFFFF2BB);
  static const Color mint = Color(0xFFDDF5E8);
  static const Color ink = Color(0xFF5B536F);
  static const Color inkSoft = Color(0xFF81789A);
  static const Color plum = Color(0xFF7C6E9F);
  static const Color stitch = Color(0xFFE8DBF5);
  static const Color border = Color(0xFFF0DEEF);
  static const Color shadow = Color(0x1FB793C7);
}

// Radius scale
class AppRadii {
  static const double xs = 14;
  static const double sm = 20;
  static const double md = 28;
  static const double lg = 36;
  static const double xl = 44;
  static const double pill = 999;
}

// Shadow style
class AppShadows {
  static const List<BoxShadow> plush = <BoxShadow>[
    BoxShadow(color: AppColors.shadow, blurRadius: 28, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x14FFFFFF), blurRadius: 2, offset: Offset(0, -1)),
  ];

  static const List<BoxShadow> floating = <BoxShadow>[
    BoxShadow(color: Color(0x18C9A5D1), blurRadius: 20, offset: Offset(0, 8)),
  ];
}

// Typography hierarchy + button/input/card styles are consumed by the app theme.
ThemeData buildFamilyTheme({
  required TextTheme textTheme,
  required String fontFamily,
  required List<String> fontFallback,
}) {
  final roundedShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadii.md),
  );

  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.lavenderDeep,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.lavenderDeep,
        secondary: AppColors.pinkDeep,
        surface: AppColors.paper,
      );

  final themedText = _withAppFontFallback(
    textTheme.copyWith(
      headlineLarge: textTheme.headlineLarge?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineMedium: textTheme.headlineMedium?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w800,
      ),
      titleLarge: textTheme.titleLarge?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w800,
      ),
      titleMedium: textTheme.titleMedium?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: textTheme.bodyLarge?.copyWith(
        color: AppColors.ink,
        height: 1.45,
      ),
      bodyMedium: textTheme.bodyMedium?.copyWith(
        color: AppColors.inkSoft,
        height: 1.4,
      ),
      labelLarge: textTheme.labelLarge?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w800,
      ),
      labelMedium: textTheme.labelMedium?.copyWith(
        color: AppColors.inkSoft,
        fontWeight: FontWeight.w700,
      ),
    ),
    fontFamily: fontFamily,
    fontFallback: fontFallback,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: fontFamily,
    textTheme: themedText,
    primaryTextTheme: themedText,
    scaffoldBackgroundColor: AppColors.cream,
    splashFactory: InkSparkle.splashFactory,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: themedText.bodyMedium?.copyWith(color: AppColors.paper),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
    ),
    iconTheme: const IconThemeData(color: AppColors.plum, size: 22),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: Colors.transparent,
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: roundedShape,
    ),
    dividerColor: AppColors.border,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        backgroundColor: AppColors.lavenderDeep,
        foregroundColor: AppColors.paper,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        textStyle: themedText.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.plum,
        side: const BorderSide(color: AppColors.border, width: 1.4),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        textStyle: themedText.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.plum,
        textStyle: themedText.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.paper,
      hintStyle: themedText.bodyMedium?.copyWith(
        color: AppColors.inkSoft.withValues(alpha: 0.72),
      ),
      labelStyle: themedText.labelMedium?.copyWith(color: AppColors.plum),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: _inputBorder(AppColors.border),
      enabledBorder: _inputBorder(AppColors.border),
      focusedBorder: _inputBorder(AppColors.lavenderDeep),
      errorBorder: _inputBorder(const Color(0xFFE6A3BA)),
      focusedErrorBorder: _inputBorder(const Color(0xFFE08CB0)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      side: const BorderSide(color: AppColors.border),
      backgroundColor: AppColors.paper,
      selectedColor: AppColors.pink,
      secondarySelectedColor: AppColors.pink,
      labelStyle: themedText.labelMedium ?? const TextStyle(),
      secondaryLabelStyle:
          themedText.labelMedium?.copyWith(color: AppColors.ink) ??
          const TextStyle(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      width: 360,
    ),
  );
}

InputBorder _inputBorder(Color color) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadii.md),
    borderSide: BorderSide(color: color, width: 1.4),
  );
}

TextTheme _withAppFontFallback(
  TextTheme textTheme, {
  required String fontFamily,
  required List<String> fontFallback,
}) {
  return textTheme.copyWith(
    displayLarge: _withFontFallback(
      textTheme.displayLarge,
      fontFamily: fontFamily,
      fontFallback: fontFallback,
    ),
    displayMedium: _withFontFallback(
      textTheme.displayMedium,
      fontFamily: fontFamily,
      fontFallback: fontFallback,
    ),
    displaySmall: _withFontFallback(
      textTheme.displaySmall,
      fontFamily: fontFamily,
      fontFallback: fontFallback,
    ),
    headlineLarge: _withFontFallback(
      textTheme.headlineLarge,
      fontFamily: fontFamily,
      fontFallback: fontFallback,
    ),
    headlineMedium: _withFontFallback(
      textTheme.headlineMedium,
      fontFamily: fontFamily,
      fontFallback: fontFallback,
    ),
    headlineSmall: _withFontFallback(
      textTheme.headlineSmall,
      fontFamily: fontFamily,
      fontFallback: fontFallback,
    ),
    titleLarge: _withFontFallback(
      textTheme.titleLarge,
      fontFamily: fontFamily,
      fontFallback: fontFallback,
    ),
    titleMedium: _withFontFallback(
      textTheme.titleMedium,
      fontFamily: fontFamily,
      fontFallback: fontFallback,
    ),
    titleSmall: _withFontFallback(
      textTheme.titleSmall,
      fontFamily: fontFamily,
      fontFallback: fontFallback,
    ),
    bodyLarge: _withFontFallback(
      textTheme.bodyLarge,
      fontFamily: fontFamily,
      fontFallback: fontFallback,
    ),
    bodyMedium: _withFontFallback(
      textTheme.bodyMedium,
      fontFamily: fontFamily,
      fontFallback: fontFallback,
    ),
    bodySmall: _withFontFallback(
      textTheme.bodySmall,
      fontFamily: fontFamily,
      fontFallback: fontFallback,
    ),
    labelLarge: _withFontFallback(
      textTheme.labelLarge,
      fontFamily: fontFamily,
      fontFallback: fontFallback,
    ),
    labelMedium: _withFontFallback(
      textTheme.labelMedium,
      fontFamily: fontFamily,
      fontFallback: fontFallback,
    ),
    labelSmall: _withFontFallback(
      textTheme.labelSmall,
      fontFamily: fontFamily,
      fontFallback: fontFallback,
    ),
  );
}

TextStyle? _withFontFallback(
  TextStyle? style, {
  required String fontFamily,
  required List<String> fontFallback,
}) {
  return style?.copyWith(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
  );
}

// Decorative background
class CozyBackdrop extends StatelessWidget {
  const CozyBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            AppColors.cream,
            AppColors.creamSoft,
            Color(0xFFFFF8F1),
          ],
        ),
      ),
      child: Stack(
        children: <Widget>[
          const Positioned(
            top: -24,
            left: -12,
            child: _PastelBlob(width: 160, height: 120, color: AppColors.pink),
          ),
          const Positioned(
            top: 72,
            right: -30,
            child: _PastelBlob(width: 180, height: 140, color: AppColors.sky),
          ),
          const Positioned(
            bottom: -30,
            left: 32,
            child: _PastelBlob(
              width: 150,
              height: 120,
              color: AppColors.butter,
            ),
          ),
          const Positioned(bottom: 84, right: 24, child: _SparkleCluster()),
          child,
        ],
      ),
    );
  }
}

class _PastelBlob extends StatelessWidget {
  const _PastelBlob({
    required this.width,
    required this.height,
    required this.color,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(AppRadii.xl),
          boxShadow: AppShadows.floating,
        ),
      ),
    );
  }
}

class _SparkleCluster extends StatelessWidget {
  const _SparkleCluster();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: const <Widget>[
          Icon(Icons.auto_awesome_rounded, size: 26, color: AppColors.pinkDeep),
          SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.favorite_rounded,
                size: 18,
                color: AppColors.lavenderDeep,
              ),
              SizedBox(width: 8),
              Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.plum),
            ],
          ),
        ],
      ),
    );
  }
}

// Card style
class StitchedPanel extends StatelessWidget {
  const StitchedPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = AppColors.paper,
    this.borderColor = AppColors.stitch,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadii.md)),
    this.shadows = AppShadows.plush,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;
  final BorderRadius borderRadius;
  final List<BoxShadow> shadows;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StitchedBorderPainter(
        color: borderColor,
        borderRadius: borderRadius,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: borderRadius,
          border: Border.all(
            color: borderColor.withValues(alpha: 0.42),
            width: 1.2,
          ),
          boxShadow: shadows,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _StitchedBorderPainter extends CustomPainter {
  const _StitchedBorderPainter({
    required this.color,
    required this.borderRadius,
  });

  final Color color;
  final BorderRadius borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = borderRadius.toRRect(Offset.zero & size).deflate(8);
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    final paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final metric in metrics) {
      var distance = 0.0;
      const dash = 6.0;
      const gap = 8.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        final segment = metric.extractPath(distance, next);
        canvas.drawPath(segment, paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_StitchedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.borderRadius != borderRadius;
  }
}

// Icon usage + small decorative chips
class CuteTag extends StatelessWidget {
  const CuteTag({
    super.key,
    required this.label,
    this.color = AppColors.pink,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.82),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 16, color: AppColors.plum),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
