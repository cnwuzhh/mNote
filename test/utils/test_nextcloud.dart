import 'dart:io';

/// Nextcloud account for the sync tests, taken from the environment:
///
///   MNOTE_TEST_NC_URL       e.g. https://nc.example.com
///   MNOTE_TEST_NC_USER
///   MNOTE_TEST_NC_PASSWORD  app password
///   MNOTE_TEST_NC_ENC       encryption password (any string for a fresh account)
///
/// mNote has no server of its own. These tests used to log in to upstream
/// Saber\x27s server with Saber\x27s test accounts; they now run only against a
/// server you configure, and are skipped otherwise.
class TestNextcloud {
  new _(this.url, this.user, this.password, this.encPassword);

  final String url, user, password, encPassword;

  static TestNextcloud? fromEnvironment() {
    final e = Platform.environment;
    final url = e['MNOTE_TEST_NC_URL'], user = e['MNOTE_TEST_NC_USER'];
    final pw = e['MNOTE_TEST_NC_PASSWORD'], enc = e['MNOTE_TEST_NC_ENC'];
    if ([url, user, pw, enc].any((v) => v == null || v.isEmpty)) return null;
    return TestNextcloud._(url!, user!, pw!, enc!);
  }

  static const skipReason =
      'set MNOTE_TEST_NC_URL / _USER / _PASSWORD / _ENC to run sync tests against your own Nextcloud';
}
