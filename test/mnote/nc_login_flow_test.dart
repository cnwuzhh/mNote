// Test-only fakes for the url_launcher platform (transitive dependencies).
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:saber/data/nextcloud/login_flow.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Bug (2026-11-27, Android, server http://localhost:8380): the 「请授权」
/// dialog appeared but no login page opened. Failures of the in-app tab and
/// of the first request were swallowed. Now: fall back to the system
/// browser, and report what went wrong.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late String base;
  late _FakeLauncher launcher;
  final webAuthCalls = <Map<Object?, Object?>>[];
  String? webAuthError; // PlatformException code to throw, or null = success

  setUpAll(() async {
    HttpOverrides.global = null; // real HTTP to the local fake server
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final r = req.response;
      if (req.uri.path == '/index.php/login/v2' &&
          !req.uri.path.startsWith('/notnc')) {
        r.headers.contentType = ContentType.json;
        r.write(
          jsonEncode({
            'poll': {
              'token': 'tok',
              'endpoint': '$base/index.php/login/v2/poll',
            },
            'login': '$base/login/v2/flow/abc',
          }),
        );
      } else {
        // Polling (not logged in yet) and anything that is not Nextcloud.
        r.statusCode = 404;
        r.headers.contentType = ContentType.html;
        r.write('<html>Not found</html>');
      }
      await r.close();
    });
  });
  tearDownAll(() => server.close(force: true));

  setUp(() {
    launcher = _FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    webAuthCalls.clear();
    webAuthError = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_web_auth_2'), (
          call,
        ) async {
          webAuthCalls.add(call.arguments as Map<Object?, Object?>);
          if (webAuthError != null)
            throw PlatformException(code: webAuthError!, message: 'test');
          return 'nc://login/done';
        });
    SaberLoginFlow.debugUseInAppTab = true; // as on Android
  });
  tearDown(() => SaberLoginFlow.debugUseInAppTab = null);

  Future<SaberLoginFlow> started(String server) async {
    final flow = SaberLoginFlow.start(serverUrl: Uri.parse(server));
    for (
      var i = 0;
      i < 50 && flow.init == null && flow.problem.value == null;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return flow;
  }

  test(
    'no in-app tab available: the system browser opens the login page',
    () async {
      webAuthError = 'NO_BROWSER';
      final flow = await started(base);
      addTearDown(() {
        flow.future.ignore();
        flow.dispose();
      });
      expect(webAuthCalls, hasLength(1), reason: 'in-app tab tried first');
      expect(launcher.opened, ['$base/login/v2/flow/abc']);
      expect(launcher.modes, [PreferredLaunchMode.externalApplication]);
      expect(flow.problem.value, isNull);
    },
  );

  test(
    'neither the tab nor a browser can open it: the reason is reported',
    () async {
      webAuthError = 'SECURITY_EXCEPTION';
      launcher.result = false;
      final flow = await started(base);
      addTearDown(() {
        flow.future.ignore();
        flow.dispose();
      });
      expect(flow.problem.value, 'noBrowser');
    },
  );

  test('the user closed the tab: no second browser pops up', () async {
    webAuthError = 'CANCELED';
    final flow = await started(base);
    addTearDown(() {
      flow.future.ignore();
      flow.dispose();
    });
    expect(launcher.opened, isEmpty);
    expect(flow.problem.value, isNull);
  });

  test('the tab works: no system browser', () async {
    final flow = await started(base);
    addTearDown(() {
      flow.future.ignore();
      flow.dispose();
    });
    expect(webAuthCalls.single['url'], '$base/login/v2/flow/abc');
    expect(launcher.opened, isEmpty);
  });

  test('「登录页面没有打开？」 goes straight to the system browser', () async {
    final flow = await started(base);
    addTearDown(() {
      flow.future.ignore();
      flow.dispose();
    });
    webAuthCalls.clear();
    await flow.openLoginUrl(external: true);
    expect(webAuthCalls, isEmpty);
    expect(launcher.opened, ['$base/login/v2/flow/abc']);
  });

  test('not a Nextcloud server: an error instead of waiting forever', () async {
    final flow = SaberLoginFlow.start(serverUrl: Uri.parse('$base/notnc'));
    // The dialog listens from the start; so does the test.
    final failed = expectLater(flow.future, throwsA(anything));
    await failed;
    expect(flow.problem.value, startsWith('server:'));
    expect(flow.problem.value, contains('404'));
    expect(launcher.opened, isEmpty);
  });
}

class _FakeLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final opened = <String>[];
  final modes = <PreferredLaunchMode>[];
  var result = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    modes.add(options.mode);
    return result;
  }

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async => launchUrl(url, const LaunchOptions());
}
