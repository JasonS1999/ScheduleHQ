import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// Service to check for and download app updates from GitHub Releases
class UpdateService {
  // GitHub repository info - update these for your repo
  static const String _owner = 'JasonS1999';
  static const String _repo = 'Manager-Schedule-App';

  // Current app version (should match pubspec.yaml)
  static const String currentVersion = '1.3.0';

  /// Cached update info
  static String? _latestVersion;
  static String? _downloadUrl;
  static String? _releaseNotes;

  /// Whether a handshake/certificate error occurred
  static bool _handshakeError = false;
  static bool get hadHandshakeError => _handshakeError;

  /// Check if an update is available
  static bool get updateAvailable {
    if (_latestVersion == null) return false;
    return _compareVersions(_latestVersion!, currentVersion) > 0;
  }

  /// Get the latest version string
  static String? get latestVersion => _latestVersion;

  /// Get the release notes
  static String? get releaseNotes => _releaseNotes;

  /// Check GitHub releases for updates
  /// Last error message if check failed
  static String? _lastError;
  static String? get lastError => _lastError;

  /// Create an HTTP client that can handle certificate issues
  /// First tries normal connection, falls back to bypassing cert check if needed
  static Future<http.Response> _safeGet(
    Uri url, {
    Map<String, String>? headers,
  }) async {
    // First, try normal HTTPS connection
    try {
      return await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 10));
    } on HandshakeException catch (e) {
      debugPrint(
        'UpdateService: Handshake error, trying with custom client: $e',
      );
      _handshakeError = true;
      // Fall through to custom client
    } on SocketException catch (e) {
      debugPrint('UpdateService: Socket error: $e');
      rethrow;
    } catch (e) {
      // Check if it's a certificate-related error
      if (e.toString().contains('CERTIFICATE') ||
          e.toString().contains('Handshake') ||
          e.toString().contains('handshake')) {
        debugPrint(
          'UpdateService: Certificate error, trying with custom client: $e',
        );
        _handshakeError = true;
        // Fall through to custom client
      } else {
        rethrow;
      }
    }

    // If we get here, try with a custom HttpClient that bypasses certificate verification
    // This is less secure but necessary for some network environments
    final httpClient = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        // Only allow for GitHub API
        return host == 'api.github.com' || host == 'github.com';
      };

    try {
      final request = await httpClient.getUrl(url);
      headers?.forEach((key, value) => request.headers.set(key, value));
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final body = await response.transform(utf8.decoder).join();
      httpClient.close();
      return http.Response(body, response.statusCode);
    } finally {
      httpClient.close();
    }
  }

  static Future<bool> checkForUpdates() async {
    _lastError = null;
    _handshakeError = false;
    try {
      final url = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/releases/latest',
      );

      final response = await _safeGet(
        url,
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Extract version from tag_name (e.g., "v1.0.1" -> "1.0.1")
        String tagName = data['tag_name'] ?? '';
        if (tagName.startsWith('v')) {
          tagName = tagName.substring(1);
        }

        _latestVersion = tagName;
        _releaseNotes = data['body'] ?? '';

        // Find the Windows zip asset
        final assets = data['assets'] as List<dynamic>? ?? [];
        for (final asset in assets) {
          final name = asset['name'] as String? ?? '';
          if (name.endsWith('.zip') && name.toLowerCase().contains('windows')) {
            _downloadUrl = asset['browser_download_url'];
            break;
          }
        }

        // If no Windows-specific asset, try to find any zip
        if (_downloadUrl == null) {
          for (final asset in assets) {
            final name = asset['name'] as String? ?? '';
            if (name.endsWith('.zip')) {
              _downloadUrl = asset['browser_download_url'];
              break;
            }
          }
        }

        debugPrint(
          'UpdateService: Latest version: $_latestVersion, Current: $currentVersion',
        );
        debugPrint('UpdateService: Download URL: $_downloadUrl');

        return updateAvailable;
      } else if (response.statusCode == 404) {
        // No releases yet
        debugPrint('UpdateService: No releases found');
        _lastError = 'No releases found (404)';
        return false;
      } else {
        debugPrint(
          'UpdateService: Failed to check updates: ${response.statusCode}',
        );
        _lastError = 'HTTP ${response.statusCode}';
        return false;
      }
    } catch (e) {
      debugPrint('UpdateService: Error checking for updates: $e');
      _lastError = e.toString();
      return false;
    }
  }

  /// Download and apply the update
  static Future<void> downloadUpdate({
    required Function(double) onProgress,
    required Function(String) onStatus,
    required Function(String) onError,
    required Function() onComplete,
  }) async {
    if (_downloadUrl == null) {
      onError('No download URL available');
      return;
    }

    try {
      onStatus('Starting download...');

      // Get Downloads folder
      final downloadsDir = Directory(
        p.join(Platform.environment['USERPROFILE'] ?? '', 'Downloads'),
      );

      if (!downloadsDir.existsSync()) {
        onError('Could not find Downloads folder');
        return;
      }

      final fileName = 'work_schedule_app_v$_latestVersion.zip';
      final filePath = p.join(downloadsDir.path, fileName);

      // Download the file with certificate handling
      final downloadUri = Uri.parse(_downloadUrl!);

      // Create HttpClient with certificate bypass for GitHub domains
      final httpClient = HttpClient()
        ..badCertificateCallback =
            (X509Certificate cert, String host, int port) {
              // Allow GitHub and related CDN domains
              return host.contains('github') ||
                  host.contains('githubusercontent') ||
                  host.contains('objects.githubusercontent');
            };

      try {
        final request = await httpClient.getUrl(downloadUri);
        final response = await request.close();

        if (response.statusCode != 200) {
          // If download fails due to redirects/cert issues, fall back to browser
          if (response.statusCode >= 300 && response.statusCode < 400) {
            onStatus('Redirecting to browser download...');
            await openReleasesPage();
            onComplete();
            return;
          }
          onError('Download failed: ${response.statusCode}');
          return;
        }

        final contentLength = response.contentLength;
        int received = 0;

        final file = File(filePath);
        final sink = file.openWrite();

        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (contentLength > 0) {
            onProgress(received / contentLength);
          }
        }

        await sink.close();

        onStatus('Download complete!');
        onProgress(1.0);

        // Open the Downloads folder with the file selected
        await _openFileInExplorer(filePath);

        onComplete();
      } finally {
        httpClient.close();
      }
    } on HandshakeException catch (e) {
      debugPrint('UpdateService: Download handshake error: $e');
      onStatus('Certificate issue - opening in browser...');
      await openReleasesPage();
      onComplete();
    } catch (e) {
      // Check for certificate-related errors
      if (e.toString().contains('CERTIFICATE') ||
          e.toString().contains('Handshake') ||
          e.toString().contains('handshake')) {
        debugPrint('UpdateService: Download cert error: $e');
        onStatus('Certificate issue - opening in browser...');
        await openReleasesPage();
        onComplete();
        return;
      }
      onError('Error downloading update: $e');
    }
  }

  /// Open the GitHub releases page
  static Future<void> openReleasesPage() async {
    final url = Uri.parse('https://github.com/$_owner/$_repo/releases');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  /// Open file in Windows Explorer
  static Future<void> _openFileInExplorer(String filePath) async {
    // Use explorer.exe to open folder and select the file
    await Process.run('explorer.exe', ['/select,', filePath]);
  }

  /// Compare two version strings
  /// Returns: positive if v1 > v2, negative if v1 < v2, 0 if equal
  static int _compareVersions(String v1, String v2) {
    final parts1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    // Pad to same length
    while (parts1.length < parts2.length) parts1.add(0);
    while (parts2.length < parts1.length) parts2.add(0);

    for (int i = 0; i < parts1.length; i++) {
      if (parts1[i] > parts2[i]) return 1;
      if (parts1[i] < parts2[i]) return -1;
    }

    return 0;
  }
}
