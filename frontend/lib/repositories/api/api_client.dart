import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config.dart';
import '../../models/user.dart';
import '../repository_exception.dart';

/// Thin HTTP layer shared by the three API repositories.
///
/// Responsibilities kept here rather than in each repository:
///  * base URL, JSON encoding, `Authorization` header
///  * turning a non-2xx response into [RepositoryException] with its status
///    code, so the Blocs keep the error handling they already have
///  * refresh-token rotation — one retry on 401, de-duplicated so that several
///    requests failing at once do not each burn a refresh token (the backend
///    revokes a refresh token the moment it is used, so a second concurrent
///    refresh would sign the user out).
class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        // A trailing slash would produce '//api/...' once a path is appended.
        _baseUrl = _stripTrailingSlash(baseUrl ?? AppConfig.apiBaseUrl);

  static String _stripTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  final http.Client _http;
  final String _baseUrl;

  static const _accessKey = 'auth_access_token';
  static const _refreshKey = 'auth_refresh_token';
  static const _userKey = 'auth_session_user';

  String? _accessToken;
  String? _refreshToken;
  AppUser? _user;
  Future<bool>? _refreshInFlight;

  /// The signed-in account as of the last login/refresh, or null.
  AppUser? get currentUser => _user;

  /// True once a token pair is held — after login, or after [loadSession]
  /// restored one from a previous run.
  bool get isSignedIn => _accessToken != null;

  /// Staff and admin hit the back-office endpoints, which return every record
  /// rather than only the caller's own.
  bool get isStaffSide => _user?.role.isStaffSide ?? false;

  // ---- Requests ---------------------------------------------------------

  Future<dynamic> get(String path, {Map<String, String>? query, bool auth = true}) =>
      _send('GET', path, query: query, auth: auth);

  Future<dynamic> post(String path, {Object? body, bool auth = true}) =>
      _send('POST', path, body: body, auth: auth);

  Future<dynamic> patch(String path, {Object? body, bool auth = true}) =>
      _send('PATCH', path, body: body, auth: auth);

  Future<dynamic> delete(String path, {bool auth = true}) =>
      _send('DELETE', path, auth: auth);

  /// Base URL, exposed so repositories can build absolute URLs for resources
  /// loaded outside this client (e.g. a public image in an `Image.network`).
  String get baseUrl => _baseUrl;

  /// Photos the backend stores come back as API paths (`/api/...`); those get
  /// the base URL prepended. Bundled asset paths (`image/...`) and full URLs
  /// pass through unchanged, so AppImage can tell them apart.
  String resolveMediaUrl(String url) =>
      url.startsWith('/api/') ? '$_baseUrl$url' : url;

  /// The reverse of [resolveMediaUrl], for sending a URL back to be stored.
  /// The base URL differs per device (10.0.2.2 on the emulator, a LAN IP on a
  /// phone), so only the API path may be saved.
  String toStoredMediaUrl(String url) =>
      url.startsWith('$_baseUrl/api/') ? url.substring(_baseUrl.length) : url;

  /// Uploads a single file as `multipart/form-data`. Mirrors [_send]'s auth and
  /// one-shot 401 refresh, but a multipart request cannot be replayed once its
  /// stream is read, so each attempt rebuilds the request.
  Future<dynamic> multipart(
    String path, {
    required String field,
    required List<int> bytes,
    required String filename,
    bool auth = true,
  }) async {
    Future<http.Response> attempt() async {
      final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl$path'))
        ..headers['Accept'] = 'application/json';
      if (auth && _accessToken != null) {
        request.headers['Authorization'] = 'Bearer $_accessToken';
      }
      request.files.add(http.MultipartFile.fromBytes(
        field,
        bytes,
        filename: filename,
        contentType: _mediaTypeFor(filename),
      ));
      return http.Response.fromStream(await _http.send(request));
    }

    http.Response response;
    try {
      response = await attempt();
    } on Object catch (e) {
      throw RepositoryException('ติดต่อเซิร์ฟเวอร์ไม่ได้: $e');
    }

    if (response.statusCode == 401 && auth && _refreshToken != null) {
      if (await _refreshTokens()) {
        try {
          response = await attempt();
        } on Object catch (e) {
          throw RepositoryException('ติดต่อเซิร์ฟเวอร์ไม่ได้: $e');
        }
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    throw _toException(response);
  }

  /// GET returning the raw bytes of a resource (e.g. a slip image behind auth),
  /// with the same one-shot 401 refresh as [_send].
  Future<Uint8List> getBytes(String path, {bool auth = true}) async {
    Future<http.Response> attempt() async {
      final request = http.Request('GET', Uri.parse('$_baseUrl$path'))
        ..headers['Accept'] = '*/*';
      if (auth && _accessToken != null) {
        request.headers['Authorization'] = 'Bearer $_accessToken';
      }
      return http.Response.fromStream(await _http.send(request));
    }

    http.Response response;
    try {
      response = await attempt();
    } on Object catch (e) {
      throw RepositoryException('ติดต่อเซิร์ฟเวอร์ไม่ได้: $e');
    }

    if (response.statusCode == 401 && auth && _refreshToken != null) {
      if (await _refreshTokens()) {
        try {
          response = await attempt();
        } on Object catch (e) {
          throw RepositoryException('ติดต่อเซิร์ฟเวอร์ไม่ได้: $e');
        }
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    throw _toException(response);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool auth = true,
    bool isRetry = false,
  }) async {
    final uri = Uri.parse('$_baseUrl$path')
        .replace(queryParameters: (query == null || query.isEmpty) ? null : query);

    final request = http.Request(method, uri)
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (auth && _accessToken != null) {
      request.headers['Authorization'] = 'Bearer $_accessToken';
    }

    http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request));
    } on Object catch (e) {
      // SocketException, HandshakeException, ClientException — the app only
      // needs to know the server could not be reached.
      throw RepositoryException('ติดต่อเซิร์ฟเวอร์ไม่ได้: $e');
    }

    // Access tokens live 15 minutes; one silent rotation keeps the user from
    // being bounced to the login screen mid-session.
    if (response.statusCode == 401 && auth && !isRetry && _refreshToken != null) {
      final refreshed = await _refreshTokens();
      if (refreshed) {
        return _send(method, path, body: body, query: query, auth: auth, isRetry: true);
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.statusCode == 204 || response.body.isEmpty) return null;
      return jsonDecode(utf8.decode(response.bodyBytes));
    }

    throw _toException(response);
  }

  RepositoryException _toException(http.Response response) {
    String message = 'คำขอล้มเหลว (${response.statusCode})';
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['message'] != null) {
        final m = decoded['message'];
        // Nest's ValidationPipe returns an array of messages.
        message = m is List ? m.join('\n') : m.toString();
      }
    } on FormatException {
      // Non-JSON error body (proxy, gateway) — keep the generic message.
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      return AuthException(message, statusCode: response.statusCode);
    }
    return RepositoryException(message, statusCode: response.statusCode);
  }

  // ---- Token lifecycle --------------------------------------------------

  Future<bool> _refreshTokens() {
    // Collapse concurrent refreshes onto one in-flight call.
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _doRefresh() async {
    final token = _refreshToken;
    if (token == null) return false;
    try {
      final data = await _send(
        'POST',
        '/api/auth/refresh',
        body: {'refreshToken': token},
        auth: false,
        isRetry: true,
      );
      await saveSession(data as Map<String, dynamic>);
      return true;
    } on RepositoryException {
      // The refresh token was revoked or expired — the session is over.
      await clearSession();
      return false;
    }
  }

  /// Stores the `{accessToken, refreshToken, user}` payload returned by
  /// register / login / refresh.
  Future<AppUser> saveSession(Map<String, dynamic> payload) async {
    _accessToken = payload['accessToken'] as String;
    _refreshToken = payload['refreshToken'] as String;
    _user = userFromJson(payload['user'] as Map<String, dynamic>);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, _accessToken!);
    await prefs.setString(_refreshKey, _refreshToken!);
    await prefs.setString(_userKey, jsonEncode(payload['user']));
    return _user!;
  }

  /// Reloads tokens written by a previous app run. Returns the remembered
  /// account without contacting the server; [ApiAuthRepository.restoreSession]
  /// then verifies it against `/api/auth/me`.
  Future<AppUser?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_accessKey);
    _refreshToken = prefs.getString(_refreshKey);
    final raw = prefs.getString(_userKey);
    if (raw == null) return null;
    _user = userFromJson(jsonDecode(raw) as Map<String, dynamic>);
    return _user;
  }

  Future<void> clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_userKey);
  }

  /// The raw refresh token, needed by `POST /api/auth/logout`.
  String? get refreshToken => _refreshToken;

  void setCurrentUser(AppUser user) => _user = user;
}

/// Shared mapper — the API returns the same user shape from several endpoints.
AppUser userFromJson(Map<String, dynamic> json) {
  return AppUser(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    phone: (json['phone'] as String?) ?? '',
    // The API never returns a password, and AppUser.password only exists for
    // the mock login check. Nothing reads it once the real API is wired up.
    password: '',
    role: roleFromString(json['role'] as String?),
  );
}

MediaType _mediaTypeFor(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png')) return MediaType('image', 'png');
  if (lower.endsWith('.webp')) return MediaType('image', 'webp');
  return MediaType('image', 'jpeg');
}

UserRole roleFromString(String? value) {
  return UserRole.values.firstWhere(
    (r) => r.name == value,
    orElse: () => UserRole.customer,
  );
}

/// The API stores check-in/check-out as calendar dates, not instants.
String ymd(DateTime date) {
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '${date.year}-$m-$d';
}
