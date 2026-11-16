import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../data/providers.dart';

/// Opens web pages for the screens (sign-in, disclosure, profile).
class LinksViewModel {
  LinksViewModel(this._ref);
  final Ref _ref;

  String get privacyPolicyUrl => _ref.read(privacyPolicyUrlProvider);

  /// Opens the Privacy Policy in the browser. False when that did not work (no browser, or the address
  /// is still the build placeholder); the screen then shows the address as text.
  Future<bool> openPrivacyPolicy() async {
    final url = privacyPolicyUrl;
    if (url.isEmpty || url == AppConfig.privacyPolicyPlaceholder) return false;
    return _ref.read(linkServiceProvider).open(url);
  }
}

final linksViewModelProvider = Provider<LinksViewModel>((ref) => LinksViewModel(ref));
