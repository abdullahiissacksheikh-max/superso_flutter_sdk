/// Composition root for the Auth module.
///
/// Dart port of `supersosdk/src/auth/auth.ts`.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import '../client/superso_http_client.dart';
import '../interfaces/sdk_module.dart';
import '../types/common.dart';
import 'auth_types.dart';
import 'email_module.dart';
import 'oauth_module.dart';
import 'password_module.dart';
import 'phone_module.dart';
import 'profile_module.dart';
import 'session_module.dart';
import 'tokens_module.dart';
import 'user_module.dart';

/// Emitted by [AuthModule.authStateChanges] whenever the signed-in state
/// changes.
///
/// This has no TypeScript counterpart — the JS SDK is imperative and leaves
/// state propagation to the application. A Flutter app almost always wants to
/// rebuild widgets when auth state changes, so the SDK exposes it as a
/// `Stream` that plugs directly into `StreamBuilder`, matching how
/// `FirebaseAuth.authStateChanges()` behaves.
@immutable
class AuthState {
  /// Creates an auth state.
  const AuthState({required this.isSignedIn, this.user});

  /// The signed-out state.
  static const AuthState signedOut = AuthState(isSignedIn: false);

  /// Whether an access token is currently held.
  final bool isSignedIn;

  /// The signed-in user, when known.
  ///
  /// This is populated by [AuthModule.login], [AuthModule.register], and
  /// [AuthModule.me]; it is `null` after a token is restored from storage
  /// until `me()` is called.
  final AuthUser? user;

  @override
  String toString() => 'AuthState(isSignedIn: $isSignedIn, user: ${user?.id})';
}

/// The composition root for every endpoint documented in `docs/auth.md`.
///
/// It exposes the core session methods (register, login, logout, refresh, me,
/// deleteAccount) directly — mirroring the ergonomics of Firebase Auth and
/// Supabase Auth — while every provider-specific concern lives in its own
/// focused submodule:
///
/// ```
/// superso.auth.register()          superso.auth.profile.update()
/// superso.auth.login()             superso.auth.password.forgot()
/// superso.auth.logout()            superso.auth.password.reset()
/// superso.auth.refresh()           superso.auth.email.*
/// superso.auth.me()                superso.auth.phone.*
/// superso.auth.deleteAccount()     superso.auth.google.signInUrl()
/// superso.auth.tokens.*            superso.auth.facebook.signInUrl()
///                                  superso.auth.users.*
/// ```
///
/// Every submodule receives only the shared [SupersoHttpClient] — no submodule
/// builds its own headers, base URL, or `Authorization` logic.
class AuthModule implements SdkModule, Disposable {
  /// Creates the auth module bound to [client].
  AuthModule(this.client)
      : profile = ProfileModule(client),
        password = PasswordModule(client),
        email = EmailModule(client),
        phone = PhoneModule(client),
        google = GoogleAuthModule(client),
        facebook = FacebookAuthModule(client),
        users = UserModule(client),
        tokens = TokensModule(client),
        _session = SessionModule(client);

  @override
  final SupersoHttpClient client;

  /// Profile updates — `PATCH /auth/profile`.
  final ProfileModule profile;

  /// Password recovery — forgot and reset.
  final PasswordModule password;

  /// §6 Email Authentication.
  final EmailModule email;

  /// §9 Phone Authentication (passwordless).
  final PhoneModule phone;

  /// §7 Google OAuth.
  final GoogleAuthModule google;

  /// §8 Facebook OAuth.
  final FacebookAuthModule facebook;

  /// §10 admin-level user management.
  final UserModule users;

  /// Access/refresh token accessors.
  final TokensModule tokens;

  final SessionModule _session;

  final StreamController<AuthState> _authState =
      StreamController<AuthState>.broadcast();

  /// Emits whenever the signed-in state changes.
  ///
  /// ```dart
  /// StreamBuilder<AuthState>(
  ///   stream: superso.auth.authStateChanges,
  ///   builder: (context, snapshot) => snapshot.data?.isSignedIn ?? false
  ///       ? const HomeScreen()
  ///       : const LoginScreen(),
  /// );
  /// ```
  ///
  /// The stream is a broadcast stream, so any number of widgets may listen.
  /// It does not replay the current state to new subscribers — read
  /// [currentState] for that.
  Stream<AuthState> get authStateChanges => _authState.stream;

  /// The current auth state, derived from whether a token is held.
  AuthState get currentState =>
      AuthState(isSignedIn: tokens.hasAccessToken, user: _lastKnownUser);

  AuthUser? _lastKnownUser;

  /// `POST /auth/register` — creates an account and signs the user in.
  Future<ApiResponse<AuthSession>> register({
    required String email,
    required String password,
    String? name,
    RegisterOptions? options,
  }) async {
    final response = await _session.register(
      email: email,
      password: password,
      name: name,
      options: options,
    );
    _emitSignedIn(response.data.user);
    return response;
  }

  /// `POST /auth/login` — authenticates with email and password.
  Future<ApiResponse<AuthSession>> login({
    required String email,
    required String password,
    LoginOptions? options,
  }) async {
    final response = await _session.login(
      email: email,
      password: password,
      options: options,
    );
    _emitSignedIn(response.data.user);
    return response;
  }

  /// `POST /auth/logout` — revokes the session and clears stored tokens.
  Future<ApiResponse<void>> logout([String? refreshToken]) async {
    final response = await _session.logout(refreshToken);
    _lastKnownUser = null;
    _emit(AuthState.signedOut);
    return response;
  }

  /// `POST /auth/refresh` — issues a new access token and rotates the refresh
  /// token.
  Future<ApiResponse<AuthTokens>> refresh([String? refreshToken]) =>
      _session.refresh(refreshToken);

  /// `GET /auth/me` — the currently authenticated user.
  Future<ApiResponse<AuthUser>> me() async {
    final response = await _session.me();
    _emitSignedIn(response.data);
    return response;
  }

  /// `DELETE /auth/account` — irreversibly deletes the current account.
  Future<ApiResponse<void>> deleteAccount() async {
    final response = await _session.deleteAccount();
    tokens.clear();
    _lastKnownUser = null;
    _emit(AuthState.signedOut);
    return response;
  }

  /// Restores a previously persisted session without a network round-trip.
  ///
  /// Call this at app start after reading tokens from secure storage, so the
  /// very first request already carries `Authorization`. Emits a signed-in
  /// [AuthState] with a `null` user; call [me] to populate it.
  ///
  /// The SDK deliberately does not persist tokens itself — where they are
  /// stored (`flutter_secure_storage`, Keychain, an encrypted database) is an
  /// application security decision, and a published SDK should not force one.
  void restoreSession({required String accessToken, String? refreshToken}) {
    tokens.setAccessToken(accessToken);
    if (refreshToken != null) tokens.setRefreshToken(refreshToken);
    _emit(const AuthState(isSignedIn: true));
  }

  void _emitSignedIn(AuthUser user) {
    _lastKnownUser = user;
    _emit(AuthState(isSignedIn: true, user: user));
  }

  void _emit(AuthState state) {
    if (!_authState.isClosed) _authState.add(state);
  }

  @override
  Future<void> dispose() async {
    if (!_authState.isClosed) await _authState.close();
  }
}
