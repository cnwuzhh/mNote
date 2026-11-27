import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:nextcloud/core.dart';
import 'package:nextcloud/nextcloud.dart';
import 'package:saber/data/nextcloud/nc_http_overrides.dart';
import 'package:saber/data/nextcloud/nextcloud_client_extension.dart';
import 'package:url_launcher/url_launcher.dart';

class SaberLoginFlow {
  new start({required this.serverUrl}) {
    NcHttpOverrides.tempAcceptBadCertificateFrom(serverUrl);
    unawaited(_run());
  }

  final Uri serverUrl;

  final log = Logger('SaberLoginFlow');
  Timer? _pollTimer;

  final completer = Completer<LoginFlowV2Credentials>();
  late final future = completer.future;

  LoginFlowV2? init;

  /// Why the login page could not be opened or the flow failed, for the
  /// dialog to show (null while all is well).
  final problem = ValueNotifier<String?>(null);

  /// Tests: force the in-app tab path (true) or the system browser (false).
  @visibleForTesting
  static bool? debugUseInAppTab;

  /// Opens the Nextcloud login page.
  ///
  /// On mobile an in-app browser tab is tried first (it returns to the app
  /// when done). If it cannot be opened — no browser supporting it, an
  /// `http://` server, a browser that refuses — the system browser is used
  /// instead; either way the login completes by polling. With [external]
  /// the system browser is used directly (the dialog's retry button).
  Future<void> openLoginUrl({bool external = false}) async {
    final init = this.init;
    if (init == null) return;
    problem.value = null;

    final inAppTab =
        !external &&
        (debugUseInAppTab ??
            (Platform.isMacOS || Platform.isIOS || Platform.isAndroid));
    if (inAppTab) {
      try {
        log.info('Opening login link in-app: ${init.login}');
        await FlutterWebAuth2.authenticate(
          url: init.login,
          callbackUrlScheme: 'nc',
          options: const FlutterWebAuth2Options(
            // We removed the flutter_web_auth_2_desktop_webview package
            useWebview: false,
          ),
        );
        return;
      } on PlatformException catch (e) {
        // The user closed the tab: nothing to fix.
        if (e.code == 'CANCELED') return;
        log.warning(
          'In-app login tab failed (${e.code}: ${e.message}); using the system browser',
        );
      } catch (e) {
        log.warning('In-app login tab failed ($e); using the system browser');
      }
    }

    try {
      log.info('Opening login link in the system browser: ${init.login}');
      final ok = await launchUrl(
        Uri.parse(init.login),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) problem.value = 'noBrowser';
    } catch (e) {
      log.warning('Could not open the system browser: $e');
      problem.value = 'noBrowser';
    }
  }

  Future<void> _run() async {
    _catchHttpError(() async {
      final client = NextcloudClient(
        serverUrl,
        httpClient: NextcloudClientExtension.newHttpClient(),
      );
      final flowClient = client.core.clientFlowLoginV2;
      init = await flowClient.init().then((response) => response.body);
      log.info('init: $init');

      unawaited(openLoginUrl());

      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _catch404Error(() async {
          // Throws 404 if not logged in yet
          final poll = await flowClient.poll(
            $body: ClientFlowLoginV2PollRequestApplicationJson(
              (b) => b..token = init!.poll.token,
            ),
          );

          _pollTimer?.cancel();
          if (!completer.isCompleted) completer.complete(poll.body);
        }),
      );
    });
  }

  Future<T?> _catchHttpError<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on http.ClientException catch (error, stackTrace) {
      log.severe('Error while polling the login flow.', error, stackTrace);
      problem.value = 'server:$error';
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
      return null;
    } catch (error, stackTrace) {
      // Not a Nextcloud server, wrong path, certificate problems, …: report
      // it instead of leaving the dialog waiting forever.
      log.severe('Login flow failed.', error, stackTrace);
      problem.value = 'server:$error';
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
      return null;
    }
  }

  Future<T?> _catch404Error<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on DynamiteStatusCodeException catch (error) {
      if (error.statusCode != 404) rethrow;

      log.fine('Login flow not found or completed yet, will repoll');
      return null;
    }
  }

  /// Cancels the polling timer and completes the [completer] with an error.
  ///
  /// This is idempotent and is safe to call multiple times.
  void dispose() {
    _pollTimer?.cancel();
    if (!completer.isCompleted)
      completer.completeError(TimeoutException('Login flow was disposed'));
  }
}
