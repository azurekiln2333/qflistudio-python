import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_python/app_startup.dart';
import 'package:qfli_python/main.dart' show pythonProfile;
import 'package:qfli_studio_core/app.dart';
import 'package:qfli_studio_core/pages/home_page.dart';
import 'package:qfli_studio_core/services/app_backup_service.dart';
import 'package:qfli_studio_core/services/app_restore_gate.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/splash_screen.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

const _platformChannel = MethodChannel('qflistudio/platform');

class _Load {
  late final completion = Completer<void>();
  var started = false;

  Future<void> run() {
    started = true;
    return completion.future;
  }
}

class _ProjectStore extends ProjectStore {
  final loading = _Load();

  @override
  Future<void> load() => loading.run();
}

class _AuthStore extends AuthStore {
  final loading = _Load();

  @override
  Future<void> load() => loading.run();
}

class _SettingsStore extends SettingsStore {
  final loading = _Load();

  @override
  Future<void> load() => loading.run();
}

class _StartupProbe extends StatelessWidget {
  const _StartupProbe({required this.ready, required this.onLayout});

  final ValueListenable<bool> ready;
  final void Function(bool ready, bool canSendFrame) onLayout;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: ready,
    builder: (context, isReady, _) => LayoutBuilder(
      builder: (context, constraints) {
        onLayout(isReady, WidgetsBinding.instance.sendFramesToEngine);
        return ColoredBox(
          key: ValueKey(isReady ? 'home' : 'loading'),
          color: isReady ? Colors.green : Colors.white,
        );
      },
    ),
  );
}

class _RejectingReady extends ValueNotifier<bool> {
  _RejectingReady() : super(false);

  @override
  set value(bool value) => throw StateError('ready notification failed');
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late _ProjectStore store;
  late _AuthStore auth;
  late _SettingsStore settings;
  late ValueNotifier<bool> ready;
  late List<MethodCall> progressCalls;
  late List<({bool ready, bool canSendFrame})> layouts;
  late Directory directory;
  String? originalBackupRoot;
  AppRestoreStatus? originalRestoreStatus;
  StudioProfile? originalProfile;

  setUp(() {
    binding.resetFirstFrameSent();
    directory = Directory.systemTemp.createTempSync('qfli_python_startup_');
    originalBackupRoot = AppBackupService.rootOverride;
    originalRestoreStatus = AppRestoreGate.status.value;
    originalProfile = StudioProfile.current;
    AppBackupService.rootOverride = directory.path;
    AppRestoreGate.status.value = null;
    store = _ProjectStore();
    auth = _AuthStore();
    settings = _SettingsStore();
    ready = ValueNotifier(false);
    progressCalls = [];
    layouts = [];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_platformChannel, (
      call,
    ) async {
      progressCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _platformChannel,
      null,
    );
    store.dispose();
    auth.dispose();
    settings.dispose();
    ready.dispose();
    AppBackupService.rootOverride = originalBackupRoot;
    AppRestoreGate.status.value = originalRestoreStatus;
    StudioProfile.current = originalProfile;
    directory.deleteSync(recursive: true);
  });

