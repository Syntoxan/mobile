import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/auth/auth_user.dart';
import 'package:lichess_mobile/src/network/http.dart';

/// Host of the custom URI scheme callback. Must stay in sync with the
/// intent-filter for `net.openid.appauth.RedirectUriReceiverActivity` in
/// `android/app/src/main/AndroidManifest.xml` and the `CFBundleURLSchemes` entry in `ios/Runner/Info.plist`.
const _kOAuthCustomSchemeCallbackHost = 'login-callback';

/// The custom URI scheme redirect for OAuth.
const kOAuthRedirectUri = '$kLichessCustomUriSchemeName://$_kOAuthCustomSchemeCallbackHost';
const oauthScopes = ['web:mobile'];

/// A provider for [FlutterAppAuth].
final appAuthProvider = Provider<FlutterAppAuth>((Ref ref) {
  return const FlutterAppAuth();
}, name: 'AppAuthProvider');

final authRepositoryProvider = Provider<AuthRepository>((Ref ref) {
  final appAuth = ref.read(appAuthProvider);
  return AuthRepository(ref, appAuth);
}, name: 'AuthRepositoryProvider');

class AuthRepository(final Ref _ref, final FlutterAppAuth _appAuth) {
  LichessClient get _client => _ref.read(lichessClientProvider);

  /// Sign out the current user by revoking the auth token.
  Future<void> signOut() async {
    await _client.deleteRead(Uri(path: '/api/token'));
  }

  /// Check if the given authUser token is valid.
  Future<bool> checkToken(AuthUser authUser) async {
    final defaultClient = _ref.read(defaultClientProvider);
    final data = await defaultClient
        .postReadJson(lichessUri('/api/token/test'), mapper: (json) => json, body: authUser.token)
        .timeout(const Duration(seconds: 5));
    return data[authUser.token] != null;
  }
}
