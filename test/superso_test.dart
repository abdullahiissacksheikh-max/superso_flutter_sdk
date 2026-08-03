import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:superso_flutter_sdk/superso_flutter_sdk.dart';

/// Builds a Superso instance whose transport is a [MockClient] returning
/// [handler]'s response, so every test runs without a network.
Superso supersoWith(Future<http.Response> Function(http.Request) handler) {
  final config = SupersoConfig(
    baseUrl: 'https://api.example.test/v1',
    apiKey: 'sp_test_key',
    retryPolicy: RetryPolicy.none,
  );
  return Superso(
    baseUrl: 'https://api.example.test/v1',
    apiKey: 'sp_test_key',
    retryPolicy: RetryPolicy.none,
    httpClient: SupersoHttpClient(config, httpClient: MockClient(handler)),
  );
}

/// Wraps [data] in the platform's standard success envelope.
http.Response ok(Object? data, {int status = 200}) => http.Response(
      jsonEncode(<String, dynamic>{
        'success': true,
        'message': 'ok',
        'data': data,
      }),
      status,
      headers: <String, String>{'content-type': 'application/json'},
    );

/// Builds an error envelope in the platform's nested `error` shape.
http.Response fail(int status, String code, String message) => http.Response(
      jsonEncode(<String, dynamic>{
        'success': false,
        'error': <String, dynamic>{'code': code, 'message': message},
      }),
      status,
      headers: <String, String>{'content-type': 'application/json'},
    );