  Future<void> waitForIo(
    WidgetTester tester,
    bool Function() complete, {
    required String reason,
  }) async {
    // Restore preflight and real stores use filesystem I/O outside fake time.
    for (var attempt = 0; !complete() && attempt < 100; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(complete(), isTrue, reason: reason);
  }

  Future<void> waitForLoads(WidgetTester tester) => waitForIo(
    tester,
    () =>
        store.loading.started &&
        auth.loading.started &&
        settings.loading.started,
    reason: 'The isolated restore preflight must finish before store loads.',
  );

  Future<void> launch() => runWithAppStartup(
    app: _StartupProbe(
      ready: ready,
      onLayout: (ready, canSendFrame) {
        layouts.add((ready: ready, canSendFrame: canSendFrame));
      },
    ),
    store: store,
    auth: auth,
    settings: settings,
    ready: ready,
  );

  void finishLoads() {
    store.loading.completion.complete();
    auth.loading.completion.complete();
    settings.loading.completion.complete();
  }

  List<double> reportedProgress() => progressCalls.map((call) {
    expect(call.method, 'startupProgress');
    expect(call.arguments, isA<Map>());
    final arguments = call.arguments as Map;
    expect(arguments.keys, ['progress']);
    return arguments['progress'] as double;
  }).toList();

  for (final platform in [TargetPlatform.android, TargetPlatform.ohos]) {
    testWidgets(
      '$platform waits for local loads and ready home layout',
      (tester) async {
        var completed = false;
        final startup = launch().then((_) => completed = true);
        expect(binding.sendFramesToEngine, isFalse);
        expect(store.loading.started, isFalse);

        await tester.pump();
        expect(layouts, [(ready: false, canSendFrame: false)]);
        expect(store.loading.started, isFalse);
        await tester.pump(const Duration(milliseconds: 160));
        await waitForLoads(tester);
        expect(store.loading.started, isTrue);
        expect(auth.loading.started, isTrue);
        expect(settings.loading.started, isTrue);
        expect(reportedProgress(), isEmpty);

        settings.loading.completion.complete();
        await tester.pump();
        expect(reportedProgress(), [1 / 3]);
        expect(ready.value, isFalse);
        expect(binding.sendFramesToEngine, isFalse);

        auth.loading.completion.complete();
        await tester.pump();
        expect(reportedProgress(), [1 / 3, 2 / 3]);
        expect(ready.value, isFalse);

        store.loading.completion.complete();
        await tester.pump();
        expect(reportedProgress(), [1 / 3, 2 / 3, 1]);
        expect(ready.value, isTrue);
        await tester.pump();
        expect(layouts.last, (ready: true, canSendFrame: false));
        expect(completed, isFalse);
        expect(binding.sendFramesToEngine, isFalse);

        await tester.pump(const Duration(milliseconds: 939));
        expect(completed, isFalse);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump();
        await startup;
        expect(binding.sendFramesToEngine, isTrue);
        expect(completed, isTrue);
        expect(find.byKey(const ValueKey('home')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets(
    'slow bootstrap preserves the post-load settling interval',
    (tester) async {
      final startup = launch();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await waitForLoads(tester);
      expect(binding.sendFramesToEngine, isFalse);
      expect(ready.value, isFalse);
      finishLoads();
      await tester.pump();
      expect(ready.value, isTrue);
      await tester.pump(const Duration(milliseconds: 319));
      expect(binding.sendFramesToEngine, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      await startup;
      expect(binding.sendFramesToEngine, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final channelError in [
    MissingPluginException('no native startup handler'),
    PlatformException(code: 'STARTUP_UNAVAILABLE'),
  ]) {
    testWidgets(
      'failed local load and $channelError still reach home',
      (tester) async {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _platformChannel,
          (call) async {
            progressCalls.add(call);
            throw channelError;
          },
        );
        final startup = launch();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 160));
        await waitForLoads(tester);
        store.loading.completion.completeError(
          StateError('registry is corrupt'),
          StackTrace.empty,
        );
        auth.loading.completion.complete();
        settings.loading.completion.complete();
        await tester.pump();
        expect(reportedProgress(), [1 / 3, 2 / 3, 1]);
        expect(ready.value, isTrue);
        await tester.pump();
        expect(layouts.last, (ready: true, canSendFrame: false));
        await tester.pump(const Duration(milliseconds: 940));
        await tester.pump();
        await startup;
        expect(binding.sendFramesToEngine, isTrue);
        expect(find.byKey(const ValueKey('home')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'a delayed progress response cannot hold the first frame',
    (tester) async {
      final response = Completer<void>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _platformChannel,
        (call) {
          progressCalls.add(call);
          return response.future;
        },
      );
      final startup = launch();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      await waitForLoads(tester);
      finishLoads();
      await tester.pump();
      expect(reportedProgress(), [1 / 3, 2 / 3, 1]);
      await tester.pump(const Duration(milliseconds: 940));
      await tester.pump();
      await startup;
      expect(binding.sendFramesToEngine, isTrue);
      response.complete();
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.ohos),
  );

  testWidgets(
    'unexpected bootstrap failure releases the first-frame gate',
    (tester) async {
      ready.dispose();
      ready = _RejectingReady();
      final startup = launch();
      final failure = expectLater(startup, throwsStateError);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      await waitForLoads(tester);
      finishLoads();
      await tester.pump();
      await failure;
      expect(binding.sendFramesToEngine, isTrue);
      await tester.pump(const Duration(milliseconds: 940));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'other platforms display the Flutter fallback while loading',
    (tester) async {
      final startup = launch();
      expect(binding.sendFramesToEngine, isTrue);
      expect(store.loading.started, isFalse);
      await tester.pump();
      expect(layouts, [(ready: false, canSendFrame: true)]);
      await waitForLoads(tester);
      expect(store.loading.started, isTrue);
      expect(find.byKey(const ValueKey('loading')), findsOneWidget);
      finishLoads();
      await tester.pump();
      await startup;
      await tester.pump();
      expect(ready.value, isTrue);
      expect(reportedProgress(), isEmpty);
      expect(find.byKey(const ValueKey('home')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final channelAvailable in [true, false]) {
    testWidgets(
      'OHOS first engine frame contains the real home with progress channel '
      '${channelAvailable ? "available" : "missing"}',
      (tester) async {
        StudioProfile.current = pythonProfile;
        final projectStore = ProjectStore(
          storageFile: File('${directory.path}/projects.json'),
        );
        final authStore = AuthStore(
          storageFile: File('${directory.path}/auth.json'),
        );
        final settingsStore = SettingsStore(
          storageFile: File('${directory.path}/settings.json'),
        );
        if (!channelAvailable) {
          binding.defaultBinaryMessenger.setMockMethodCallHandler(
            _platformChannel,
            null,
          );
        }
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          projectStore.dispose();
          authStore.dispose();
          settingsStore.dispose();
        });

        final startup = runWithAppStartup(
          app: QfliApp(
            store: projectStore,
            auth: authStore,
            settings: settingsStore,
            ready: ready,
          ),
          store: projectStore,
          auth: authStore,
          settings: settingsStore,
          ready: ready,
        );
        expect(binding.sendFramesToEngine, isFalse);
        await tester.pump();
        expect(find.byType(SplashScreen), findsOneWidget);
        expect(find.byType(HomePage), findsNothing);
        expect(binding.sendFramesToEngine, isFalse);

        await tester.pump(const Duration(milliseconds: 160));
        await waitForIo(
          tester,
          () => ready.value,
          reason: 'Real local stores must finish before the native handoff.',
        );
        await tester.pump();
        expect(projectStore.loaded, isTrue);
        expect(find.byType(HomePage), findsOneWidget);
        expect(find.byType(SplashScreen), findsNothing);
        expect(binding.sendFramesToEngine, isFalse);
        if (channelAvailable) {
          expect(reportedProgress(), [1 / 3, 2 / 3, 1]);
        }

        await tester.pump(const Duration(milliseconds: 1100));
        await tester.pump();
        await startup;
        expect(binding.sendFramesToEngine, isTrue);
        await tester.pump();
        expect(find.byType(HomePage), findsOneWidget);
        expect(find.byType(SplashScreen), findsNothing);
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 20)),
      variant: TargetPlatformVariant.only(TargetPlatform.ohos),
    );
  }
}
