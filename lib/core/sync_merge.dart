/// Rebase local edits onto a server snapshot without replaying unchanged data.
bool syncEqual(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && syncEqual(a[k], b[k]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(a.length, (i) => i).every((i) => syncEqual(a[i], b[i]));
  }
  return a == b;
}

Object? mergeSyncDelta(Object? server, Object? local, Object? base) {
  if (syncEqual(local, base)) return server;
  if (local is Map && base is Map) {
    final result = <String, dynamic>{
      if (server is Map) ...server.cast<String, dynamic>(),
    };
    for (final key in {...base.keys, ...local.keys}) {
      if (!local.containsKey(key)) {
        if (syncEqual(result[key], base[key])) result.remove(key);
      } else if (!base.containsKey(key) || !syncEqual(local[key], base[key])) {
        result[key as String] = mergeSyncDelta(
          result[key],
          local[key],
          base[key],
        );
      }
    }
    return result;
  }
  if (local is List &&
      base is List &&
      [...local, ...base].every((v) => v is Map && v['id'] is String)) {
    Map<String, dynamic> indexed(List rows) => {
      for (final row in rows.whereType<Map>())
        if (row['id'] is String) row['id'] as String: row,
    };
    final old = indexed(base),
        next = indexed(local),
        live = indexed(server is List ? server : []);
    for (final key in old.keys.where((k) => !next.containsKey(k))) {
      if (syncEqual(live[key], old[key])) live.remove(key);
    }
    for (final key in next.keys) {
      if (!old.containsKey(key) || !syncEqual(next[key], old[key])) {
        live[key] = mergeSyncDelta(live[key], next[key], old[key]);
      }
    }
    final order = {...next.keys, ...live.keys};
    return [
      for (final key in order)
        if (live.containsKey(key)) live[key],
    ];
  }
  return local;
}
