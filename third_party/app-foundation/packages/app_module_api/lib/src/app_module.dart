import 'package:flutter/widgets.dart';

/// An application-owned module instance with a stable, unique ID.
abstract interface class AppModule {
  String get id;

  List<LocalizationsDelegate<dynamic>> get localizationsDelegates;

  List<Locale> get supportedLocales;

  /// If initialization fails, release any resources acquired by this call.
  Future<void> init();

  /// Release the resources acquired by a successful initialization.
  Future<void> dispose();
}
