import 'package:flutter/material.dart';

import '../config.dart';
import '../services/update_service.dart';
import 'update_gate.dart';

/// The "About" row on the profile screen: shows which build is installed and,
/// when tapped, checks GitHub Releases for a newer one.
///
/// The launch check ([UpdateGate]) only runs once per app start, so this is
/// how someone who tapped "Later" gets back to the update without restarting.
class AboutTile extends StatefulWidget {
  const AboutTile({
    super.key,
    this.service,
    this.installer,
    this.openUrl,
    this.platformSupported,
    this.versionLabel,
  });

  /// Overridable for tests.
  final UpdateService? service;
  final UpdateInstaller? installer;
  final UrlOpener? openUrl;
  final bool? platformSupported;
  final String? versionLabel;

  @override
  State<AboutTile> createState() => _AboutTileState();
}

class _AboutTileState extends State<AboutTile> {
  late final UpdateService _service = widget.service ?? UpdateService();
  bool _checking = false;

  Future<void> _checkForUpdate() async {
    if (_checking) return;
    final supported = widget.platformSupported ?? updatePlatformSupported;

    setState(() => _checking = true);
    final result = supported
        ? await _service.checkDetailed()
        : const UpdateCheck(UpdateStatus.disabled);
    if (!mounted) return;
    setState(() => _checking = false);

    switch (result.status) {
      case UpdateStatus.available:
        await offerUpdate(
          context,
          result.update!,
          installer: widget.installer,
          openUrl: widget.openUrl,
        );
      case UpdateStatus.upToDate:
        _say('You have the latest version.');
      case UpdateStatus.disabled:
        _say('Updates are only available in the installed Android app.');
      case UpdateStatus.failed:
        _say('Could not check for updates. Check your connection and try again.');
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final version = widget.versionLabel ?? AppConfig.versionLabel;
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: const Text('About'),
      subtitle: Text('${AppConfig.hotelName} · $version\nTap to check for updates'),
      isThreeLine: true,
      trailing: _checking
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.system_update_alt),
      onTap: _checking ? null : _checkForUpdate,
    );
  }
}
