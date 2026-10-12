// Media-state control lifecycle — ONE pattern for every client control that
// changes authoritative media state: self microphone, self camera, the host's
// per-participant mute, screen share. Dart twin of supersosdk
// `src/media/controls.ts` (same policy, same test scenarios). The SDK owns
// signalling, not tracks or UI: these classes take the platform pieces (apply
// a value to a track, capture a screen, call the SDK) as callbacks, so a Web
// app and a Flutter app behave identically.
//
// State: desired (the user's preference), confirmed (the last server value),
// blocked (a server-imposed restriction: host mute, force mute, revoked
// permission), pending (an operation is in flight — show "Saving…" /
// "Starting…" / "Stopping…").
//
// Policy
//  * The local effect is `desired && confirmed && !blocked`: switching OFF is
//    immediate (fail-safe), switching ON takes effect only after the server
//    confirms it.
//  * At most ONE operation is in flight per control; clicks made meanwhile are
//    coalesced and the last click wins.
//  * On failure the control returns to the server value (a blocked control
//    keeps the user's preference), the error is reported, nothing is retried.
//  * While blocked nothing is sent automatically; switching ON is an explicit
//    request (self-unmute) the server allows or refuses.
//  * When a fresh read shows the restriction LIFTED, the user's own preference
//    is re-asserted (the server never enables a microphone remotely — POST
//    …/unmute only clears is_muted): a microphone that was on comes back, one
//    the user muted stays muted.
//  * adopt() ignores reads issued before the last operation settled.
//    dispose() stops further sends; an in-flight operation settles silently.
//
// No sleeps, no timers.

import 'dart:async';

import 'media_types.dart';

/// The server's view of one control, from a response or a fresh read.
class MediaServerState {
  /// Creates a server state.
  const MediaServerState(this.value, {this.blocked = false});

  /// The field's server value.
  final bool value;

  /// A server-imposed restriction is in force.
  final bool blocked;

  /// Microphone: `microphone_enabled`, blocked by a host mute (`is_muted`), a
  /// force mute or a revoked microphone permission.
  static MediaServerState microphone(MediaParticipant p) => MediaServerState(
        p.microphoneEnabled,
        blocked: p.isMuted || p.forceMuted || !p.microphonePermission,
      );

  /// Camera: `camera_enabled`, blocked by a revoked camera permission.
  static MediaServerState camera(MediaParticipant p) =>
      MediaServerState(p.cameraEnabled, blocked: !p.cameraPermission);

  /// Screen share: the SFU-derived `screen_share_active`.
  static MediaServerState screenShare(MediaParticipant p) =>
      MediaServerState(p.screenShareActive);

  /// Host moderation toggle: the participant's `is_muted`.
  static MediaServerState hostMute(MediaParticipant p) => MediaServerState(p.isMuted);

  @override
  bool operator ==(Object other) =>
      other is MediaServerState && other.value == value && other.blocked == blocked;

  @override
  int get hashCode => Object.hash(value, blocked);

  @override
  String toString() => 'MediaServerState(value: $value, blocked: $blocked)';
}

/// What a control presents.
class MediaControlSnapshot {
  /// Creates a snapshot.
  const MediaControlSnapshot({
    required this.desired,
    required this.preference,
    required this.confirmed,
    required this.blocked,
    required this.pending,
  });

  /// The target state the UI should present ("on"/"off").
  final bool desired;

  /// The user's own preference (kept while blocked).
  final bool preference;

  /// Last value the server reported.
  final bool confirmed;

  /// A server-imposed restriction is in force.
  final bool blocked;

  /// An operation is in flight.
  final bool pending;

  @override
  bool operator ==(Object other) =>
      other is MediaControlSnapshot &&
      other.desired == desired &&
      other.preference == preference &&
      other.confirmed == confirmed &&
      other.blocked == blocked &&
      other.pending == pending;

  @override
  int get hashCode => Object.hash(desired, preference, confirmed, blocked, pending);

