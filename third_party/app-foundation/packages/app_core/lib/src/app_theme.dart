import 'package:flutter/material.dart';

ThemeData createAppTheme({
  required Color seedColor,
  required Brightness brightness,
  String? fontFamily,
}) => ThemeData(
  fontFamily: fontFamily,
  colorScheme: ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  ),
);
