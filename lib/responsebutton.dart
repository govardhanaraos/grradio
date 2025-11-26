import 'package:flutter/cupertino.dart';

/// This class encapsulates the logic for determining responsive sizes
/// based on the device's screen width, mimicking the concept of CSS media queries.
class RButton {
  // Store the screen width provided at instantiation (obtained via MediaQuery.of(context).size.width)
  static double screenWidth = 600.0;

  // Constants for common breakpoints
  static const double mobileBreakpoint = 600.0;
  static const double tabletBreakpoint = 1024.0;

  /// Initialize with current context to get screen width
  static void initialize(BuildContext context) {
    screenWidth = MediaQuery.of(context).size.width;
    print('screen width $screenWidth');
  }

  /// Returns the appropriate base size based on the screenWidth.
  ///
  /// - Small (< 600px): 55.0
  /// - Medium (600px to 1023px): 60.0
  /// - Large (>= 1024px): 64.0
  static double getBaseSize() {
    if (screenWidth < mobileBreakpoint) {
      // Mobile or extra-small screens
      return 55.0;
    } else if (screenWidth < tabletBreakpoint) {
      // Tablet or medium screens
      return 60.0;
    } else {
      // Desktop or large screens
      return 64.0;
    }
  }

  /// Returns dynamic horizontal padding based on the base size.
  static double getHorizontalPadding() {
    final double baseSize = getBaseSize();
    // Use 1.5x the base size for horizontal padding
    return baseSize * 1.5;
  }

  /// Returns dynamic vertical padding based on the base size.
  static double getVerticalPadding() {
    final double baseSize = getBaseSize();
    // Use 0.8x the base size for vertical padding
    return baseSize * 0.8;
  }

  // Button Sizes
  static double getSmallButtonSize() => getBaseSize() * 0.8; // ~44-51px
  static double getMediumButtonSize() => getBaseSize(); // 55-64px
  static double getLargeButtonSize() => getBaseSize() * 1.2; // ~66-77px
  static double getXLargeButtonSize() => getBaseSize() * 1.5; // ~82-96px

  // Icon Sizes
  static double getSmallIconSize() => getBaseSize() * 0.5; // ~27-32px
  static double getMediumIconSize() => getBaseSize() * 0.7; // ~38-45px
  static double getLargeIconSize() => getBaseSize() * 0.9; // ~49-58px
  static double getXLargeIconSize() => getBaseSize() * 1.1; // ~60-70px

  // Container Sizes
  static double getSmallContainerSize() => getBaseSize() * 1.0; // 55-64px
  static double getMediumContainerSize() => getBaseSize() * 1.3; // ~71-83px
  static double getLargeContainerSize() => getBaseSize() * 1.6; // ~88-102px
  static double getXLargeContainerSize() => getBaseSize() * 2.0; // 110-128px

  // Image Sizes
  static double getSmallImageSize() => getBaseSize() * 0.8; // ~44-51px
  static double getMediumImageSize() => getBaseSize() * 1.2; // ~66-77px
  static double getLargeImageSize() => getBaseSize() * 1.8; // ~99-115px
  static double getXLargeImageSize() => getBaseSize() * 2.5; // ~137-160px
  static double getXXLargeImageSize() => getBaseSize() * 3.6; // ~137-160px

  // Font Sizes
  static double getExSmallFontSize() => getBaseSize() * 0.20; // ~10-13px
  static double getSmallFontSize() => getBaseSize() * 0.25; // ~13-16px
  static double getMediumFontSize() => getBaseSize() * 0.3; // ~16-19px
  static double getLargeFontSize() => getBaseSize() * 0.4; // ~22-25px
  static double getXLargeFontSize() => getBaseSize() * 0.5; // ~27-32px
  static double getXXLargeFontSize() => getBaseSize() * 0.6; // ~27-32px

  // Border Radius
  static double getSmallBorderRadius() => getBaseSize() * 0.1; // ~5-6px
  static double getMediumBorderRadius() => getBaseSize() * 0.15; // ~8-9px
  static double getLargeBorderRadius() => getBaseSize() * 0.2; // ~11-13px

  // Spacing
  static double getSmallSpacing() => getBaseSize() * 0.1; // ~5-6px
  static double getMediumSpacing() => getBaseSize() * 0.2; // ~11-13px
  static double getLargeSpacing() => getBaseSize() * 0.3; // ~16-19px
  static double getXLargeSpacing() => getBaseSize() * 0.4; // ~22-25px
  static double getXXLargeSpacing() => getBaseSize() * 0.6; // ~22-25px

  // App Bar
  static double getAppBarHeight() => getBaseSize() * 1.1; // ~60-70px
  static double getAppBarIconSize() => getBaseSize() * 0.6; // ~33-38px

  // Player Sheet
  static double getMiniPlayerHeight() => getBaseSize() * 1.2; // ~66-77px
  static double getExpandedPlayerHeight(BuildContext context) =>
      MediaQuery.of(context).size.height * 0.7;

  // Control Buttons (for music player)
  static double getControlButtonSize() => getBaseSize() * 1.1; // ~60-70px
  static double getControlIconSize() => getBaseSize() * 0.9; // ~49-58px
  static double getMainControlButtonSize() => getBaseSize() * 1.3; // ~71-83px
  static double getMainControlIconSize() => getBaseSize() * 1.1; // ~60-70px

  // Action Buttons (record, recordings, etc.)
  static double getActionButtonSize() => getBaseSize() * 1.0; // 55-64px
  static double getActionIconSize() => getBaseSize() * 0.5; // ~27-32px

  // List Items
  static double getListItemHeight() => getBaseSize() * 0.9; // ~49-58px
  static double getListIconSize() => getBaseSize() * 0.4; // ~22-25px

  // Helper method to get responsive value based on screen size
  static T responsiveValue<T>({
    required T mobile,
    required T tablet,
    required T desktop,
  }) {
    if (screenWidth < mobileBreakpoint) {
      return mobile;
    } else if (screenWidth < tabletBreakpoint) {
      return tablet;
    } else {
      return desktop;
    }
  }
}
