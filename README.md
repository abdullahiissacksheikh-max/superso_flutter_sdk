# superso_flutter_sdk

Official Flutter SDK for **Superso Core** — a unified backend platform providing
Auth, Database, Storage, Realtime, Media, Notifications, Payments, and AI behind
a single strongly-typed client.

This package is the Dart/Flutter counterpart to the official JavaScript SDK
(`supersosdk`). It mirrors that SDK module for module and endpoint for endpoint,
adapted to idiomatic Dart.

---

## Status

All eight modules are ported. Endpoint parity with the JavaScript SDK is
**136 / 136**, verified by extracting every endpoint from both codebases and
diffing them.

| Module | State |
|---|---|
| Core (config, HTTP client, errors, types, utils, interfaces) | ✅ Complete |
| `auth` | ✅ Complete |
| `database` | ✅ Complete |
| `storage` | ✅ Complete |
| `realtime` | ✅ Complete |
| `media` | ✅ Complete |
| `notification` | ✅ Complete |
| `payment` | ✅ Complete |
| `ai` | ✅ Complete |

Where the JavaScript SDK deliberately omits an operation because no
`X-API-Key` route exists for it — Admin-Dashboard-only surfaces such as
storage usage, media analytics, or payment logs — this SDK omits it too, and
says so in the relevant class documentation. Shipping a method that reliably
404s would be worse than not shipping it.

---

## Install

```yaml
dependencies:
  superso_flutter_sdk: ^0.3.0
```

---

## Quick start

```dart
import 'package:superso_flutter_sdk/superso_flutter_sdk.dart';

final superso = Superso(
  baseUrl: 'https://api.superso.io/v1',
  apiKey: 'sp_live_xxxxxxxxx',
);
```

Create the instance **once** for the app's lifetime — a provider, a
service-locator singleton, or an `InheritedWidget` — and call
`superso.dispose()` when it is no longer needed.

---

## Auth

Tokens are captured automatically on every authentication call. You never need
to call `setAccessToken()` by hand after a successful sign-in.

```dart
// Email + password
final res = await superso.auth.login(
  email: 'ada@example.com',
  password: 'correct horse battery staple',
);
print(res.data.user.id);

// Register
await superso.auth.register(
  email: 'ada@example.com',
  password: 'correct horse battery staple',
  name: 'Ada Lovelace',
  options: const RegisterOptions(sendWelcomeEmail: true),
);

// Passwordless phone
await superso.auth.phone.sendOtp(phone: '+252612345678');
await superso.auth.phone.login(phone: '+252612345678', code: '123456');

// Current user, profile, sign-out
final me = await superso.auth.me();
await superso.auth.profile.update(
  const UpdateProfileRequest(fullName: 'Ada L.', timezone: 'Africa/Mogadishu'),
);
await superso.auth.logout();
```

### Reacting to auth state

```dart
StreamBuilder<AuthState>(
  stream: superso.auth.authStateChanges,
  builder: (context, snapshot) => (snapshot.data?.isSignedIn ?? false)
      ? const HomeScreen()
      : const LoginScreen(),
);
```

### Restoring a session at app start

The SDK deliberately does not persist tokens itself — where they are stored
(`flutter_secure_storage`, Keychain, an encrypted database) is an application
security decision. Restore them yourself:

```dart
final saved = await secureStorage.read(key: 'access_token');
if (saved != null) {
  superso.auth.restoreSession(accessToken: saved);
}
```

### Password recovery

```dart
await superso.auth.password.forgot('ada@example.com');
await superso.auth.password.reset(
  email: 'ada@example.com',
  code: '123456',
  newPassword: 'a new passphrase',
);
```

### OAuth

`GET /auth/google` requires the `x-api-key` header, which a plain browser
navigation cannot attach. Proxy the redirect through your own backend:

```dart
final url = superso.auth.google.signInUrl();
// Your backend attaches x-api-key and 302s to `url`; the app opens that route,
// then receives tokens back on a deep link:
superso.auth.tokens
  ..setAccessToken(accessToken)
  ..setRefreshToken(refreshToken);
```

---

## Database

### Fluent queries

```dart
final page = await superso.database
    .collection('posts')
    .where('published', WhereOperator.equal, true)
    .where('score', WhereOperator.between, 10, 100)
    .orderBy('created_at', OrderByDirection.desc)
    .limit(20)
    .get();

for (final doc in page.data.items) {
  print('${doc.docId}: ${doc.data['title']}');
}
if (page.data.hasMore) {
  // Paginate with the returned cursor.
  await superso.database
      .collection('posts')
      .startAfter(page.data.items.last.docId)
      .limit(20)
      .get();
}
```

### Document CRUD

```dart
final created = await superso.database.documents.create('posts', {
  'title': 'Hello',
  'created': serverTimestamp(),
});

// ALWAYS use docId — never `id` — for follow-up operations.
final id = created.data.docId;

await superso.database.documents.patch('posts', id, {'views': increment(1)});
await superso.database.documents.set('posts', id, {'title': 'Replaced'});
final exists = await superso.database.documents.exists('posts', id);
await superso.database.documents.delete('posts', id);   // soft-delete
await superso.database.documents.restore('posts', id);  // recoverable
```

