// Per-module coverage: storage, realtime, media, notification, payment, ai.
//
// Core, auth, and database are covered in superso_test.dart.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:superso_flutter_sdk/superso_flutter_sdk.dart';

/// Builds a Superso instance backed by a mock transport, capturing the last
/// request so tests can assert on the URL, method, and body actually sent.
({Superso superso, List<http.Request> requests}) harness(
  Future<http.Response> Function(http.Request request) handler,
) {
  final requests = <http.Request>[];
  final config = SupersoConfig(
    baseUrl: 'https://api.example.test/v1',
    apiKey: 'sp_test_key',
    retryPolicy: RetryPolicy.none,
  );
  final superso = Superso(
    baseUrl: 'https://api.example.test/v1',
    apiKey: 'sp_test_key',
    retryPolicy: RetryPolicy.none,
    httpClient: SupersoHttpClient(
      config,
      httpClient: MockClient((request) {
        requests.add(request);
        return handler(request);
      }),
    ),
  );
  return (superso: superso, requests: requests);
}

http.Response ok(Object? data, {int status = 200}) => http.Response(
      jsonEncode(<String, dynamic>{
        'success': true,
        'message': 'ok',
        'data': data,
      }),
      status,
      headers: <String, String>{'content-type': 'application/json'},
    );

http.Response fail(int status, String code, String message) => http.Response(
      jsonEncode(<String, dynamic>{
        'success': false,
        'error': <String, dynamic>{'code': code, 'message': message},
      }),
      status,
      headers: <String, String>{'content-type': 'application/json'},
    );

Map<String, dynamic> bodyOf(http.Request request) =>
    jsonDecode(request.body) as Map<String, dynamic>;