  @override
  String toString() =>
      'MediaControlSnapshot(desired: $desired, preference: $preference, confirmed: $confirmed, blocked: $blocked, pending: $pending)';
}

/// One media-state control (see the file header for the policy).
class MediaStateControl {
  /// Creates a control whose value is [initial] on both sides.
  MediaStateControl({
    required bool initial,
    this.applyLocal,
    required this.send,
    this.onChange,
    this.onError,
  })  : _desired = initial,
        _confirmed = initial,
        _applied = initial;

  /// Applies the effective local state (`desired && confirmed && !blocked`).
  /// Called on change only. Must not throw.
  final void Function(bool on)? applyLocal;

  /// Performs the operation; completes with the server state once confirmed.
  final Future<MediaServerState> Function(bool value) send;

  /// Called after every state change.
  final void Function(MediaControlSnapshot s)? onChange;

  /// Called when an operation fails; the control has already been reverted.
  final void Function(Object error, bool attempted)? onError;

  bool _desired;
  bool _confirmed;
  bool _blocked = false;
  bool _unblockRequested = false;
  bool _applied;
  Future<void>? _inflight;
  // _pump() is running (false again once it settled — possibly synchronously).
  bool _pumping = false;
  bool _disposed = false;
  int _generation = 0;

  /// The current snapshot.
  MediaControlSnapshot get snapshot => MediaControlSnapshot(
        desired: _unblockRequested || (_desired && !_blocked),
        preference: _desired,
        confirmed: _confirmed,
        blocked: _blocked,
        pending: _inflight != null,
      );

  /// Pass to [adopt] with a server read issued now.
  int get generation => _generation;

  /// Whether [dispose] was called.
  bool get isDisposed => _disposed;

  /// A click: switch to the opposite of what the UI presents.
  Future<void> toggle() => set(!snapshot.desired);

  /// Requests [value]. Completes when the server caught up or an operation failed.
  Future<void> set(bool value) {
    if (_disposed) return Future<void>.value();
    if (_blocked && value) {
      _unblockRequested = true; // explicit; the server decides
    } else {
      _unblockRequested = false;
      _desired = value;
    }
    _apply();
    return _start();
  }

  /// Adopts an authoritative server read (see the file header).
  void adopt(MediaServerState server, int readGeneration) {
    if (_disposed || _inflight != null || readGeneration != _generation) return;
    final wasBlocked = _blocked;
    _confirmed = server.value;
    _blocked = server.blocked;
    if (!_blocked) {
      _unblockRequested = false;
      if (wasBlocked && _desired != _confirmed) {
        // Restriction lifted: re-assert the user's own preference.
        _apply();
        unawaited(_start());
        return;
      }
      _desired = _confirmed; // the server wins
    }
    _apply();
    _emit();
  }

  /// Stops all further sends; an in-flight operation settles silently.
  void dispose() => _disposed = true;

  bool _needsSend() => _unblockRequested || (!_blocked && _desired != _confirmed);

  Future<void> _start() {
    final running = _inflight;
    if (running != null) {
      _emit();
      return running;
    }
    if (!_needsSend()) {
      // Nothing to send; also avoids a synchronously-completed _pump()
      // leaving a stale pending future behind.
      _emit();
      return Future<void>.value();
    }
    final f = _pump();
    // _pump() settles synchronously when send() throws before returning a
    // future; its finally has then already run, so it must not be marked in
    // flight (that would leave the control stuck "pending").
    if (!_pumping) {
      _emit();
      return f;
    }
    _inflight = f;
    _emit();
    return f;
  }

  Future<void> _pump() async {
    _pumping = true;
    try {
      while (!_disposed && _needsSend()) {
        final unblock = _unblockRequested;
        final target = unblock ? true : _desired;
        final MediaServerState res;
        try {
          res = await send(target);
        } on Object catch (e) {
          if (_disposed) return;
          _unblockRequested = false;
          if (!_blocked) _desired = _confirmed;
          _apply();
          onError?.call(e, target);
          return;
        }
        if (_disposed) return;
        _confirmed = res.value;
        _blocked = res.blocked;
        if (unblock && _unblockRequested) {
          _unblockRequested = false;
          if (!_blocked && _confirmed) _desired = true;
        } else if (!_blocked && _confirmed != target && _desired == target) {
          _desired = _confirmed; // accepted, but the server holds a different value
        }
        _apply();
      }
    } finally {
      _pumping = false;
      _generation++;
      _inflight = null;
      _emit();
    }
  }

