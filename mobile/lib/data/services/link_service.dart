import 'package:url_launcher/url_launcher.dart';

/// Opens a web address outside the app.
abstract class LinkService {
  /// True when a browser (or another app) took the address.
  Future<bool> open(String url);
}

class UrlLauncherLinkService implements LinkService {
  @override
  Future<bool> open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