> **`id` vs `docId`** — both look like UUIDs by default. `docId` is the only
> valid lookup key; `id` is the internal row UUID and passing it where `docId`
> is expected fails with `DocumentNotFoundError`.

### Counting and existence

```dart
final count = await superso.database
    .collection('posts')
    .where('published', WhereOperator.equal, true)
    .count();
print('${count.data.count} of ${count.data.total}');
```

### Batches and transactions

```dart
// Independent writes — partial success is possible.
await superso.database.batch([
  const DatabaseBatchOperation(
    operation: DatabaseBatchOperationType.create,
    collection: 'posts',
    data: {'title': 'A'},
  ),
  const DatabaseBatchOperation(
    operation: DatabaseBatchOperationType.delete,
    collection: 'posts',
    docId: 'old-doc',
  ),
]);

// All-or-nothing — rolls back entirely on any failure.
await superso.database.transaction([...]);
```

### Diagnosing a slow query

```dart
final page = await superso.database
    .collection('posts')
    .where('author', WhereOperator.equal, 'ada')
    .explain()
    .get();

final plan = page.data.explain!;
print('${plan.scanType}, ${plan.executionMs}ms');
print(plan.recommendedIndex); // non-null when an index would help
```

---

## Storage

```dart
final bucket = await superso.storage.bucket.create(
  const CreateBucketRequest(
    name: 'avatars',
    provider: StorageProviderName.cloudinary,
  ),
);

// Upload. Pass raw bytes — Dart has no single cross-platform file type
// (dart:io's File does not exist on Web), so bytes are the one representation
// that works identically everywhere.
final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
final uploaded = await superso.storage.file.upload(
  bytes: await picked!.readAsBytes(),
  filename: picked.name,
  options: UploadFileOptions(bucketId: bucket.data.id, tags: ['avatar']),
);
print(uploaded.data.cdnUrl);

// Chunked upload for files over 100 MB, with a progress stream
final session = await superso.storage.uploads.create(
  bucketId: bucket.data.id,
  fileName: 'movie.mp4',
  mimeType: 'video/mp4',
  totalSize: bytes.length,
  chunkSize: 5 * 1024 * 1024,
);
superso.storage.uploads
    .watch(session.data.id)
    .listen((s) => print('${(s.progress * 100).toStringAsFixed(0)}%'));

// Realtime file events
superso.storage.onUploaded.listen((file) => print('new: ${file.name}'));
```

---

## Realtime

```dart
await superso.realtime.connect();
await superso.realtime.subscribe('database:posts');

superso.realtime.events.listen((frame) {
  print('${frame.channel}: ${frame.event}');
});

// Typed database bridge — no hand-built channel names
final posts = superso.realtime.databaseCollection('posts');
await posts.subscribe();
posts.onDocumentCreated.listen((e) => print('created ${e.docId}'));

// Presence
await superso.realtime.online('presence/lobby', metadata: {'name': 'Ada'});
final present = await superso.realtime.getPresence('presence/lobby');

// Broadcast
await superso.realtime.publish(
  channel: 'broadcast/chat',
  event: 'message.sent',
  data: {'text': 'hello'},
);
```

Reconnection is automatic with exponential backoff. Watch
`onConnectionStateChanged` to drive a connection indicator, and check
`clientInfo?.authenticated` — a `false` there means the connection is a guest,
which is the usual explanation for missing user-scoped events.

---

## Media

```dart
final session = await superso.media.sessions.create(title: 'Standup');
await superso.media.sessions.start(session.data.id);

// Realtime session events
superso.media
    .on(session.data.id, MediaParticipantEvents.joined)
    .listen((e) => print('${e.asParticipant.displayName} joined'));

// Host moderation — requires the host to be signed in
await superso.media.moderation.mute(sessionId, participantId);
await superso.media.moderation.spotlight(sessionId, participantId);
await superso.media.moderation
    .assignRole(sessionId, participantId, ClassroomRole.coHost);

// Whiteboard
final board = await superso.media.whiteboard.start(
  sessionId,
  allowParticipantDraw: true,
);
await superso.media.whiteboard.draw(
  sessionId: sessionId,
  participantId: participantId,
  whiteboardId: board.data.id,
  objectId: 'stroke-1',
  points: [{'x': 10, 'y': 10}, {'x': 20, 'y': 30}],
);

// Late join / reconnect: replay the log to rebuild the exact canvas
final log = await superso.media.whiteboard.listActions(sessionId, board.data.id);
for (final action in log.data.actions) applyToCanvas(action);
```

> **Moderation needs a host, not just an API key.** Every method on
> `media.moderation` requires an end-user access token belonging to that
> session's host, teacher, co-host, or moderator. A caller without standing
> gets a `HostAuthorizationError`. A session's creator becomes its host
> automatically on first join, provided they were signed in when it was
> created.

---

## Notifications

