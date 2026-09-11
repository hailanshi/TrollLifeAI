// TrollLifeAI 主题定义：简约暗色文字模拟器风格。
//
// 全工程只在这里定义颜色常量与 ThemeData，
// 页面中一律引用 AppColors / AppTheme，避免散落的魔法色值。

import 'package:flutter/material.dart';

/// 全局配色常量（暗色文字模拟器风格）
class AppColors {
  const AppColors._();

  /// 页面底色：近黑的冷灰
  static const Color background = Color(0xFF0D0F12);

  /// 卡片 / 面板底色
  static const Color surface = Color(0xFF14171D);

  /// 卡片上的次级面板底色（列表条目、输入框）
  static const Color surfaceAlt = Color(0xFF1B1F27);

  /// 分隔线
  static const Color divider = Color(0xFF262B35);

  /// 正文色
  static const Color text = Color(0xFFD8DEE9);

  /// 次级文字（说明、时间戳）
  static const Color textDim = Color(0xFF8B95A6);

  /// 主色（深绿）
  static const Color primary = Color(0xFF2B8C68);

  /// 主色亮色（高亮数字、强调）
  static const Color primaryLight = Color(0xFF7FD1AE);

  /// 危险 / 负向变化
  static const Color danger = Color(0xFFE06C75);

  /// 警告 / 成瘾、罪恶
  static const Color warning = Color(0xFFE5C07B);

  /// 正向变化
  static const Color success = Color(0xFF7FD1AE);

  /// 稀有 / 天赋
  static const Color epic = Color(0xFFC678DD);
}

/// 主题构建器
class AppTheme {
  const AppTheme._();

  /// 主 ThemeData：暗色，圆角克制，字体层级清晰
  static ThemeData get dark {
    const ColorScheme scheme = ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.primaryLight,
      onSecondary: AppColors.background,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      error: AppColors.danger,
      onError: Colors.white,
    );

    final TextTheme textTheme = _buildTextTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      dividerColor: AppColors.divider,
      splashFactory: InkRipple.splashFactory,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.text,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
        iconTheme: IconThemeData(color: AppColors.text),
      ),
      cardTheme: CardTheme(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.divider),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      // 主按钮：实心墨绿
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.surfaceAlt,
          disabledForegroundColor: AppColors.textDim,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      // 次按钮：描边
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryLight,
          side: const BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryLight,
          textStyle: const TextStyle(fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceAlt,
        hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 14),
        labelStyle: const TextStyle(color: AppColors.textDim, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceAlt,
        selectedColor: AppColors.primary,
        side: const BorderSide(color: AppColors.divider),
        labelStyle: const TextStyle(color: AppColors.text, fontSize: 13),
        secondaryLabelStyle:
            const TextStyle(color: Colors.white, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.divider),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surfaceAlt,
        contentTextStyle: TextStyle(color: AppColors.text, fontSize: 14),
        behavior: SnackBarBehavior.floating,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.primary,
        thumbColor: AppColors.primaryLight,
        inactiveTrackColor: AppColors.divider,
        valueIndicatorColor: AppColors.primary,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primaryLight,
        linearTrackColor: AppColors.divider,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.primaryLight,
        textColor: AppColors.text,
      ),
    );
  }

  /// 统一的文字层级：正文 15 号，读起来不费眼
  static TextTheme _buildTextTheme() {
    return const TextTheme(
      displaySmall: TextStyle(
        color: AppColors.text,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
      headlineMedium: TextStyle(
        color: AppColors.text,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: TextStyle(
        color: AppColors.text,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: TextStyle(
        color: AppColors.text,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: TextStyle(
        color: AppColors.text,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
      bodyLarge: TextStyle(
        color: AppColors.text,
        fontSize: 15,
        height: 1.6,
      ),
      bodyMedium: TextStyle(
        color: AppColors.text,
        fontSize: 14,
        height: 1.55,
      ),
      bodySmall: TextStyle(
        color: AppColors.textDim,
        fontSize: 12,
        height: 1.45,
      ),
      labelLarge: TextStyle(
        color: AppColors.text,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: TextStyle(
        color: AppColors.textDim,
        fontSize: 11,
        letterSpacing: 0.4,
      ),
    );
  }

  /// 属性数值的统一着色：越高越亮，负值走警告色
  static Color valueColor(num value) {
    if (value < 0) return AppColors.danger;
    if (value >= 80) return AppColors.success;
    if (value >= 50) return AppColors.text;
    if (value >= 25) return AppColors.warning;
    return AppColors.danger;
  }
}
