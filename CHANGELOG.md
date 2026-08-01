# Changelog

All notable changes to `superso_flutter_sdk` are documented in this file.

## 0.3.0

Initial release of the official Flutter SDK. Version numbering tracks the
JavaScript SDK (`supersosdk`) so a given version of either speaks the same
backend contract.

### Added — core

- **`Superso`** — the single entry point. One instance shares one
  `SupersoConfig` and one `SupersoHttpClient` across every module, so headers,
  base URLs, and token handling are never duplicated.
- **`SupersoHttpClient`** — the only component permitted to build headers,
  resolve URLs, or issue requests. Attaches `x-api-key` and
  `Authorization: Bearer` automatically. Built on `package:http` rather than
  `dart:io` so the SDK works unchanged on Flutter Web.
- **Typed error hierarchy** — `SupersoError` plus `ValidationError`,
  `AuthenticationError`, `PermissionError`, `NotFoundError`, `ConflictError`,
  `RateLimitError`, `ServerError`, `NetworkError`, `CancelledError`. Status
  mapping and `code` values are identical to the JavaScript SDK, so
  error-handling logic ports across unchanged.
- **`CancelToken`** — the Dart equivalent of `AbortSignal`. One token can abort
  any number of in-flight requests.
- **`RetryPolicy`** — automatic retry of transport failures and 5xx/429
  responses, restricted to idempotent verbs. Not present in the JavaScript SDK;
  added because mobile clients routinely fail requests for reasons that resolve
  within a second (Wi-Fi/cellular handover). `RetryPolicy.none` restores the
  JavaScript SDK's single-attempt behaviour exactly.
- **Interceptors and logging** — `addRequestInterceptor`,
  `addResponseInterceptor`, and a `SupersoLogger`. The SDK never writes to the
  console uninvited.
- **`dispose()`** — explicit teardown of the connection pool and stream
  controllers, so a Flutter `State` cannot leak them.

### Added — auth

Full parity with `supersosdk/src/auth`:

- `login`, `register`, `logout`, `refresh`, `me`, `deleteAccount`
- `auth.email.*` — register, login, send/verify verification, change and
  confirm-change, generic send/verify OTP
- `auth.phone.*` — passwordless send/verify OTP, login, change and
  confirm-change
- `auth.password.*` — forgot and reset
- `auth.profile.update`
- `auth.users.*` — list, get, update, delete, disable, enable
- `auth.google` / `auth.facebook` — OAuth URL resolution
- `auth.tokens.*` — token accessors
- **Automatic session capture** — every token-returning call stores its tokens
  on the shared client, so an authenticated user is never silently downgraded
  to a guest. Ports the JavaScript SDK's v0.2.8 fix.
- **`authStateChanges`** — a broadcast `Stream<AuthState>` for `StreamBuilder`.
  No JavaScript counterpart; added because Flutter apps almost always need to
  rebuild on sign-in state.
- **`restoreSession()`** — rehydrate a persisted session without a network call.

### Added — database

Full parity with `supersosdk/src/database`:

- `database.collections.*` — list, create, get, rename, delete
- `database.documents.*` — create, get, set, update, patch, delete, restore,
  exists, list
- **Fluent `QueryBuilder`** — `where`, `orderBy`, `limit`, `offset`, `select`,
  `startAfter`, `startAt`, `distinct`, `explain`, terminating in `get`, `count`,
  or `exists`
- All 23 documented `where` operators as a type-safe `WhereOperator` enum
- `batch`, `transaction`, `bulkUpsert`
- `serverTimestamp()` and `increment()` sentinels
- Database-specific errors mapped from the documented `error.code`:
  `CollectionNotFoundError`, `DocumentNotFoundError`, `PermissionDeniedError`,
  `TransactionFailedError`, `ReservedFieldConflictError`,
  `QueryPatternInvalidError`, `CollectionLimitReachedError`,
  `IndexRequiredError`
- Client-side rejection of batches exceeding the documented 500-operation limit,
  rather than letting the server reject the whole request

### Added — storage

Full parity with `supersosdk/src/storage`: `bucket` CRUD, `file`
upload/list/get/delete, chunked upload sessions, and realtime `file.uploaded` /
`file.deleted` streams. Storage-specific errors (`BucketError`, `UploadError`,
`QuotaExceededError`, `MultipartError`, `StorageProviderError`), with `413`
always mapping to a quota error and `415` always to a multipart error.

