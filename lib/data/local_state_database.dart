import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../core/security/secure_kv_store.dart';

/// Durable embedded storage for THAMAN operational data.
///
/// V9.8 stores operational state in AES-encrypted Hive boxes. Existing V9.4
/// plaintext boxes are migrated once into the encrypted boxes and deleted
/// after the encrypted writes are flushed, so sensitive shop data is not left
/// on disk in plaintext.
class LocalStateDatabase {
  LocalStateDatabase._();
  static final LocalStateDatabase instance = LocalStateDatabase._();

  static const _primaryBoxName = 'thaman_pos_operational_v9_7_enc';
  static const _backupBoxName = 'thaman_pos_operational_backup_v9_7_enc';
  static const _metaBoxName = 'thaman_pos_operational_meta_v9_7_enc';

  static const _legacyPrimaryBoxName = 'thaman_pos_operational_v9_4';
  static const _legacyBackupBoxName = 'thaman_pos_operational_backup_v9_4';
  static const _legacyMetaBoxName = 'thaman_pos_operational_meta_v9_4';

  static const _encryptionKeyStoreKey = 'thaman_pos_hive_aes_key_v1';
  static const _stateKey = 'state_json';
  static const _checksumKey = 'state_sha256';
  static const _cloudBaselineKey = 'cloud_baseline_json';
  static const _corruptKey = 'corrupt_primary_recovery_copy';

  Box<String>? _primary;
  Box<String>? _backup;
  Box<String>? _meta;
  List<int>? _testingEncryptionKey;

  Future<void> _writeTail = Future<void>.value();

  Future<T> _enqueueWrite<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _writeTail = _writeTail
        .catchError((Object _, StackTrace __) {})
        .then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> initialize() async {
    if (_primary != null && _backup != null && _meta != null) return;
    await Hive.initFlutter();
    final cipher = HiveAesCipher(await _loadEncryptionKey());

    _primary = await Hive.openBox<String>(
      _primaryBoxName,
      encryptionCipher: cipher,
    );
    _backup = await Hive.openBox<String>(
      _backupBoxName,
      encryptionCipher: cipher,
    );
    _meta = await Hive.openBox<String>(
      _metaBoxName,
      encryptionCipher: cipher,
    );

    await _migrateLegacyBoxesIfNeeded();
  }

  Future<List<int>> _loadEncryptionKey() async {
    final testing = _testingEncryptionKey;
    if (testing != null) return List<int>.from(testing);

    try {
      final stored = await SecureKvStore.instance.readStrict(_encryptionKeyStoreKey);
      if (stored != null && stored.isNotEmpty) {
        final key = base64Url.decode(stored);
        if (key.length == 32) return key;
      }

      final random = Random.secure();
      final key = List<int>.generate(32, (_) => random.nextInt(256));
      await SecureKvStore.instance.writeStrict(
        _encryptionKeyStoreKey,
        base64UrlEncode(key),
      );
      return key;
    } on SecureStorageUnavailableException {
      throw StateError(
        'Secure storage is required to protect THAMAN local business data.',
      );
    }
  }

  Future<void> _migrateLegacyBoxesIfNeeded() async {
    final primary = _require(_primary, _primaryBoxName);
    final backup = _require(_backup, _backupBoxName);
    final meta = _require(_meta, _metaBoxName);
    if (primary.isNotEmpty || backup.isNotEmpty || meta.isNotEmpty) {
      await _deleteLegacyBoxesFromDisk();
      return;
    }

    Box<String>? legacyPrimary;
    Box<String>? legacyBackup;
    Box<String>? legacyMeta;
    try {
      legacyPrimary = await Hive.openBox<String>(_legacyPrimaryBoxName);
      legacyBackup = await Hive.openBox<String>(_legacyBackupBoxName);
      legacyMeta = await Hive.openBox<String>(_legacyMetaBoxName);

      if (legacyPrimary.isNotEmpty) {
        await primary.putAll(Map<String, String>.from(legacyPrimary.toMap()));
        await primary.flush();
      }
      if (legacyBackup.isNotEmpty) {
        await backup.putAll(Map<String, String>.from(legacyBackup.toMap()));
        await backup.flush();
      }
      if (legacyMeta.isNotEmpty) {
        await meta.putAll(Map<String, String>.from(legacyMeta.toMap()));
        await meta.flush();
      }
    } finally {
      await legacyPrimary?.close();
      await legacyBackup?.close();
      await legacyMeta?.close();
    }

    // Migration is complete only after encrypted writes have been flushed.
    // Remove plaintext legacy boxes so sensitive shop data is not left behind.
    await _deleteLegacyBoxesFromDisk();
  }

