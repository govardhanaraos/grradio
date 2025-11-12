import 'package:flutter/cupertino.dart';

/// This class encapsulates the logic for determining responsive sizes
/// based on the device's screen width, mimicking the concept of CSS media queries.
class RButton extends StatelessWidget {
  // Store the screen width provided at instantiation (obtained via MediaQuery.of(context).size.width)
  static double screenWidth = 600.0;

  // Constants for common breakpoints
  static const double mobileBreakpoint = 600.0;
  static const double tabletBreakpoint = 1024.0;

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    print('screen width ${screenWidth}');
    getButtonFontSize();
    throw UnimplementedError();
  }

  /// Returns the appropriate font size based on the screenWidth.
  ///
  /// - Small (< 600px): 16.0
  /// - Medium (600px to 1023px): 20.0
  /// - Large (>= 1024px): 24.0
  double getButtonFontSize() {
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

  /// Returns dynamic horizontal padding based on the font size.
  double getHorizontalPadding() {
    final double fontSize = getButtonFontSize();
    // Use 1.5x the font size for horizontal padding
    return fontSize * 1.5;
  }

  /// Returns dynamic vertical padding based on the font size.
  double getVerticalPadding() {
    final double fontSize = getButtonFontSize();
    // Use 0.8x the font size for vertical padding
    return fontSize * 0.8;
  }
}
