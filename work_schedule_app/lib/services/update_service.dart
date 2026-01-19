import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// Service to check for and download app updates from GitHub Releases
class UpdateService {
  // GitHub repository info - update these for your repo
  static const String _owner = 'Cottagex';
  static const String _repo = 'Manager-Schedule-App';
  
  // Current app version (should match pubspec.yaml)
  static const String currentVersion = '1.2.2';
  
  /// Cached update info
  static String? _latestVersion;
  static String? _downloadUrl;
  static String? _releaseNotes;
  static bool _hasChecked = false;
  
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
  static Future<bool> checkForUpdates() async {
    try {
      final url = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/releases/latest'
      );
      
      final response = await http.get(url, headers: {
        'Accept': 'application/vnd.github.v3+json',
      });
      
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
        
        _hasChecked = true;
        debugPrint('UpdateService: Latest version: $_latestVersion, Current: $currentVersion');
        debugPrint('UpdateService: Download URL: $_downloadUrl');
        
        return updateAvailable;
      } else if (response.statusCode == 404) {
        // No releases yet
        debugPrint('UpdateService: No releases found');
        _hasChecked = true;
        return false;
      } else {
        debugPrint('UpdateService: Failed to check updates: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('UpdateService: Error checking for updates: $e');
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
      final downloadsDir = Directory(p.join(
        Platform.environment['USERPROFILE'] ?? '',
        'Downloads',
      ));
      
      if (!downloadsDir.existsSync()) {
        onError('Could not find Downloads folder');
        return;
      }
      
      final fileName = 'work_schedule_app_v$_latestVersion.zip';
      final filePath = p.join(downloadsDir.path, fileName);
      
      // Download the file
      final request = http.Request('GET', Uri.parse(_downloadUrl!));
      final response = await http.Client().send(request);
      
      if (response.statusCode != 200) {
        onError('Download failed: ${response.statusCode}');
        return;
      }
      
      final contentLength = response.contentLength ?? 0;
      int received = 0;
      
      final file = File(filePath);
      final sink = file.openWrite();
      
      await for (final chunk in response.stream) {
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
      
    } catch (e) {
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
