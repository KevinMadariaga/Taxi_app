import 'package:flutter/material.dart';

class ResponsiveHelper {
  static ResponsiveData getResponsiveData(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    // Calcular escalas basadas en diseño de referencia (375x812)
    final scaleWidth = screenWidth / 375.0;
    final scaleHeight = screenHeight / 812.0;
    final scale = (scaleWidth + scaleHeight) / 2;

    // Determinar tipo de dispositivo
    DeviceType deviceType;
    if (screenWidth < 600) {
      deviceType = DeviceType.mobile;
    } else if (screenWidth < 1200) {
      deviceType = DeviceType.tablet;
    } else {
      deviceType = DeviceType.desktop;
    }

    return ResponsiveData(
      screenWidth: screenWidth,
      screenHeight: screenHeight,
      scale: scale,
      scaleWidth: scaleWidth,
      scaleHeight: scaleHeight,
      deviceType: deviceType,
    );
  }

  static double sp(BuildContext context, double fontSize) {
    final data = getResponsiveData(context);
    return fontSize * data.scale;
  }

  static double wp(BuildContext context, double percentage) {
    final data = getResponsiveData(context);
    return data.screenWidth * (percentage / 100);
  }

  static double hp(BuildContext context, double percentage) {
    final data = getResponsiveData(context);
    return data.screenHeight * (percentage / 100);
  }

  static EdgeInsets padding(
    BuildContext context, {
    double? all,
    double? horizontal,
    double? vertical,
    double? top,
    double? bottom,
    double? left,
    double? right,
  }) {
    final data = getResponsiveData(context);
    return EdgeInsets.only(
      top: (top ?? vertical ?? all ?? 0) * data.scale,
      bottom: (bottom ?? vertical ?? all ?? 0) * data.scale,
      left: (left ?? horizontal ?? all ?? 0) * data.scale,
      right: (right ?? horizontal ?? all ?? 0) * data.scale,
    );
  }
}

class ResponsiveData {
  final double screenWidth;
  final double screenHeight;
  final double scale;
  final double scaleWidth;
  final double scaleHeight;
  final DeviceType deviceType;

  ResponsiveData({
    required this.screenWidth,
    required this.screenHeight,
    required this.scale,
    required this.scaleWidth,
    required this.scaleHeight,
    required this.deviceType,
  });
}

enum DeviceType { mobile, tablet, desktop }
