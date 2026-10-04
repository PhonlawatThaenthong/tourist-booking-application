import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';

/// Starts the download + install of [update] and reports progress.
typedef UpdateInstaller = Stream<OtaEvent> Function(AppUpdate update);

/// Opens [url] outside the app (browser). Returns false if nothing handled it.
typedef UrlOpener = Future<bool> Function(Uri url);

/// Wraps the first screen. Once, shortly after launch, asks [UpdateService]
/// whether a newer APK exists and, if so, offers to install it.
///
/// Android only allows a sideloaded app to *offer* an update: the user still
/// confirms the system install prompt (and, the first time, allows this app
/// to install packages). There is no silent self-update outside an app store.
///
/// Everything here is best-effort. No network, GitHub rate limit, a dev build
/// — the check just does nothing and the app carries on.
class UpdateGate extends StatefulWidget {
  const UpdateGate({
    super.key,
    required this.child,
    this.service,
    this.installer,
    this.openUrl,
    this.platformSupported,
  });

  final Widget child;

  /// Overridable for tests.
  final UpdateService? service;
  final UpdateInstaller? installer;
  final UrlOpener? openUrl;

  /// Defaults to "running as an Android app". Overridable for tests.
  final bool? platformSupported;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  late final UpdateService _service = widget.service ?? UpdateService();

  bool get _supported =>
      widget.platformSupported ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  @override
  void initState() {
    super.initState();
    if (_supported && _service.enabled) {
      // After the first frame, so there is a Navigator to show a dialog on.
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  Future<void> _check() async {
    final update = await _service.check();
    if (update == null || !mounted) return;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update available'),
        content: Text(
          'A newer version (${update.tag}) is ready.\n\n'
          'Your login and data are kept. Android will ask you to confirm '
          'the installation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;

    final installed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DownloadDialog(
        update: update,
        installer: widget.installer ?? _defaultInstaller,
      ),
    );
    // true = Android's installer took over; null = the user cancelled.
    if (installed != false || !mounted) return;

    // In-app install failed (permission refused, download error, ...): hand
    // the APK link to the browser instead, which can always download it.
    await _openInBrowser(update);
  }

  static Stream<OtaEvent> _defaultInstaller(AppUpdate update) =>
      OtaUpdate().execute(update.apkUrl, destinationFilename: update.apkName);

  Future<void> _openInBrowser(AppUpdate update) async {
    final open = widget.openUrl ??
        (Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);
    var opened = false;
    try {
      opened = await open(Uri.parse(update.apkUrl));
    } on Object {
      opened = false;
    }
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          opened
              ? 'Could not install in the app. Downloading in your browser '
                  'instead — open the file when it finishes.'
              : 'Could not download the update. Get it from: ${update.pageUrl}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Shows download progress. Pops `true` once Android's installer has taken
/// over, `false` on a failure (so the caller can fall back to the browser),
/// and `null` when the user cancelled.
class _DownloadDialog extends StatefulWidget {
  const _DownloadDialog({required this.update, required this.installer});

  final AppUpdate update;
  final UpdateInstaller installer;

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  StreamSubscription<OtaEvent>? _sub;
  double? _progress; // null = indeterminate
  bool _done = false;

  @override
  void initState() {
    super.initState();
    try {
      _sub = widget.installer(widget.update).listen(
        _onEvent,
        onError: (Object _) => _finish(false),
        onDone: () => _finish(false), // ended without ever reaching INSTALLING
      );
    } on Object {
      // Thrown synchronously, e.g. plugin missing on this platform.
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish(false));
    }
  }

  void _onEvent(OtaEvent event) {
    switch (event.status) {
      case OtaStatus.DOWNLOADING:
        final percent = double.tryParse(event.value ?? '');
        if (mounted) {
          setState(() => _progress = percent == null ? null : (percent / 100).clamp(0, 1));
        }
      case OtaStatus.INSTALLING:
      case OtaStatus.INSTALLATION_DONE:
        _finish(true);
      case OtaStatus.CANCELED:
        _finish(null);
      default:
        // Every other status is an error.
        _finish(false);
    }
  }

  void _finish(bool? success) {
    if (_done) return;
    _done = true;
    _sub?.cancel();
    if (mounted) Navigator.of(context).pop(success);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final percent = _progress == null ? '' : ' ${(_progress! * 100).round()}%';
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Downloading update'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 12),
            Text('${widget.update.tag}$percent'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _finish(null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
