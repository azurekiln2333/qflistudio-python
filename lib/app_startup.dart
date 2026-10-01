import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qfli_studio_core/splash_screen.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

const _platformChannel = MethodChannel('qflistudio/platform');

Future<void> _reportProgress(double progress) async {
  try {
    await _platformChannel.invokeMethod<void>('startupProgress', {
      'progress': progress,
    });
  } on PlatformException catch (error) {
    debugPrint('Startup progress unavailable: ${error.code}');
  } on MissingPluginException {
    // Native progress is optional for alternate entry shells.
  }
}

/// Keep the native startup surface until the initialized app has laid out.
Future<void> runWithAppStartup({
  required Widget app,
  required ProjectStore store,
  required AuthStore auth,
  required SettingsStore settings,
  required ValueNotifier<bool> ready,
}) async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final nativeStartup =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.ohos);
  if (nativeStartup) binding.deferFirstFrame();

  try {
    runApp(app);
    // Bootstrap after framework layout, even while engine frames are deferred.
    await binding.endOfFrame;
    final minimumDisplay = nativeStartup
        ? Future<void>.delayed(const Duration(milliseconds: 1100))
        : Future<void>.value();
    if (nativeStartup) {
      await Future<void>.delayed(const Duration(milliseconds: 160));
    }
    await AppBootstrap.run(
      store: store,
      auth: auth,
      settings: settings,
      ready: ready,
      onProgress: nativeStartup
          ? (progress) => unawaited(_reportProgress(progress))
          : null,
    );
    await Future.wait([
      minimumDisplay,
      if (nativeStartup)
        Future<void>.delayed(const Duration(milliseconds: 320)),
    ]);
    // The ready notifier rebuilds the home page before its first engine frame.
    if (nativeStartup) await binding.endOfFrame;
  } finally {
    if (nativeStartup) binding.allowFirstFrame();
  }
}