  void _apply() {
    final on = _desired && _confirmed && !_blocked;
    if (on == _applied) return;
    _applied = on;
    applyLocal?.call(on);
  }

  void _emit() => onChange?.call(snapshot);
}

/// Waits for the server to report a value, using only reads issued AFTER the
/// wait began (screen-share start/stop is confirmed by `screen_share_active`).
/// No timers: a wait ends when confirmed or aborted.
class ServerConfirmation {
  int _issued = 0;
  _Waiter? _waiter;

  /// Call immediately before issuing a read; pass the result to [observe].
  int nextRead() => ++_issued;

  /// Feeds a server value from the read numbered [readSeq].
  void observe(bool value, int readSeq) {
    final w = _waiter;
    if (w == null || readSeq <= w.since || value != w.want) return;
    _waiter = null;
    w.completer.complete();
  }

  /// Completes once a fresh read reports [want]. One wait at a time.
  Future<void> wait(bool want) {
    abort(StateError('superseded by a newer operation'));
    final w = _Waiter(want, _issued);
    _waiter = w;
    return w.completer.future;
  }

  /// Whether a wait is open.
  bool get waiting => _waiter != null;

  /// Ends the current wait with [reason].
  void abort(Object reason) {
    final w = _waiter;
    _waiter = null;
    if (w != null && !w.completer.isCompleted) w.completer.completeError(reason);
  }
}

class _Waiter {
  _Waiter(this.want, this.since);
  final bool want;
  final int since;
  final Completer<void> completer = Completer<void>();
}

/// Runs an async task with at most ONE run at a time; requests made during a
/// run collapse into exactly one more run after it. Used for authoritative
/// reads so they can never be applied out of order.
class SerialTask {
  /// Creates a serial task.
  SerialTask(this._task);

  final Future<void> Function() _task;
  Future<void>? _running;
  bool _again = false;

  /// Runs (or schedules one more run of) the task.
  Future<void> run() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final f = () async {
      try {
        do {
          _again = false;
          await _task();
        } while (_again);
      } finally {
        _running = null;
      }
    }();
    _running = f;
    return f;
  }
}

/// Platform glue for [ScreenShareLifecycle] (e.g. flutter_webrtc
/// getDisplayMedia + RTCPeerConnection on a platform that supports capture).
class ScreenShareLifecycleDeps<T> {
  /// Creates the glue.
  const ScreenShareLifecycleDeps({
    required this.capture,
    required this.onEnded,
    required this.publish,
    required this.unpublish,
    required this.release,
    required this.context,
    required this.requestRead,
    this.onChange,
    this.onError,
    this.onLog,
  });

  /// Asks the user for a capture; throws when permission is denied or cancelled.
  final Future<T> Function() capture;

  /// Registers the platform's own "Stop sharing" (track ended).
  final void Function(T capture, void Function() cb) onEnded;

  /// Adds the capture to the publisher and renegotiates.
  final Future<void> Function(T capture) publish;

  /// Removes it from the publisher and renegotiates.
  final Future<void> Function(T capture) unpublish;

  /// Stops the capture's tracks. Must not throw.
  final void Function(T capture) release;

  /// Identity of the current publisher; a start whose publisher changed is abandoned.
  final Object? Function() context;

  /// Issues a fresh authoritative read (which calls [ScreenShareLifecycle.observe]).
  final void Function() requestRead;

  /// State changes.
  final void Function(MediaControlSnapshot s)? onChange;

  /// Failures.
  final void Function(Object error, bool attempted)? onError;

