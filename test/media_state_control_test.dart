// Behavioural tests for the media-state control lifecycle
// (lib/src/media/media_state_control.dart). Same scenarios as the Web SDK's
// supersosdk/tests/media-controls.test.ts, so Web and Flutter behave the same.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:superso_flutter_sdk/superso_flutter_sdk.dart';

class _Harness {
  _Harness(bool initial) {
    control = MediaStateControl(
      initial: initial,
      applyLocal: local.add,
      send: (v) {
        inflight++;
        if (inflight > maxInflight) maxInflight = inflight;
        final c = Completer<MediaServerState>();
        requests.add((value: v, completer: c));
        return c.future.whenComplete(() => inflight--);
      },
      onError: (e, _) => errors.add(e),
    );
  }
  late final MediaStateControl control;
  final local = <bool>[];
  final errors = <Object>[];
  final requests = <({bool value, Completer<MediaServerState> completer})>[];
  int inflight = 0;
  int maxInflight = 0;
}

Future<void> _flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

MediaControlSnapshot _snap({required bool desired, bool? preference, required bool confirmed, bool blocked = false, bool pending = false}) =>
    MediaControlSnapshot(desired: desired, preference: preference ?? desired, confirmed: confirmed, blocked: blocked, pending: pending);

const _hostMuted = MediaServerState(false, blocked: true);
const _unblockedOff = MediaServerState(false);

class _Capture {
  _Capture(this.id);
  final int id;
  void Function()? ended;
  bool released = false;
  bool published = false;
}

class _ScreenHarness {
  _ScreenHarness() {
    share = ScreenShareLifecycle<_Capture>(ScreenShareLifecycleDeps<_Capture>(
      capture: () {
        final c = Completer<_Capture>();
        pickers.add(c);
        return c.future;
      },
      onEnded: (c, cb) => c.ended = cb,
      publish: (c) async {
        final f = publishFails;
        if (f != null) throw f;
        c.published = true;
      },
      unpublish: (c) async => c.published = false,
      release: (c) => c.released = true,
      context: () => context,
      requestRead: () => readRequests++,
      onChange: (s) => labels.add(s.pending ? (s.desired ? 'Starting…' : 'Stopping…') : (s.desired ? 'Stop' : 'Start')),
      onError: (e, _) => errors.add(e),
    ));
  }
  late final ScreenShareLifecycle<_Capture> share;
  final pickers = <Completer<_Capture>>[];
  final captures = <_Capture>[];
  final errors = <Object>[];
  final labels = <String>[];
  Object context = Object();
  StateError? publishFails;
  int readRequests = 0;
  int _next = 0;

  int get live => captures.where((c) => !c.released).length;

  _Capture pick() {
    final c = _Capture(++_next);
    captures.add(c);
    pickers.removeAt(0).complete(c);
    return c;
  }

  void deny() => pickers.removeAt(0).completeError(StateError('NotAllowedError: Permission denied'));

  void server(bool active) => share.observe(active, share.beforeRead());
}

