import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Token 安全存储。按服务器档案隔离，避免多服务器串号。
abstract interface class TokenStore {
  Future<String?> read(String serverId);
  Future<void> write(String serverId, String token);
  Future<void> delete(String serverId);
  Future<void> deleteAll();
}

class SecureTokenStore implements TokenStore {
  const SecureTokenStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const _prefix = 'auth.token.v1.';

  String _key(String serverId) {
    final encoded = base64Url.encode(utf8.encode(serverId));
    return '$_prefix$encoded';
  }

  @override
  Future<String?> read(String serverId) => _storage.read(key: _key(serverId));

  @override
  Future<void> write(String serverId, String token) =>
      _storage.write(key: _key(serverId), value: token);

  @override
  Future<void> delete(String serverId) =>
      _storage.delete(key: _key(serverId));

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

/// 测试可用内存实现替换。
class InMemoryTokenStore implements TokenStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String serverId) async => _values[serverId];

  @override
  Future<void> write(String serverId, String token) async {
    _values[serverId] = token;
  }

  @override
  Future<void> delete(String serverId) async {
    _values.remove(serverId);
  }

  @override
  Future<void> deleteAll() async {
    _values.clear();
  }
}

final tokenStoreProvider = Provider<TokenStore>(
  (ref) => const SecureTokenStore(),
);
