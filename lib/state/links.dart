import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a web address in the browser. Tests supply their own.
abstract class LinkOpener {
  /// Whether the address was handed to a browser.
  Future<bool> open(Uri link);
}

class BrowserLinkOpener implements LinkOpener {
  const BrowserLinkOpener();

  @override
  Future<bool> open(Uri link) async {
    // Only web pages: an address from a shared notebook is never trusted
    // to start anything else.
    if (link.scheme != 'http' && link.scheme != 'https') return false;
    return launchUrl(link, mode: LaunchMode.externalApplication);
  }
}

final linkOpenerProvider = Provider<LinkOpener>((ref) => const BrowserLinkOpener());
