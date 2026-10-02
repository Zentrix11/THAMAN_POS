/// Conflict-aware merge helpers for THAMAN's cloud operational snapshot.
///
/// The POS keeps a local baseline from the last successful sync. Changes made
/// offline are calculated against that baseline, then rebased on the newest
/// server snapshot. Collections are merged by stable record id, so unrelated
/// work from two devices is preserved instead of using blind last-write-wins.
class CloudStateMerge {
  CloudStateMerge._();

  static const Set<String> localOnlyKeys = {
    'invoiceSerial',
    'purchaseSerial',
    'stockCountSerial',
    'productSerial',
    'restockSerial',
    'journalSerial',
    'customerSerial',
    'supplierSerial',
    'sequenceEnds',
  };

  static const Set<String> mergeMapKeys = {
    'stockBaselines',
    'customerBalanceBaselines',
  };

  static bool deepEqual(dynamic a, dynamic b) => _deepEqual(a, b);

  static Map<String, dynamic> cloudProjection(Map<String, dynamic> state) {
    final result = <String, dynamic>{};
    for (final entry in state.entries) {
      if (!localOnlyKeys.contains(entry.key)) {
        result[entry.key] = _clone(entry.value);
      }
    }
    return result;
  }

  static Map<String, dynamic> diff(
    Map<String, dynamic> baseline,
    Map<String, dynamic> local,
  ) {
    final replace = <String, dynamic>{};
    final upserts = <String, dynamic>{};
    final deletes = <String, dynamic>{};
    final mapUpserts = <String, dynamic>{};
    final mapDeletes = <String, dynamic>{};

    final keys = <String>{...baseline.keys, ...local.keys}
      ..removeAll(localOnlyKeys);
    for (final key in keys) {
      final before = baseline[key];
      final after = local[key];
      if (_deepEqual(before, after)) continue;

      if (mergeMapKeys.contains(key) && before is Map && after is Map) {
        final b = before.map((k, v) => MapEntry('$k', v));
        final a = after.map((k, v) => MapEntry('$k', v));
        final changed = <String, dynamic>{};
        final removed = <String>[];
        for (final e in a.entries) {
          if (!b.containsKey(e.key) || !_deepEqual(b[e.key], e.value)) {
            changed[e.key] = _clone(e.value);
          }
        }
        for (final k in b.keys) {
          if (!a.containsKey(k)) removed.add(k);
        }
        if (changed.isNotEmpty) mapUpserts[key] = changed;
        if (removed.isNotEmpty) mapDeletes[key] = removed;
        continue;
      }

      if (_isIdCollection(before) || _isIdCollection(after)) {
        final b = _byId(before);
        final a = _byId(after);
        final changed = <dynamic>[];
        final removed = <String>[];
        for (final e in a.entries) {
          if (!b.containsKey(e.key) || !_deepEqual(b[e.key], e.value)) {
            changed.add(_clone(e.value));
          }
        }
        for (final id in b.keys) {
          if (!a.containsKey(id)) removed.add(id);
        }
        if (changed.isNotEmpty) upserts[key] = changed;
        if (removed.isNotEmpty) deletes[key] = removed;
        continue;
      }

      replace[key] = _clone(after);
    }

    return {
      'replace': replace,
      'upserts': upserts,
      'deletes': deletes,
      'mapUpserts': mapUpserts,
      'mapDeletes': mapDeletes,
    };
  }

  static Map<String, dynamic> apply(
    Map<String, dynamic> remote,
    Map<String, dynamic> patch,
  ) {
    final result = cloudProjection(remote);

    final replace = _map(patch['replace']);
    for (final e in replace.entries) {
      if (e.value == null) {
        result.remove(e.key);
      } else {
        result[e.key] = _clone(e.value);
      }
    }

    final upserts = _map(patch['upserts']);
    final deletes = _map(patch['deletes']);
    for (final key in <String>{...upserts.keys, ...deletes.keys}) {
      final current = _byId(result[key]);
      final removed = (deletes[key] is List)
          ? (deletes[key] as List).map((e) => '$e').toSet()
          : <String>{};
      current.removeWhere((id, _) => removed.contains(id));
      final incoming = upserts[key];
      if (incoming is List) {
        for (final raw in incoming) {
          if (raw is Map && raw['id'] != null) {
            current['${raw['id']}'] = Map<String, dynamic>.from(raw);
          }
        }
      }
      result[key] = current.values.map(_clone).toList();
    }

    final mapUpserts = _map(patch['mapUpserts']);
    final mapDeletes = _map(patch['mapDeletes']);
    for (final key in <String>{...mapUpserts.keys, ...mapDeletes.keys}) {
      final current = result[key] is Map
          ? Map<String, dynamic>.from(result[key] as Map)
          : <String, dynamic>{};
      final removed = mapDeletes[key];
      if (removed is List) {
        for (final raw in removed) {
          current.remove('$raw');
        }
      }
      final incoming = mapUpserts[key];
      if (incoming is Map) {
        for (final e in incoming.entries) {
          current['${e.key}'] = _clone(e.value);
        }
      }
      result[key] = current;
    }

    return result;
  }

  /// First cloud migration: merge two pre-cloud stores instead of deleting one.
  /// Stable-id collections are unioned, local changes win for the same id, and
  /// immutable per-entity baseline maps are unioned.
  static Map<String, dynamic> mergeInitial(
    Map<String, dynamic> remote,
    Map<String, dynamic> local,
  ) {
    if (_operationalCount(local) == 0) return cloudProjection(remote);
    if (_operationalCount(remote) == 0) return cloudProjection(local);
    final empty = <String, dynamic>{};
    return apply(cloudProjection(remote), diff(empty, cloudProjection(local)));
  }

  static int _operationalCount(Map<String, dynamic> state) {
    var count = 0;
    for (final key in const [
      'products',
      'invoices',
      'returns',
      'stockMovements',
      'purchases',
      'purchaseReturns',
      'customers',
      'suppliers',
      'customerPayments',
      'supplierPayments',
      'expenses',
      'journalEntries',
      'employees',
      'adminAccounts',
      'assets',
      'attendance',
      'overtimeRecords',
      'employeeAdvances',
    ]) {
      final value = state[key];
      if (value is List) count += value.length;
    }
    return count;
  }

  static bool _isIdCollection(dynamic value) {
    if (value is! List) return false;
    if (value.isEmpty) return false;
    return value.every((e) => e is Map && e['id'] != null);
  }

  static Map<String, Map<String, dynamic>> _byId(dynamic value) {
    final out = <String, Map<String, dynamic>>{};
    if (value is! List) return out;
    for (final raw in value) {
      if (raw is! Map || raw['id'] == null) continue;
      out['${raw['id']}'] = Map<String, dynamic>.from(raw);
    }
    return out;
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static bool _deepEqual(dynamic a, dynamic b) {
    if (identical(a, b)) return true;
    if (a is num && b is num) return a == b;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k) || !_deepEqual(a[k], b[k])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEqual(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  static dynamic _clone(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry('$k', _clone(v)));
    }
    if (value is List) return value.map(_clone).toList();
    return value;
  }
}