Two Dart-specific adaptations, both forced by platform differences:

- **`upload` takes raw bytes plus an explicit filename**, not a `File`. Dart
  has no single cross-platform file type — `dart:io`'s `File` does not exist on
  Web — so bytes are the one representation that works identically on mobile,
  desktop, and Web. Content type is inferred from the extension, with an
  explicit override available.
- **`uploads.watch()`** returns a progress `Stream`; the JavaScript SDK leaves
  polling to the caller.

`file.download()` is additive: the browser SDK hands `cdnUrl` to an `<img>`
tag, but a Flutter app usually needs the bytes.

### Added — realtime

Full parity with `supersosdk/src/realtime`: connection lifecycle, channel
subscribe/unsubscribe, presence (set/online/away/busy/invisible/read),
broadcast publish, the REST fallback client, and the typed database bridge via
`databaseCollection()` / `databaseDocument()`.

Where the JavaScript SDK uses an emitter (`on(event, handler)`), this exposes
typed `Stream`s. A `StreamSubscription` already provides cancellation and works
directly with `StreamBuilder`, so an emitter would be redundant and less
idiomatic. Request/acknowledgement correlation, heartbeats, and
exponential-backoff reconnection are handled by a shared `RealtimeSocket` used
internally by realtime, storage, and media — the JavaScript SDK duplicates this
logic per module, which in Dart would guarantee the copies drift.

### Added — media

Full parity with `supersosdk/src/media`, the largest module: sessions,
participants, telemetry, self-service permissions, all 26 host moderation
routes, the complete whiteboard drawing engine (strokes, shapes, text, erase,
clear, per-participant undo/redo, live pointer, replay-log sync), the classroom
engine (reactions, polls, chat, speaker queue, attendance, hand raising), voice
rooms, breakout rooms, waiting room, lobby chat, invitations, share links,
overview, usage, and settings.

Realtime session events are exposed as `media.events(sessionId)` and
`media.on(sessionId, eventName)`, with the complete verified event catalogue in
`media_events.dart`. `HostAuthorizationError` and `WhiteboardPermissionError`
make the two most common 403s self-explaining.

### Added — notification

Full parity with `supersosdk/src/notification`: send, broadcast, trigger, the
complete 18-method inbox surface, templates, schedules (with `pause`/`resume`
shorthands), queue inspection, device registration, preferences, providers,
logs, and analytics.

### Added — payment

Full parity with `supersosdk/src/payment`: all 10 WaafiPay-family routes
(purchase, reversal, preauthorize, commit, cancel, status, transaction lookup,
HPP purchase, refund, gateway discovery) and all 7 Stripe routes (payment
intents create/get/capture/cancel, customers create/get, setup intents,
checkout sessions, refunds).

`waitForCompletion()` and `watch()` are additive polling helpers — a `Future`
and a `Stream` are what a Dart caller awaiting a payment actually wants.

An unrecognized `PaymentStatus` decodes as `pending`, never `declined`: a
status the SDK does not know must never be mistaken for a definitive failure,
since that could trigger a double charge or a wrong refund.

### Added — ai

Full parity with `supersosdk/src/ai`: `chat`, `complete`, stateful multi-turn
`session()`, and the static provider and model reference lookups. The
`choices` and `usage` convenience views are synthesized client-side from the
backend's flat response, exactly as the JavaScript SDK does.

### Parity

Endpoint parity with the JavaScript SDK is **136 / 136**, verified by
extracting every endpoint from both codebases and diffing them. One genuine gap
was found and closed during that audit: `POST /v1/stripe/payment-intents/:piId/cancel`.

Operations the JavaScript SDK deliberately omits — Admin-Dashboard-only
surfaces such as storage usage, media analytics, payment logs, and AI
usage/limits — are omitted here too, and the reason is documented on the
relevant class. Their data shapes are still declared where the JavaScript SDK
declares them, so consumers receiving one through another channel have a type.

### Verification

Written to Dart 3 / strict-analysis standards (`strict-casts`,
`strict-inference`, `strict-raw-types`, `public_member_api_docs: error`).
`flutter analyze` and `flutter test` were **not** run — no Dart or Flutter
toolchain was available in the authoring environment, and the SDK download is
blocked by that environment's network allowlist. Run both locally before
publishing.