  Future<void> _deleteLegacyBoxesFromDisk() async {
    for (final name in const [
      _legacyPrimaryBoxName,
      _legacyBackupBoxName,
      _legacyMetaBoxName,
    ]) {
      try {
        if (Hive.isBoxOpen(name)) {
          await Hive.box<String>(name).close();
        }
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
  }

  @visibleForTesting
  void setEncryptionKeyForTesting(List<int>? key) {
    if (key != null && key.length != 32) {
      throw ArgumentError('Hive test encryption key must be 32 bytes.');
    }
    _testingEncryptionKey = key == null ? null : List<int>.from(key);
  }

  /// Resets the embedded database between unit tests.
  /// Production code must never call it.
  @visibleForTesting
  Future<void> resetForTesting() async {
    await _writeTail.catchError((Object _, StackTrace __) {});

    final primary = _primary;
    final backup = _backup;
    final meta = _meta;
    _primary = null;
    _backup = null;
    _meta = null;

    await primary?.close();
    await backup?.close();
    await meta?.close();

    for (final name in const [
      _primaryBoxName,
      _backupBoxName,
      _metaBoxName,
      _legacyPrimaryBoxName,
      _legacyBackupBoxName,
      _legacyMetaBoxName,
    ]) {
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
  }

  String? get primaryRaw => _primary?.get(_stateKey);
  String? get primaryChecksum => _primary?.get(_checksumKey);
  String? get backupRaw => _backup?.get(_stateKey);
  String? get backupChecksum => _backup?.get(_checksumKey);
  String? get cloudBaselineRaw => _meta?.get(_cloudBaselineKey);

  Future<void> writeState(
    String raw,
    String checksum, {
    bool rollBackup = true,
  }) {
    return _enqueueWrite(() async {
      final primary = _require(_primary, _primaryBoxName);
      final backup = _require(_backup, _backupBoxName);
      final previous = primary.get(_stateKey);
      final previousChecksum = primary.get(_checksumKey);
      if (rollBackup && previous != null && previous.isNotEmpty && previous != raw) {
        await backup.put(_stateKey, previous);
        if (previousChecksum != null && previousChecksum.isNotEmpty) {
          await backup.put(_checksumKey, previousChecksum);
        } else {
          await backup.delete(_checksumKey);
        }
        await backup.flush();
      }
      await primary.put(_stateKey, raw);
      await primary.put(_checksumKey, checksum);
      await primary.flush();
    });
  }

  Future<void> writeCloudBaseline(String raw) {
    return _enqueueWrite(() async {
      final meta = _require(_meta, _metaBoxName);
      await meta.put(_cloudBaselineKey, raw);
      await meta.flush();
    });
  }

  Future<void> preserveCorruptPrimary(String raw) {
    return _enqueueWrite(() async {
      final meta = _require(_meta, _metaBoxName);
      await meta.put(_corruptKey, raw);
      await meta.flush();
    });
  }

  Future<void> clearBackup() {
    return _enqueueWrite(() async {
      final backup = _require(_backup, _backupBoxName);
      await backup.clear();
      await backup.flush();
    });
  }

  T _require<T>(T? value, String name) {
    if (value == null) {
      throw StateError('Local database box not initialized: $name');
    }
    return value;
  }
}
