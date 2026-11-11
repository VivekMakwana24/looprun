import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredSession {
  const StoredSession({required this.token, required this.userId, required this.userName});
  final String token;
  final String userId;
  final String userName;
}

abstract class TokenStore {
  Future<StoredSession?> read();
  Future<void> write(StoredSession session);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage]) : _s = storage ?? FlutterSecureStorage();
  final FlutterSecureStorage _s;

  static const _kToken = 'looprun_token';
  static const _kId = 'looprun_user_id';
  static const _kName = 'looprun_user_name';

  @override
  Future<StoredSession?> read() async {
    try {
      final token = await _s.read(key: _kToken);
      if (token == null || token.isEmpty) return null;
      final id = await _s.read(key: _kId) ?? '';
      final name = await _s.read(key: _kName) ?? '';
      return StoredSession(token: token, userId: id, userName: name);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(StoredSession session) async {
    await _s.write(key: _kToken, value: session.token);
    await _s.write(key: _kId, value: session.userId);
    await _s.write(key: _kName, value: session.userName);
  }

  @override
  Future<void> clear() async {
    await _s.delete(key: _kToken);
    await _s.delete(key: _kId);
    await _s.delete(key: _kName);
  }
}

/// Used in tests and previews.
class InMemoryTokenStore implements TokenStore {
  InMemoryTokenStore([this._session]);
  StoredSession? _session;

  @override
  Future<StoredSession?> read() async => _session;

  @override
  Future<void> write(StoredSession session) async {
    _session = session;
  }

  @override
  Future<void> clear() async {
    _session = null;
  }
}
