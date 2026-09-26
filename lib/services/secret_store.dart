// Where the music server's password is kept: the system's own protected storage (Windows
// Credential Manager / DPAPI, the Android Keystore) instead of settings.json.
//
// HomeTunes (0.1.17, code review fix 11): the password used to sit in plain text in settings.json
// (and in the automatic "before restore" backup), so anyone who could copy those files could read
// it. LibraryModel keeps it here, keyed by the server address and user name, and moves an old
// plain-text password over the first time it loads.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores small secrets. Every method reports failure instead of throwing.
abstract class SecretStore {
  /// The value for [key], or null if there isn't one or it can't be read.
  Future<String?> read(String key);

  /// Saves [value] under [key]. False if it couldn't be saved.
  Future<bool> write(String key, String value);

  /// Removes [key] (nothing happens if it isn't there).
  Future<void> delete(String key);

  /// The store for this device: the system's protected storage on Windows, Android, iOS and
  /// macOS; an in-memory store under `flutter test`; null elsewhere (e.g. Linux while
  /// developing), where the password stays in settings.json as before.
  static SecretStore? forPlatform() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return MemorySecretStore();
    if (Platform.isWindows || Platform.isAndroid || Platform.isIOS || Platform.isMacOS) return SystemSecretStore();
    return null;
  }

  /// The key the server password is kept under: one per server address and user name, so a
  /// backup from another server never picks up the wrong password.
  static String serverPasswordKey(String url, String username) =>
      'server-password:${username.trim()}@${url.trim().toLowerCase()}';
}

/// The system's protected storage, through the flutter_secure_storage package.
class SystemSecretStore implements SecretStore {
  final FlutterSecureStorage _storage;
  SystemSecretStore() : _storage = const FlutterSecureStorage();

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      // E.g. Android restored the app's data from a cloud backup without the Keystore key that
      // encrypted it: the value can never be read, so drop it (the user signs in again).
      debugPrint('HomeTunes: could not read a saved secret: $e');
      try {
        await _storage.delete(key: key);
      } catch (_) {}
      return null;
    }
  }

  @override
  Future<bool> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      return true;
    } catch (e) {
      debugPrint('HomeTunes: could not save a secret: $e');
      return false;
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('HomeTunes: could not delete a saved secret: $e');
    }
  }
}

/// Keeps secrets in memory only (tests). [failWrites] simulates a store that can't save.
class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<bool> write(String key, String value) async {
    if (failWrites) return false;
    values[key] = value;
    return true;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}