void main() {
  group('StorageModule', () {
    test('createBucket serializes provider and quota', () async {
      final h = harness((_) async => ok(<String, dynamic>{
            'id': 'b1',
            'name': 'avatars',
            'provider': 'cloudinary',
            'is_unlimited': true,
          }));

      final result = await h.superso.storage.bucket.create(
        const CreateBucketRequest(
          name: 'avatars',
          provider: StorageProviderName.cloudinary,
        ),
      );

      expect(bodyOf(h.requests.single)['provider'], 'cloudinary');
      expect(result.data.isUnlimited, isTrue);
      expect(result.data.provider, StorageProviderName.cloudinary);
      addTearDown(h.superso.dispose);
    });

    test('an empty bucket name is rejected before any request', () {
      final h = harness((_) async => ok(null));
      expect(
        () => h.superso.storage.bucket.create(
          const CreateBucketRequest(
            name: '   ',
            provider: StorageProviderName.s3,
          ),
        ),
        throwsA(isA<ValidationError>()),
      );
      expect(h.requests, isEmpty);
      addTearDown(h.superso.dispose);
    });

    test('makeUnlimited sends an explicit null quota', () async {
      final h = harness((_) async => ok(<String, dynamic>{'id': 'b1'}));
      await h.superso.storage.bucket.update(
        'b1',
        const UpdateBucketRequest(makeUnlimited: true),
      );
      final body = bodyOf(h.requests.single);
      expect(body.containsKey('quota_bytes'), isTrue);
      expect(body['quota_bytes'], isNull);
      addTearDown(h.superso.dispose);
    });

    test('upload sends multipart with the inferred content type', () async {
      final h = harness((_) async => ok(<String, dynamic>{
            'id': 'f1',
            'name': 'photo.jpg',
            'cdn_url': 'https://cdn.test/f1.jpg',
          }));

      final result = await h.superso.storage.file.upload(
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        filename: 'photo.jpg',
        options: const UploadFileOptions(bucketId: 'b1', tags: <String>['a']),
      );

      final request = h.requests.single;
      expect(request.method, 'POST');
      expect(
        request.headers['content-type'],
        startsWith('multipart/form-data'),
      );
      expect(result.data.cdnUrl, 'https://cdn.test/f1.jpg');
      addTearDown(h.superso.dispose);
    });

    test('an empty upload is rejected before any request', () {
      final h = harness((_) async => ok(null));
      expect(
        () => h.superso.storage.file.upload(
          bytes: Uint8List(0),
          filename: 'empty.txt',
          options: const UploadFileOptions(bucketId: 'b1'),
        ),
        throwsA(isA<ValidationError>()),
      );
      addTearDown(h.superso.dispose);
    });

    test('a 413 always becomes QuotaExceededError', () async {
      final h = harness((_) async => fail(413, 'QUOTA_EXCEEDED', 'too big'));
      await expectLater(
        h.superso.storage.file.list('b1'),
        throwsA(isA<QuotaExceededError>()),
      );
      addTearDown(h.superso.dispose);
    });

    test('a 415 always becomes MultipartError', () async {
      final h = harness((_) async => fail(415, 'BAD_TYPE', 'wrong type'));
      await expectLater(
        h.superso.storage.file.upload(
          bytes: Uint8List.fromList(<int>[1]),
          filename: 'a.bin',
          options: const UploadFileOptions(bucketId: 'b1'),
        ),
        throwsA(isA<MultipartError>()),
      );
      addTearDown(h.superso.dispose);
    });

    test('a non-positive chunk size is rejected', () {
      final h = harness((_) async => ok(null));
      expect(
        () => h.superso.storage.uploads.create(
          bucketId: 'b1',
          fileName: 'big.mp4',
          mimeType: 'video/mp4',
          totalSize: 1000,
          chunkSize: 0,
        ),
        throwsA(isA<ValidationError>()),
      );
      addTearDown(h.superso.dispose);
    });
  });

  group('MIME inference', () {
    test('maps known extensions case-insensitively', () {
      expect(inferMimeType('photo.HEIC'), 'image/heic');
      expect(inferMimeType('clip.mp4'), 'video/mp4');
      expect(inferMimeType('doc.pdf'), 'application/pdf');
    });

    test('falls back for unknown or missing extensions', () {
      expect(inferMimeType('archive.bin'), defaultMimeType);
      expect(inferMimeType('noextension'), defaultMimeType);
      expect(inferMimeType('trailing.'), defaultMimeType);
    });
  });

  group('Realtime', () {
    test('inferChannelType applies the documented prefix rules', () {
      expect(inferChannelType('database:users'), RealtimeChannelType.database);
      expect(inferChannelType('presence/lobby'), RealtimeChannelType.presence);
      expect(
        inferChannelType('broadcast/chat'),
        RealtimeChannelType.broadcast,
      );
      expect(inferChannelType('anything-else'), RealtimeChannelType.custom);
    });

    test('REST publish posts the documented body', () async {
      final h = harness(
        (_) async => ok(<String, dynamic>{
          'channel': 'broadcast/chat',
          'event': 'message.sent',
        }),
      );

      final result = await h.superso.realtime.rest.publish(
        channel: 'broadcast/chat',
        event: 'message.sent',
        data: <String, dynamic>{'text': 'hi'},
      );

      final body = bodyOf(h.requests.single);
      expect(h.requests.single.url.path, endsWith('/realtime/publish'));
      expect(body['channel'], 'broadcast/chat');
      expect(body['event'], 'message.sent');
      expect(result.data.event, 'message.sent');
      addTearDown(h.superso.dispose);
    });

    test('presence read URL-encodes the channel', () async {
      final h = harness(
        (_) async => ok(<String, dynamic>{
          'channel': 'presence/lobby',
          'presence': <dynamic>[
            <String, dynamic>{'user_id': 'u1', 'status': 'online'},
          ],
          'total': 1,
        }),
      );

      final result = await h.superso.realtime.getPresence('presence/lobby');

      expect(h.requests.single.url.toString(), contains('presence%2Flobby'));
      expect(result.data.presence.single.status, PresenceStatus.online);
      addTearDown(h.superso.dispose);
    });

    test('an error frame maps to the documented error type', () {
      const frame = RealtimeFrame(
        type: 'error',
        raw: <String, dynamic>{},
        code: 'CHANNEL_LIMIT_EXCEEDED',
        message: 'too many channels',
      );
      expect(mapRealtimeErrorFrame(frame), isA<SubscriptionError>());

      const authFrame = RealtimeFrame(
        type: 'error',
        raw: <String, dynamic>{},
        code: 'API_KEY_INVALID',
        message: 'bad key',
      );
      expect(mapRealtimeErrorFrame(authFrame), isA<AuthenticationError>());
    });

    test('ReconnectPolicy backoff grows and is capped', () {
      const policy = ReconnectPolicy(
        initialDelay: Duration(milliseconds: 100),
        maxDelay: Duration(milliseconds: 500),
      );
      expect(policy.delayFor(1), const Duration(milliseconds: 100));
      expect(policy.delayFor(2), const Duration(milliseconds: 200));
      expect(policy.delayFor(10).inMilliseconds, lessThanOrEqualTo(500));
    });
  });

  group('MediaModule', () {
    test('creating a session with an empty title is rejected', () {
      final h = harness((_) async => ok(null));
      expect(
        () => h.superso.media.sessions.create(title: '  '),
        throwsA(isA<ValidationError>()),
      );
      addTearDown(h.superso.dispose);
    });

    test('moderation targets the documented participant path', () async {
      final h = harness(
        (_) async => ok(<String, dynamic>{
          'id': 'p1',
          'session_id': 's1',
          'role': 'publisher',
          'is_muted': true,
        }),
      );

      final result =
          await h.superso.media.moderation.mute('s1', 'p1', reason: 'noise');

      expect(
        h.requests.single.url.path,
        endsWith('/media/sessions/s1/participants/p1/mute'),
      );
      expect(bodyOf(h.requests.single)['reason'], 'noise');
      expect(result.data.isMuted, isTrue);
      addTearDown(h.superso.dispose);
    });

    test('a 403 on moderation becomes HostAuthorizationError', () async {
      final h = harness(
        (_) async => fail(403, 'FORBIDDEN', 'not a host'),
      );
      await expectLater(
        h.superso.media.moderation.pin('s1', 'p1'),
        throwsA(isA<HostAuthorizationError>()),
      );
      addTearDown(h.superso.dispose);
    });

    test('a whiteboard draw denial becomes WhiteboardPermissionError',
        () async {
      final h = harness(
        (_) async => fail(
          403,
          'WHITEBOARD_DRAW_NOT_PERMITTED',
          'drawing is not currently permitted',
        ),
      );
      await expectLater(
        h.superso.media.whiteboard.draw(
          sessionId: 's1',
          participantId: 'p1',
          whiteboardId: 'w1',
          objectId: 'stroke-1',
          points: <Map<String, double>>[
            <String, double>{'x': 1, 'y': 2},
          ],
        ),
        throwsA(isA<WhiteboardPermissionError>()),
      );
      addTearDown(h.superso.dispose);
    });

    test('an unassignable classroom role is rejected client-side', () {
      final h = harness((_) async => ok(null));
      expect(
        () => h.superso.media.moderation
            .assignRole('s1', 'p1', ClassroomRole.owner),
        throwsA(isA<ValidationError>()),
      );
      expect(h.requests, isEmpty);
      addTearDown(h.superso.dispose);
    });

    test('assignable roles are accepted', () async {
      final h = harness((_) async => ok(null));
      await h.superso.media.moderation
          .assignRole('s1', 'p1', ClassroomRole.coHost);
      expect(bodyOf(h.requests.single)['role'], 'co_host');
      addTearDown(h.superso.dispose);
    });

    test('classroom roles report privilege correctly', () {
      expect(ClassroomRole.teacher.isPrivileged, isTrue);
      expect(ClassroomRole.coHost.isPrivileged, isTrue);
      expect(ClassroomRole.viewer.isPrivileged, isFalse);
      expect(ClassroomRole.guest.isPrivileged, isFalse);
    });

    test('undo returns null when there is nothing to undo', () async {
      final h = harness((_) async => ok(null));
      final action = await h.superso.media.whiteboard.undo(
        sessionId: 's1',
        participantId: 'p1',
        whiteboardId: 'w1',
      );
      expect(action, isNull);
      addTearDown(h.superso.dispose);
    });

    test('the replay log decodes in sequence order', () async {
      final h = harness(
        (_) async => ok(<String, dynamic>{
          'whiteboard_id': 'w1',
          'total': 2,
          'actions': <dynamic>[
            <String, dynamic>{
              'id': 'a1',
              'whiteboard_id': 'w1',
              'action_type': 'draw',
              'seq': 1,
            },
            <String, dynamic>{
              'id': 'a2',
              'whiteboard_id': 'w1',
              'action_type': 'shape',
              'seq': 2,
            },
          ],
        }),
      );

      final log = await h.superso.media.whiteboard.listActions('s1', 'w1');
      expect(log.data.actions.map((a) => a.seq), <int>[1, 2]);
      expect(log.data.total, 2);
      addTearDown(h.superso.dispose);
    });

    test('a poll with fewer than two options is rejected', () {
      final h = harness((_) async => ok(null));
      expect(
        () => h.superso.media.classroom.createPoll(
          's1',
          question: 'Yes?',
          options: <String>['Only one'],
        ),
        throwsA(isA<ValidationError>()),
      );
      addTearDown(h.superso.dispose);
    });
  });

  group('NotificationModule', () {
    test('send requires either a template or a body', () {
      final h = harness((_) async => ok(null));
      expect(
        () => h.superso.notification.send(
          channel: NotificationChannel.push,
          recipientId: 'u1',
        ),
        throwsA(isA<ValidationError>()),
      );
      addTearDown(h.superso.dispose);
    });

    test('send posts the documented body', () async {
      final h = harness((_) async => ok(<String, dynamic>{'id': 'log-1'}));
      await h.superso.notification.send(
        channel: NotificationChannel.email,
        recipientId: 'u1',
        title: 'Hi',
        body: 'Hello there',
      );
      final body = bodyOf(h.requests.single);
      expect(body['channel'], 'email');
      expect(body['recipient_id'], 'u1');
      expect(body['subject'], 'Hi');
      addTearDown(h.superso.dispose);
    });

    test('selected_users broadcast requires recipient IDs', () {
      final h = harness((_) async => ok(null));
      expect(
        () => h.superso.notification.broadcast(
          channel: NotificationChannel.push,
          targetMode: BroadcastTargetMode.selectedUsers,
          body: 'hi',
        ),
        throwsA(isA<ValidationError>()),
      );
      addTearDown(h.superso.dispose);
    });

    test('inbox list decodes items and the unread count', () async {
      final h = harness(
        (_) async => ok(<String, dynamic>{
          'items': <dynamic>[
            <String, dynamic>{
              'id': 'i1',
              'project_id': 'p',
              'user_id': 'u1',
              'title': 'Hello',
              'body': 'World',
              'priority': 'high',
              'is_read': false,
              'is_archived': false,
              'is_starred': false,
              'created_at': '',
              'updated_at': '',
            },
          ],
          'total': 1,
          'limit': 20,
          'offset': 0,
          'unread_count': 4,
        }),
      );

      final inbox = await h.superso.notification.inbox.list(userId: 'u1');
      expect(inbox.data.items.single.priority, NotificationPriority.high);
      expect(inbox.data.unreadCount, 4);
      addTearDown(h.superso.dispose);
    });

    test('a server-assigned schedule status cannot be set', () {
      final h = harness((_) async => ok(null));
      expect(
        () => h.superso.notification.schedules
            .update('s1', status: ScheduleStatus.completed),
        throwsA(isA<ValidationError>()),
      );
      addTearDown(h.superso.dispose);
    });

    test('an empty device token is rejected', () {
      final h = harness((_) async => ok(null));
      expect(
        () => h.superso.notification.devices.register(
          userId: 'u1',
          deviceToken: '',
          platform: DevicePlatform.ios,
        ),
        throwsA(isA<ValidationError>()),
      );
      addTearDown(h.superso.dispose);
    });
  });

  group('PaymentModule', () {
    test('purchase posts snake_case fields', () async {
      final h = harness(
        (_) async => ok(<String, dynamic>{
          'status': 'approved',
          'transaction_id': 'txn-1',
          'provider_response_code': '2001',
        }),
      );

      final result = await h.superso.payment.purchase(
        accountNo: '252615000000',
        amount: 10.5,
      );

      final body = bodyOf(h.requests.single);
      expect(body['account_no'], '252615000000');
      expect(body['amount'], 10.5);
      // Currency is deliberately omitted so the backend resolves it.
      expect(body.containsKey('currency'), isFalse);
      expect(result.data.isApproved, isTrue);
      expect(result.data.providerResponseCode, '2001');
      addTearDown(h.superso.dispose);
    });

    test('a non-positive amount is rejected before any request', () {
      final h = harness((_) async => ok(null));
      expect(
        () => h.superso.payment.purchase(accountNo: '252', amount: 0),
        throwsA(isA<ValidationError>()),
      );
      expect(h.requests, isEmpty);
      addTearDown(h.superso.dispose);
    });

    test('status requires an identifier', () {
      final h = harness((_) async => ok(null));
      expect(
        () => h.superso.payment.status(),
        throwsA(isA<ValidationError>()),
      );
      addTearDown(h.superso.dispose);
    });

    test('an unknown payment status decodes as pending, never declined', () {
      // A status the SDK does not recognize must never be mistaken for a
      // definitive failure — that could trigger a double charge or refund.
      expect(PaymentStatus.fromWire('some_new_status'), PaymentStatus.pending);
      expect(PaymentStatus.pending.isTerminal, isFalse);
      expect(PaymentStatus.approved.isTerminal, isTrue);
      expect(PaymentStatus.declined.isTerminal, isTrue);
    });

    test('a 422 becomes GatewayNotConfiguredError', () async {
      final h = harness(
        (_) async => fail(422, 'GATEWAY_NOT_CONFIGURED', 'no gateway'),
      );
      await expectLater(
        h.superso.payment.gateway.get(),
        throwsA(isA<GatewayNotConfiguredError>()),
      );
      addTearDown(h.superso.dispose);
    });

    test('a checkout session with no line items is rejected', () {
      final h = harness((_) async => ok(null));
      expect(
        () => h.superso.payment.stripe.createCheckoutSession(
          mode: StripeCheckoutMode.payment,
          lineItems: const <LineItemInput>[],
          successUrl: 'https://a.test/ok',
          cancelUrl: 'https://a.test/no',
        ),
        throwsA(isA<ValidationError>()),
      );
      addTearDown(h.superso.dispose);
    });

    test('createPaymentIntent surfaces the client secret', () async {
      final h = harness(
        (_) async => ok(<String, dynamic>{
          'id': 'pi_123',
          'status': 'requires_confirmation',
          'client_secret': 'pi_123_secret',
          'amount_minor': 1050,
        }),
      );

      final intent = await h.superso.payment.stripe.createPaymentIntent(
        amountMinor: 1050,
        orderId: 'order-1',
      );

      expect(intent.data.clientSecret, 'pi_123_secret');
      expect(
        intent.data.status,
        StripePaymentIntentStatus.requiresConfirmation,
      );
      addTearDown(h.superso.dispose);
    });
  });

  group('AIModule', () {
    test('chat synthesizes choices and usage from the flat wire shape',
        () async {
      final h = harness(
        (_) async => ok(<String, dynamic>{
          'provider': 'anthropic',
          'model': 'claude-sonnet-4-6',
          'message': <String, dynamic>{
            'role': 'assistant',
            'content': 'Hello!',
          },
          'tokens_in': 12,
          'tokens_out': 5,
          'total_tokens': 17,
          'latency_ms': 340,
        }),
      );

      final response = await h.superso.ai.chat(
        messages: <ChatMessage>[const ChatMessage.user('Hi')],
      );

      expect(response.data.text, 'Hello!');
      expect(response.data.choices.single.message.content, 'Hello!');
      expect(response.data.usage.promptTokens, 12);
      expect(response.data.usage.completionTokens, 5);
      expect(response.data.usage.totalTokens, 17);
      addTearDown(h.superso.dispose);
    });

    test('an empty message list is rejected before any request', () {
      final h = harness((_) async => ok(null));
      expect(
        () => h.superso.ai.chat(messages: const <ChatMessage>[]),
        throwsA(isA<ValidationError>()),
      );
      expect(h.requests, isEmpty);
      addTearDown(h.superso.dispose);
    });

    test('a session seeds the system prompt and accumulates history', () async {
      var turn = 0;
      final h = harness((_) async {
        turn++;
        return ok(<String, dynamic>{
          'provider': 'openai',
          'model': 'gpt-4o',
          'message': <String, dynamic>{
            'role': 'assistant',
            'content': 'reply $turn',
          },
          'tokens_in': 1,
          'tokens_out': 1,
          'total_tokens': 2,
          'latency_ms': 1,
        });
      });

      final chat = h.superso.ai.session(systemPrompt: 'Be terse.');
      expect(await chat.send('first'), 'reply 1');
      expect(await chat.send('second'), 'reply 2');

      // system + user + assistant + user + assistant
      expect(chat.history(), hasLength(5));
      expect(chat.history().first.role, MessageRole.system);

      chat.reset();
      expect(chat.history(), hasLength(1));

      chat.clear();
      expect(chat.history(), isEmpty);
      addTearDown(h.superso.dispose);
    });

    test('provider lookup is synchronous and issues no request', () {
      final h = harness((_) async => ok(null));
      expect(h.superso.ai.providers.supports('anthropic'), isTrue);
      expect(h.superso.ai.providers.supports('not-a-provider'), isFalse);
      expect(
        h.superso.ai.providers.get('openai').value,
        AIProviderName.openai,
      );
      expect(
        () => h.superso.ai.providers.get('nope'),
        throwsA(isA<AIProviderError>()),
      );
      expect(h.superso.ai.models.byProvider('gemini'), contains('Gemini'));
      expect(h.requests, isEmpty);
      addTearDown(h.superso.dispose);
    });
  });

  group('Superso root', () {
    test('exposes every module', () {
      final h = harness((_) async => ok(null));
      expect(h.superso.auth, isNotNull);
      expect(h.superso.database, isNotNull);
      expect(h.superso.storage, isNotNull);
      expect(h.superso.realtime, isNotNull);
      expect(h.superso.media, isNotNull);
      expect(h.superso.notification, isNotNull);
      expect(h.superso.payment, isNotNull);
      expect(h.superso.ai, isNotNull);
      addTearDown(h.superso.dispose);
    });

    test('dispose is idempotent across every module', () async {
      final h = harness((_) async => ok(null));
      await h.superso.dispose();
      await h.superso.dispose();
    });
  });
}