void main() {
  group('self microphone / camera', () {
    test('switching OFF: local immediate, pending until confirmed', () async {
      final h = _Harness(true);
      final done = h.control.toggle();
      expect(h.local, <bool>[false]);
      expect(h.control.snapshot, _snap(desired: false, confirmed: true, pending: true));
      h.requests[0].completer.complete(const MediaServerState(false));
      await done;
      expect(h.control.snapshot, _snap(desired: false, confirmed: false));
    });

    test('switching ON: local enabled only after the server confirms', () async {
      final h = _Harness(false);
      final done = h.control.toggle();
      expect(h.local, isEmpty);
      h.requests[0].completer.complete(const MediaServerState(true));
      await done;
      expect(h.local, <bool>[true]);
    });

    test('rapid ON→OFF→ON→OFF: one request in flight, final = last click', () async {
      final h = _Harness(true);
      unawaited(h.control.toggle());
      unawaited(h.control.toggle());
      unawaited(h.control.toggle());
      expect(h.requests, hasLength(1));
      h.requests[0].completer.complete(const MediaServerState(false));
      await _flush();
      expect(h.requests, hasLength(1));
      expect(h.control.snapshot, _snap(desired: false, confirmed: false));
      expect(h.maxInflight, 1);
    });

    test('ON→OFF→ON: the follow-up carries the latest intent', () async {
      final h = _Harness(true);
      unawaited(h.control.toggle());
      unawaited(h.control.toggle());
      h.requests[0].completer.complete(const MediaServerState(false));
      await _flush();
      expect(h.requests, hasLength(2));
      expect(h.requests[1].value, isTrue);
      h.requests[1].completer.complete(const MediaServerState(true));
      await _flush();
      expect(h.control.snapshot, _snap(desired: true, confirmed: true));
      expect(h.maxInflight, 1);
    });

    test('failure reverts to the server value, reports, does not retry', () async {
      final h = _Harness(true);
      final done = h.control.toggle();
      h.requests[0].completer.completeError(Exception('NETWORK_ERROR'));
      await done;
      expect(h.control.snapshot, _snap(desired: true, confirmed: true));
      expect(h.local, <bool>[false, true]);
      expect(h.errors, hasLength(1));
      await _flush();
      expect(h.requests, hasLength(1));
    });

    test('send() throwing synchronously: error reported, never stuck pending', () async {
      final errors = <Object>[];
      final c = MediaStateControl(
        initial: true,
        send: (_) => throw StateError('Sign in first.'),
        onError: (e, _) => errors.add(e),
      );
      await c.toggle();
      expect(errors, hasLength(1));
      expect(c.snapshot.pending, isFalse);
      expect(c.snapshot.desired, isTrue);
    });

    test('server keeps a different value: adopted', () async {
      final h = _Harness(false);
      final done = h.control.set(true);
      h.requests[0].completer.complete(const MediaServerState(false));
      await done;
      expect(h.control.snapshot.desired, isFalse);
      expect(h.requests, hasLength(1));
    });

    test('stale read is ignored, fresh read adopted', () async {
      final h = _Harness(true);
      final stale = h.control.generation;
      final done = h.control.toggle();
      h.requests[0].completer.complete(const MediaServerState(false));
      await done;
      h.control.adopt(const MediaServerState(true), stale);
      expect(h.control.snapshot.desired, isFalse);
      h.control.adopt(const MediaServerState(true), h.control.generation);
      expect(h.control.snapshot.desired, isTrue);
    });

    test('dispose: pending clears, no error, nothing more sent', () async {
      final h = _Harness(true);
      final done = h.control.toggle();
      h.control.dispose();
      h.requests[0].completer.completeError(Exception('ended'));
      await done;
      expect(h.control.snapshot.pending, isFalse);
      expect(h.errors, isEmpty);
      unawaited(h.control.toggle());
      expect(h.requests, hasLength(1));
    });

    test('set() to the held value: no request, never stuck pending', () async {
      final h = _Harness(true);
      await h.control.set(true);
      expect(h.requests, isEmpty);
      expect(h.control.snapshot.pending, isFalse);
    });
  });

  group('host moderation as seen by the participant', () {
    test('host mute: local mic stops at once, nothing sent, preference kept', () {
      final h = _Harness(true);
      h.control.adopt(_hostMuted, h.control.generation);
      expect(h.local, <bool>[false]);
      expect(h.requests, isEmpty);
      expect(h.control.snapshot, _snap(desired: false, preference: true, confirmed: false, blocked: true));
    });

    test('host unmute restores a mic that was on (one PATCH, enabled after confirmation)', () async {
      final h = _Harness(true);
      h.control.adopt(_hostMuted, h.control.generation);
      h.control.adopt(_unblockedOff, h.control.generation);
      expect(h.requests, hasLength(1));
      expect(h.requests[0].value, isTrue);
      expect(h.local, <bool>[false]);
      h.requests[0].completer.complete(const MediaServerState(true));
      await _flush();
      expect(h.local, <bool>[false, true]);
      expect(h.control.snapshot, _snap(desired: true, confirmed: true));
    });

    test('a self-muted participant stays muted after the host mute is lifted', () async {
      final h = _Harness(true);
      final done = h.control.toggle();
      h.requests[0].completer.complete(const MediaServerState(false));
      await done;
      h.control.adopt(_hostMuted, h.control.generation);
      h.control.adopt(_unblockedOff, h.control.generation);
      expect(h.requests, hasLength(1));
      expect(h.local, <bool>[false]);
      expect(h.control.snapshot.desired, isFalse);
    });

    test('Unmute while host-muted: explicit request; track stays off until accepted', () async {
      final h = _Harness(true);
      h.control.adopt(_hostMuted, h.control.generation);
      final done = h.control.toggle();
      expect(h.requests.single.value, isTrue);
      expect(h.local, <bool>[false]);
      h.requests[0].completer.complete(const MediaServerState(true));
      await done;
      expect(h.local, <bool>[false, true]);
    });

    test('self-unmute refused while force-muted: still muted, error, preference kept, no retry', () async {
      final h = _Harness(true);
      h.control.adopt(_hostMuted, h.control.generation);
      final done = h.control.toggle();
      h.requests[0].completer.completeError(Exception('MEDIA_FORBIDDEN'));
      await done;
      expect(h.errors, hasLength(1));
      expect(h.control.snapshot, _snap(desired: false, preference: true, confirmed: false, blocked: true));
      await _flush();
      expect(h.requests, hasLength(1));
    });

    test('repeated host mute/unmute: converges each cycle', () async {
      final h = _Harness(true);
      for (var i = 0; i < 3; i++) {
        h.control.adopt(_hostMuted, h.control.generation);
        expect(h.local.last, isFalse);
        h.control.adopt(_unblockedOff, h.control.generation);
        h.requests.last.completer.complete(const MediaServerState(true));
        await _flush();
        expect(h.local.last, isTrue);
      }
      expect(h.requests, hasLength(3));
    });

    test("a read from before the participant's own unmute cannot re-impose the old mute", () async {
      final h = _Harness(true);
      h.control.adopt(_hostMuted, h.control.generation);
      final before = h.control.generation;
      final done = h.control.toggle();
      h.requests[0].completer.complete(const MediaServerState(true));
      await done;
      h.control.adopt(_hostMuted, before);
      expect(h.control.snapshot.blocked, isFalse);
      expect(h.local.last, isTrue);
    });
  });

  group('host moderation toggle (value = is_muted)', () {
    test('rapid mute/unmute coalesce; final state wins', () async {
      final h = _Harness(false);
      unawaited(h.control.toggle());
      unawaited(h.control.toggle());
      unawaited(h.control.toggle());
      expect(h.requests, hasLength(1));
      expect(h.control.snapshot.pending, isTrue);
      h.requests[0].completer.complete(const MediaServerState(true));
      await _flush();
      expect(h.requests, hasLength(1));
      expect(h.control.snapshot.confirmed, isTrue);
      expect(h.control.snapshot.pending, isFalse);
    });

    test('unmute refused (409 force-muted): reverts and reports', () async {
      final h = _Harness(true);
      final done = h.control.toggle();
      h.requests[0].completer.completeError(Exception('MEDIA_INVALID_STATE'));
      await done;
      expect(h.control.snapshot.desired, isTrue);
      expect(h.control.snapshot.pending, isFalse);
      expect(h.errors, hasLength(1));
    });
  });

  group('SerialTask / ServerConfirmation', () {
    test('SerialTask: one run at a time; requests during a run collapse into one more', () async {
      var running = 0, maxRunning = 0, runs = 0;
      final gates = <Completer<void>>[];
      final t = SerialTask(() async {
        running++;
        runs++;
        if (running > maxRunning) maxRunning = running;
        final g = Completer<void>();
        gates.add(g);
        await g.future;
        running--;
      });
      final first = t.run();
      unawaited(t.run());
      unawaited(t.run());
      expect(runs, 1);
      gates.removeAt(0).complete();
      await _flush();
      expect(runs, 2);
      gates.removeAt(0).complete();
      await first;
      expect(runs, 2);
      expect(maxRunning, 1);
    });

    test('ServerConfirmation: only reads issued after the wait began confirm; abort errors', () async {
      final c = ServerConfirmation();
      final stale = c.nextRead();
      var done = false;
      final f = c.wait(true).then((_) => done = true);
      c.observe(true, stale);
      await _flush();
      expect(done, isFalse);
      c.observe(true, c.nextRead());
      await f;
      expect(done, isTrue);
      final g = c.wait(false);
      c.abort(StateError('publisher closed'));
      await expectLater(g, throwsA(isA<StateError>()));
    });
  });

  group('screen share lifecycle', () {
    test('Start → Stop → Start → Stop: pending until the server confirms, one capture at most', () async {
      final h = _ScreenHarness();
      for (var i = 0; i < 2; i++) {
        unawaited(h.share.toggle());
        expect(h.labels.last, 'Starting…');
        final cap = h.pick();
        await _flush();
        expect(cap.published, isTrue);
        expect(h.share.snapshot.pending, isTrue);
        h.server(true);
        await _flush();
        expect(h.labels.last, 'Stop');
        expect(h.live, 1);
        unawaited(h.share.toggle());
        expect(h.labels.last, 'Stopping…');
        await _flush();
        expect(cap.released, isTrue);
        expect(cap.published, isFalse);
        h.server(false);
        await _flush();
        expect(h.labels.last, 'Start');
        expect(h.live, 0);
      }
      expect(h.errors, isEmpty);
    });

    test('platform "Stop sharing" after confirmation: same path as the Stop button', () async {
      final h = _ScreenHarness();
      unawaited(h.share.toggle());
      final cap = h.pick();
      await _flush();
      h.server(true);
      await _flush();
      cap.ended!();
      expect(h.labels.last, 'Stopping…');
      await _flush();
      expect(cap.released, isTrue);
      h.server(false);
      await _flush();
      expect(h.share.snapshot.pending, isFalse);
      expect(h.share.snapshot.confirmed, isFalse);
      expect(h.errors, isEmpty);
    });

    test('platform "Stop sharing" during startup: start aborted, capture released', () async {
      final h = _ScreenHarness();
      final done = h.share.toggle();
      final cap = h.pick();
      await _flush();
      cap.ended!();
      await done;
      await _flush();
      expect(cap.released, isTrue);
      expect(h.share.snapshot.pending, isFalse);
      expect(h.share.snapshot.desired, isFalse);
      expect(h.errors, hasLength(1));
    });

    test('permission denied / cancelled: no share, error, pending clears', () async {
      final h = _ScreenHarness();
      final done = h.share.toggle();
      h.deny();
      await done;
      expect(h.share.snapshot.pending, isFalse);
      expect(h.share.snapshot.desired, isFalse);
      expect(h.errors, hasLength(1));
      expect(h.captures, isEmpty);
    });

    test('leaving while the picker is open: late capture released, no error', () async {
      final h = _ScreenHarness();
      final done = h.share.toggle();
      h.share.dispose();
      final cap = h.pick();
      await done;
      expect(cap.released, isTrue);
      expect(cap.published, isFalse);
      expect(h.share.snapshot.pending, isFalse);
      expect(h.errors, isEmpty);
    });

    test('publisher replaced while the picker is open: released, start fails', () async {
      final h = _ScreenHarness();
      final done = h.share.toggle();
      h.context = Object();
      final cap = h.pick();
      await done;
      expect(cap.released, isTrue);
      expect(cap.published, isFalse);
      expect(h.errors, hasLength(1));
    });

    test('renegotiation failure: released, error, pending clears', () async {
      final h = _ScreenHarness()..publishFails = StateError('publisher connection closed');
      final done = h.share.toggle();
      final cap = h.pick();
      await done;
      expect(cap.released, isTrue);
      expect(h.share.snapshot.pending, isFalse);
      expect(h.errors, hasLength(1));
    });

    test('rapid Start/Stop/Start/Stop while the picker is open: one picker, final = stopped', () async {
      final h = _ScreenHarness();
      unawaited(h.share.toggle());
      unawaited(h.share.toggle());
      unawaited(h.share.toggle());
      unawaited(h.share.toggle());
      expect(h.pickers, hasLength(1));
      final cap = h.pick();
      await _flush();
      h.server(true);
      await _flush();
      expect(h.labels.last, 'Stopping…');
      expect(cap.released, isTrue);
      h.server(false);
      await _flush();
      expect(h.share.snapshot.pending, isFalse);
      expect(h.share.snapshot.confirmed, isFalse);
      expect(h.captures, hasLength(1));
      expect(h.live, 0);
    });
  });

  test('state mappers: host mute / force mute / revoked permission block the microphone', () {
    MediaParticipant row(Map<String, dynamic> o) => MediaParticipant.fromJson(<String, dynamic>{
          'id': 'p1',
          'session_id': 's1',
          'role': 'subscriber',
          'status': 'joined',
          'microphone_enabled': true,
          'camera_enabled': true,
          'screen_share_active': false,
          'is_muted': false,
          'force_muted': false,
          'microphone_permission': true,
          'camera_permission': true,
          ...o,
        });
    expect(MediaServerState.microphone(row(<String, dynamic>{})), const MediaServerState(true));
    expect(MediaServerState.microphone(row(<String, dynamic>{'is_muted': true, 'microphone_enabled': false})),
        const MediaServerState(false, blocked: true));
    expect(MediaServerState.microphone(row(<String, dynamic>{'force_muted': true})), const MediaServerState(true, blocked: true));
    expect(MediaServerState.microphone(row(<String, dynamic>{'microphone_permission': false})),
        const MediaServerState(true, blocked: true));
    expect(MediaServerState.camera(row(<String, dynamic>{'camera_permission': false})), const MediaServerState(true, blocked: true));
    expect(MediaServerState.screenShare(row(<String, dynamic>{'screen_share_active': true})), const MediaServerState(true));
    expect(MediaServerState.hostMute(row(<String, dynamic>{'is_muted': true})), const MediaServerState(true));
  });
}