  /// Diagnostics.
  final void Function(String message)? onLog;
}

/// Screen-share lifecycle on top of [MediaStateControl], confirmed by the
/// server-reported `screen_share_active` (never by the click). One operation
/// and one capture at a time; the platform "Stop sharing" takes the same path
/// as the Stop button and aborts a pending start; denial, cancel, a failed
/// renegotiation, a changed publisher, [dispose] and [abort] all release the
/// capture and clear "pending".
class ScreenShareLifecycle<T extends Object> {
  /// Creates the lifecycle.
  ScreenShareLifecycle(this._deps) {
    control = MediaStateControl(
      initial: false,
      applyLocal: (on) {
        if (!on && !_busy && _current != null) {
          unawaited(_releaseCurrent().catchError((Object e) => _deps.onError?.call(e, false)));
        }
      },
      send: (v) => v ? _startShare() : _stopShare(),
      onChange: _deps.onChange,
      onError: _deps.onError,
    );
  }

  final ScreenShareLifecycleDeps<T> _deps;

  /// Server-confirmation of start/stop.
  final ServerConfirmation confirm = ServerConfirmation();

  /// The underlying control.
  late final MediaStateControl control;

  T? _current;
  bool _published = false;
  bool _busy = false;
  bool _disposed = false;

  /// The capture currently held.
  T? get active => _current;

  /// The current snapshot.
  MediaControlSnapshot get snapshot => control.snapshot;

  /// A Start/Stop click.
  Future<void> toggle() => control.toggle();

  /// Requests sharing on/off.
  Future<void> set(bool v) => control.set(v);

  /// Read bookkeeping: call before a read, then [observe] with its result.
  ({int seq, int gen}) beforeRead() => (seq: confirm.nextRead(), gen: control.generation);

  /// Feeds `screen_share_active` from a read started with [beforeRead].
  void observe(bool serverActive, ({int seq, int gen}) read) {
    confirm.observe(serverActive, read.seq);
    control.adopt(MediaServerState(serverActive), read.gen);
  }

  /// Ends a waiting operation (e.g. the publisher connection closed).
  void abort(String reason) => confirm.abort(StateError(reason));

  /// Leave / session end: no further operations; the capture is released.
  void dispose() {
    _disposed = true;
    control.dispose();
    confirm.abort(StateError('left the session'));
    final c = _current;
    _current = null;
    _published = false;
    if (c != null) _deps.release(c);
  }

  Future<void> _releaseCurrent() async {
    final c = _current;
    final wasPublished = _published;
    _current = null;
    _published = false;
    if (c == null) return;
    _deps.release(c);
    if (wasPublished) await _deps.unpublish(c);
  }

  Future<MediaServerState> _startShare() async {
    _busy = true;
    try {
      final ctx = _deps.context();
      final c = await _deps.capture();
      if (_disposed || !identical(ctx, _deps.context())) {
        _deps.release(c);
        throw StateError('the session or publisher changed while the screen picker was open — capture released');
      }
      await _releaseCurrent(); // never two captures
      _current = c;
      _deps.onEnded(c, () {
        if (!identical(_current, c)) return;
        _deps.onLog?.call('platform "Stop sharing" pressed');
        confirm.abort(StateError('screen share was stopped from the platform before the server confirmed it'));
        unawaited(control.set(false));
      });
      try {
        await _deps.publish(c);
        _published = true;
        final confirmed = confirm.wait(true);
        _deps.requestRead();
        await confirmed;
      } on Object {
        if (identical(_current, c)) {
          await _releaseCurrent().catchError((Object e) => _deps.onError?.call(e, false));
        }
        rethrow;
      }
      return const MediaServerState(true);
    } finally {
      _busy = false;
    }
  }

  Future<MediaServerState> _stopShare() async {
    _busy = true;
    try {
      await _releaseCurrent();
      final confirmed = confirm.wait(false);
      _deps.requestRead();
      await confirmed;
      return const MediaServerState(false);
    } finally {
      _busy = false;
    }
  }
}