```dart
// Register for push
await superso.notification.devices.register(
  userId: user.id,
  deviceToken: fcmToken,
  platform: DevicePlatform.android,
);

await superso.notification.send(
  channel: NotificationChannel.push,
  recipientId: user.id,
  title: 'Order shipped',
  body: 'Your order is on its way.',
);

final inbox = await superso.notification.inbox.list(userId: user.id);
print('${inbox.data.unreadCount} unread');
await superso.notification.inbox.read(inbox.data.items.first.id);
```

---

## Payments

```dart
// WaafiPay family. Omit `currency` — the backend resolves the merchant's
// configured currency, which is the single source of truth.
final result = await superso.payment.purchase(
  accountNo: '252615000000',
  amount: 10.50,
);
if (result.data.isApproved) { /* ... */ }

// Hosted payment page, with a live status stream
final hpp = await superso.payment.hpp.purchase(
  accountNo: '252615000000',
  amount: 10.50,
);
launchUrl(Uri.parse(hpp.data.hppUrl!));
superso.payment
    .watch(transactionId: hpp.data.transactionId)
    .listen((r) => print(r.status.wireValue));

// Stripe — hand the client secret to flutter_stripe; card details never
// touch your server or this package.
final intent = await superso.payment.stripe.createPaymentIntent(
  amountMinor: 1050,
  orderId: 'order-123',
);
```

> An unrecognized payment status decodes as `pending`, never `declined` —
> a status the SDK does not know must never be mistaken for a definitive
> failure, or you could double-charge or wrongly refund.

---

## AI

```dart
final reply = await superso.ai.complete('Write a haiku about the ocean.');

final response = await superso.ai.chat(
  messages: [const ChatMessage.user('Explain CRDTs briefly.')],
  provider: 'anthropic',
);
print('${response.data.text} (${response.data.totalTokens} tokens)');

// Stateful multi-turn conversation
final chat = superso.ai.session(systemPrompt: 'You are a terse assistant.');
print(await chat.send('What does Iterable.fold do?'));
print(await chat.send('Show me an example.'));
```

---

## Error handling

Every failure is a `SupersoError` subclass. Switch on the type, or on
`error.code` for the machine-readable identifier.

```dart
try {
  await superso.database.documents.get('posts', id);
} on DocumentNotFoundError {
  // 404 with error.code == 'DOCUMENT_NOT_FOUND'
} on PermissionError catch (e) {
  // 403 — e.details carries required_permission / granted_permissions
  // when the rejection came from the API-key scope check.
  print(e.details);
} on NetworkError {
  // Never reached the server.
} on SupersoError catch (e) {
  print('${e.code}: ${e.message}');
}
```

| Class | Status | Meaning |
|---|---|---|
| `ValidationError` | 400 / 422 | Payload failed validation |
| `AuthenticationError` | 401 | Missing / invalid / expired credentials |
| `PermissionError` | 403 | Authenticated but not authorized |
| `NotFoundError` | 404 | Resource does not exist |
| `ConflictError` | 409 | Already exists |
| `RateLimitError` | 429 | Too many requests |
| `ServerError` | 5xx | Server-side failure |
| `NetworkError` | — | Never reached the server |
| `CancelledError` | — | Aborted via a `CancelToken` |

---

## Cancellation

Dart has no `AbortSignal`; `CancelToken` is the equivalent. Pass one token to
any number of requests and cancel them all at once — useful in `dispose()`.

```dart
final token = CancelToken();

@override
void dispose() {
  token.cancel('screen closed');
  super.dispose();
}

await superso.database.documents.list(
  'posts',
  // ...
);
```

---

## Retries, timeouts, logging, interceptors

Unlike the JS SDK — where `fetch` is called once and any failure surfaces
immediately — this SDK retries by default, because a request issued while a
phone switches between Wi-Fi and cellular fails for reasons that resolve on
their own. Retries are restricted to cases where they are provably safe:
transport failures and 5xx/429 responses **on idempotent verbs only**. A `POST`
that reached the server is never retried.

```dart
final superso = Superso(
  baseUrl: '...',
  apiKey: '...',
  timeout: const Duration(seconds: 15),
  retryPolicy: const RetryPolicy(maxAttempts: 4),
  // retryPolicy: RetryPolicy.none,  // match the JS SDK exactly
  logger: (level, message, [error]) => debugPrint('[$level] $message'),
);

superso.config.addRequestInterceptor((request) async {
  request.headers['x-trace-id'] = newTraceId();
  return request;
});
```

---

## Relationship to the JavaScript SDK

| JavaScript | Dart |
|---|---|
| structural `interface` | immutable class + `fromJson` / `toJson` |
| `Promise<T>` | `Future<T>` |
| callback subscriptions | `Stream<T>` |
| `AbortSignal` | `CancelToken` |
| `snake_case` model fields | `camelCase` properties, `snake_case` on the wire |
| garbage-collected sockets | explicit `dispose()` |
| no retry layer | `RetryPolicy`, safe verbs only |

Endpoint paths, request bodies, response shapes, and error codes are **identical**
— the two SDKs speak the same protocol to the same backend.

---

## Testing

```bash
flutter pub get
flutter analyze
flutter test
```

---

## License

MIT — see [LICENSE](LICENSE).
