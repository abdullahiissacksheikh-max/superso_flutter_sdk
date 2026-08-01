/// OAuth redirect helpers (Google, Facebook).
///
/// Dart port of `supersosdk/src/auth/google.ts` and `facebook.ts`, merged into
/// one file because the two classes differ only by their endpoint path.
library;

import '../client/superso_http_client.dart';

/// Base for the provider OAuth helpers.
///
/// `GET /auth/google` and `GET /auth/facebook` both require the `x-api-key`
/// header, which a plain browser navigation cannot attach. Per the
/// documentation's recommended pattern, proxy this redirect through your own
/// backend rather than opening [signInUrl] directly.
///
/// On Flutter, the practical flow is:
///
/// ```dart
/// // 1. Your backend exposes a route that attaches x-api-key and 302s to
/// //    superso.auth.google.signInUrl().
/// // 2. The app opens that route in a browser tab / custom tab.
/// // 3. The provider redirects back to your app's deep link with tokens.
/// // 4. Hand them to the SDK:
/// superso.auth.tokens
///   ..setAccessToken(accessToken)
///   ..setRefreshToken(refreshToken);
/// ```
///
/// The SDK deliberately does not bundle a browser/deep-link dependency —
/// `url_launcher` and `app_links` are application choices, and forcing them on
/// every consumer would bloat apps that never use social sign-in.
abstract class OAuthModule {
  /// Creates an OAuth helper bound to [client] for [providerPath].
  const OAuthModule(this._client, this.providerPath);

  final SupersoHttpClient _client;

  /// The API path that starts this provider's flow, e.g. `/auth/google`.
  final String providerPath;

  /// Resolves the absolute URL that starts the OAuth consent flow.
  String signInUrl() => _client.resolveUrl(providerPath);
}

/// Implements §7 Google OAuth from `docs/auth.md`.
///
/// Exposed at `superso.auth.google`.
class GoogleAuthModule extends OAuthModule {
  /// Creates the Google OAuth helper.
  const GoogleAuthModule(SupersoHttpClient client)
      : super(client, '/auth/google');
}

/// Implements §8 Facebook OAuth from `docs/auth.md`.
///
/// Exposed at `superso.auth.facebook`.
class FacebookAuthModule extends OAuthModule {
  /// Creates the Facebook OAuth helper.
  const FacebookAuthModule(SupersoHttpClient client)
      : super(client, '/auth/facebook');
}