void main() {
  group('SupersoConfig', () {
    test('rejects an empty baseUrl', () {
      expect(
        () => SupersoConfig(baseUrl: ''),
        throwsA(isA<ValidationError>()),
      );
    });

    test('strips a trailing slash from baseUrl', () {
      final config = SupersoConfig(baseUrl: 'https://api.example.test/v1/');
      expect(config.baseUrl, 'https://api.example.test/v1');
    });

    test('resolveUrl joins paths with and without a leading slash', () {
      final config = SupersoConfig(baseUrl: 'https://api.example.test/v1');
      expect(
          config.resolveUrl('/auth/me'), 'https://api.example.test/v1/auth/me');
      expect(
          config.resolveUrl('auth/me'), 'https://api.example.test/v1/auth/me');
    });
  });

  group('buildQueryString', () {
    test('skips null values and encodes the rest', () {
      final qs = buildQueryString(<String, Object?>{
        'page': 1,
        'q': 'hello world',
        'cursor': null,
      });
      expect(qs, '?page=1&q=hello+world');
    });

    test('returns an empty string when nothing is usable', () {
      expect(buildQueryString(<String, Object?>{'a': null}), '');
    });
  });

  group('errorFromResponse', () {
    test('maps statuses to the documented error subclasses', () {
      expect(errorFromResponse(400, 'x'), isA<ValidationError>());
      expect(errorFromResponse(401, 'x'), isA<AuthenticationError>());
      expect(errorFromResponse(403, 'x'), isA<PermissionError>());
      expect(errorFromResponse(404, 'x'), isA<NotFoundError>());
      expect(errorFromResponse(409, 'x'), isA<ConflictError>());
      expect(errorFromResponse(429, 'x'), isA<RateLimitError>());
      expect(errorFromResponse(503, 'x'), isA<ServerError>());
    });
  });

  group('SupersoHttpClient', () {
    test('attaches x-api-key and Authorization headers', () async {
      late http.Request captured;
      final superso = supersoWith((request) async {
        captured = request;
        return ok(<String, dynamic>{'id': 'u1', 'provider': 'email'});
      });
      superso.setAccessToken('jwt-token');

      await superso.auth.me();

      expect(captured.headers['x-api-key'], 'sp_test_key');
      expect(captured.headers['Authorization'], 'Bearer jwt-token');
      addTearDown(superso.dispose);
    });

    test('throws a typed error for a non-2xx response', () async {
      final superso = supersoWith(
        (_) async => fail(401, 'INVALID_TOKEN', 'Token expired'),
      );

      await expectLater(
        superso.auth.me(),
        throwsA(
          isA<AuthenticationError>().having(
            (e) => e.message,
            'message',
            'Token expired',
          ),
        ),
      );
      addTearDown(superso.dispose);
    });

    test('a cancelled token aborts the request', () async {
      final superso = supersoWith((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return ok(null);
      });
      final token = CancelToken()..cancel('user navigated away');

      // Exercised through the shared client, which is the layer CancelToken
      // is wired into; every module routes its requests through it.
      await expectLater(
        superso.client.get<void>(
          '/auth/me',
          options: RequestOptions(cancelToken: token),
          decoder: (_) {},
        ),
        throwsA(
          isA<CancelledError>().having(
            (e) => e.message,
            'message',
            'user navigated away',
          ),
        ),
      );
      expect(token.isCancelled, isTrue);
      addTearDown(superso.dispose);
    });

    test('a token cancelled mid-flight aborts an in-progress request',
        () async {
      final superso = supersoWith((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return ok(null);
      });
      final token = CancelToken();

      final pending = superso.client.get<void>(
        '/auth/me',
        options: RequestOptions(cancelToken: token),
        decoder: (_) {},
      );
      // Cancel after the request is already in flight.
      Timer(const Duration(milliseconds: 10), () => token.cancel('too slow'));

      await expectLater(pending, throwsA(isA<CancelledError>()));
      addTearDown(superso.dispose);
    });

    test('requests after dispose are rejected', () async {
      final superso = supersoWith((_) async => ok(null));
      await superso.dispose();

      await expectLater(
        superso.auth.me(),
        throwsA(
          isA<SupersoError>().having((e) => e.code, 'code', 'CLIENT_DISPOSED'),
        ),
      );
    });
  });

  group('AuthModule', () {
    test('login captures tokens automatically', () async {
      final superso = supersoWith(
        (_) async => ok(<String, dynamic>{
          'access_token': 'access-1',
          'refresh_token': 'refresh-1',
          'token_type': 'Bearer',
          'expires_in': 3600,
          'user': <String, dynamic>{'id': 'u1', 'provider': 'email'},
        }),
      );

      final res = await superso.auth.login(
        email: 'a@b.test',
        password: 'secret',
      );

      expect(res.data.user.id, 'u1');
      expect(res.data.tokens.expiresIn, 3600);
      // The whole point of automatic capture: no manual setAccessToken().
      expect(superso.getAccessToken(), 'access-1');
      expect(superso.getRefreshToken(), 'refresh-1');
      addTearDown(superso.dispose);
    });

    test('logout without any refresh token throws before hitting the network',
        () async {
      final superso = supersoWith(
        (_) async => fail(500, 'X', 'should never be called'),
      );

      await expectLater(
        superso.auth.logout(),
        throwsA(isA<ValidationError>()),
      );
      addTearDown(superso.dispose);
    });

    test('logout clears both tokens on success', () async {
      final superso = supersoWith((_) async => ok(null));
      superso
        ..setAccessToken('access-1')
        ..setRefreshToken('refresh-1');

      await superso.auth.logout();

      expect(superso.getAccessToken(), isNull);
      expect(superso.getRefreshToken(), isNull);
      addTearDown(superso.dispose);
    });

    test('authStateChanges emits on login and logout', () async {
      final superso = supersoWith(
        (request) async => request.url.path.endsWith('/logout')
            ? ok(null)
            : ok(<String, dynamic>{
                'access_token': 'a',
                'refresh_token': 'r',
                'token_type': 'Bearer',
                'expires_in': 60,
                'user': <String, dynamic>{'id': 'u1', 'provider': 'email'},
              }),
      );

      final states = <bool>[];
      final sub = superso.auth.authStateChanges
          .listen((state) => states.add(state.isSignedIn));

      await superso.auth.login(email: 'a@b.test', password: 'x');
      await superso.auth.logout();
      await Future<void>.delayed(Duration.zero);

      expect(states, <bool>[true, false]);
      await sub.cancel();
      addTearDown(superso.dispose);
    });
  });

  group('DatabaseModule', () {
    test('QueryBuilder serializes filters, ordering, and paging', () {
      final superso = supersoWith((_) async => ok(null));
      final query = superso.database
          .collection('users')
          .where('age', WhereOperator.greaterThanOrEqual, 18)
          .where('score', WhereOperator.between, 10, 20)
          .orderBy('created_at', OrderByDirection.desc)
          .limit(20)
          .offset(40)
          .toQuery()
          .toJson();

      expect(query['collection'], 'users');
      expect(query['limit'], 20);
      expect(query['offset'], 40);
      final where = query['where']! as List<dynamic>;
      expect(where, hasLength(2));
      expect((where[0] as Map<String, dynamic>)['op'], '>=');
      expect((where[1] as Map<String, dynamic>)['value2'], 20);
      final orderBy = query['order_by']! as List<dynamic>;
      expect((orderBy.first as Map<String, dynamic>)['direction'], 'desc');
      addTearDown(superso.dispose);
    });

    test('toPage normalizes the raw list shape', () async {
      final superso = supersoWith(
        (_) async => ok(<String, dynamic>{
          'documents': <dynamic>[
            <String, dynamic>{
              'id': 'row-1',
              'doc_id': 'doc-1',
              'collection': 'posts',
              'path': 'posts/doc-1',
              'data': <String, dynamic>{'title': 'Hello'},
              'version': 1,
              'size_bytes': 24,
              'created_at': '2026-01-01T00:00:00Z',
              'updated_at': '2026-01-01T00:00:00Z',
            },
          ],
          'total': 1,
          'has_more': false,
          'next_cursor': null,
        }),
      );

      final page = await superso.database.documents.list('posts');

      expect(page.data.items, hasLength(1));
      expect(page.data.items.first.docId, 'doc-1');
      expect(page.data.items.first.data['title'], 'Hello');
      expect(page.data.hasMore, isFalse);
      addTearDown(superso.dispose);
    });

    test('a batch over the documented limit is rejected client-side', () {
      final superso = supersoWith((_) async => ok(null));
      final tooMany = List<DatabaseBatchOperation>.generate(
        maxBatchOperations + 1,
        (_) => const DatabaseBatchOperation(
          operation: DatabaseBatchOperationType.create,
          collection: 'posts',
          data: <String, dynamic>{},
        ),
      );

      expect(
        () => superso.database.batch(tooMany),
        throwsA(isA<ValidationError>()),
      );
      addTearDown(superso.dispose);
    });

    test('maps error.code to the Database-specific error type', () async {
      final superso = supersoWith(
        (_) async => fail(404, 'DOCUMENT_NOT_FOUND', 'No such document'),
      );

      await expectLater(
        superso.database.documents.get('posts', 'missing'),
        throwsA(isA<DocumentNotFoundError>()),
      );
      addTearDown(superso.dispose);
    });

    test('parseDocumentReference rejects a malformed path', () {
      expect(
        () => parseDocumentReference('nocollection'),
        throwsA(isA<ValidationError>()),
      );
      final ref = parseDocumentReference('users/abc');
      expect(ref.collection, 'users');
      expect(ref.docId, 'abc');
    });

    test('increment and serverTimestamp emit the documented sentinels', () {
      expect(increment(5), <String, dynamic>{'__increment__': 5});
      expect(serverTimestamp(), '__server_timestamp__');
    });
  });
}
