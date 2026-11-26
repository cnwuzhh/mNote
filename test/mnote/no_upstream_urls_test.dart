import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/settings/app_info.dart';
import 'package:saber/data/nextcloud/nextcloud_client_extension.dart';
import 'package:saber/pages/user/login.dart';

/// mNote must never silently use upstream Saber's services (privacy policy,
/// sign-up, default Nextcloud server, sponsorship). Until mNote has its own,
/// these stay on `.invalid` hosts, which never resolve (RFC 2606).
void main() {
  test('placeholder URLs use .invalid hosts', () {
    for (final uri in [
      AppInfo.privacyPolicyUrl,
      NcLoginPage.signupUrl,
      NextcloudClientExtension.defaultNextcloudUri,
    ]) {
      expect(uri.host, endsWith('.invalid'), reason: '$uri');
    }
  });

  test('no upstream Saber service URLs in lib/', () {
    const banned = ['saber.adil.hanney.org', 'github.com/sponsors/adil192'];
    final hits = <String>[];
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.startsWith('lib/i18n/')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue; // comments may cite upstream
        if (banned.any(line.contains)) hits.add('${f.path}:${i + 1}: $line');
      }
    }
    expect(hits, isEmpty);
  });
}
