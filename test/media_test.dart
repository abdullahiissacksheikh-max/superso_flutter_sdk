// Media Engine v0.4.0 contract tests: every SDK method's verb + path +
// headers + body, error mapping, participant-token handling, signaling
// reconnect decisions, and the realtime event catalogue.
//
// Ground truth: backend/internal/modules/media/api/routes.go (`register()`),
// service/events.go (`AllEvents`), docs/internal/MEDIA_CANONICAL_CONTRACT.md.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:superso_flutter_sdk/superso_flutter_sdk.dart';

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

const String userJwt = 'user-jwt';
const String tokenP1 = 'ptok-p1';
const String tokenVp1 = 'ptok-vp1';

/// Seeds an end-user access token plus participant tokens for p1 (session
/// s1) and vp1 (voice room v1), exactly as `join` would have stored them.
void seed(Superso superso) {
  superso.client.setAccessToken(userJwt);
  superso.media.tokens
    ..store(sessionId: 's1', participantId: 'p1', token: tokenP1)
    ..store(sessionId: 'v1', participantId: 'vp1', token: tokenVp1);
}

/// One SDK call and the exact request it must produce.
class RouteCase {
  const RouteCase(
    this.name,
    this.call,
    this.method,
    this.path, {
    this.body,
    this.query = const <String, String>{},
    this.participantToken,
  });

  final String name;
  final Future<Object?> Function(MediaModule media) call;
  final String method;

  /// Path relative to the SDK base (`/v1`).
  final String path;

  /// Expected JSON body, or `null` when no body may be sent.
  final Map<String, dynamic>? body;
  final Map<String, String> query;

  /// Expected `X-Media-Participant-Token`, or `null` when it must be absent.
  final String? participantToken;
}

const Map<String, dynamic> genericData = <String, dynamic>{
  'id': 'p1',
  'session_id': 's1',
  'role': 'publisher',
};

final List<RouteCase> routeCases = <RouteCase>[
  // ── Project ──
  RouteCase('overview', (m) => m.overview(), 'GET', '/media/overview'),
  RouteCase('usage', (m) => m.usage(days: 7), 'GET', '/media/usage',
      query: const <String, String>{'days': '7'}),
  RouteCase('getSettings', (m) => m.getSettings(), 'GET', '/media/settings'),
  RouteCase(
    'updateSettings',
    (m) => m.updateSettings(moderationEnabled: false, maxSessions: 5),
    'PUT',
    '/media/settings',
    body: const <String, dynamic>{
      'max_sessions': 5,
      'moderation_enabled': false,
    },
  ),
  // ── Participants ──
  RouteCase(
    'participants.list',
    (m) => m.participants.list(
      status: 'joined',
      publishersOnly: true,
      isPublisher: false,
      voiceRole: 'speaker',
      limit: 10,
      offset: 20,
    ),
    'GET',
    '/media/participants',
    query: const <String, String>{
      'status': 'joined',
      'publishers_only': 'true',
      'is_publisher': 'false',
      'voice_role': 'speaker',
      'limit': '10',
      'offset': '20',
    },
  ),
  RouteCase('participants.get', (m) => m.participants.get('p1'), 'GET',
      '/media/participants/p1'),
  RouteCase(
    'participants.pushTelemetry',
    (m) => m.participants.pushTelemetry('p1', rttMs: 40, packetLossPct: 1.5),
    'PATCH',
    '/media/participants/p1/telemetry',
    body: const <String, dynamic>{'packet_loss_pct': 1.5, 'rtt_ms': 40},
    participantToken: tokenP1,
  ),
  // ── Sessions ──
  RouteCase(
    'sessions.list',
    (m) => m.sessions.list(status: 'live', voiceRoom: false, limit: 5),
    'GET',
    '/media/sessions',
    query: const <String, String>{
      'status': 'live',
      'voice_room': 'false',
      'limit': '5',
    },
  ),
  RouteCase(
    'sessions.create',
    (m) => m.sessions.create(
      title: 'Standup',
      waitingRoom: true,
      hostUserId: 'u1',
    ),
    'POST',
    '/media/sessions',
    body: const <String, dynamic>{
      'title': 'Standup',
      'waiting_room': true,
      'host_user_id': 'u1',
    },
  ),
  RouteCase('sessions.byJoinToken', (m) => m.sessions.byJoinToken('jt'),
      'GET', '/media/sessions/by-join-token',
      query: const <String, String>{'join_token': 'jt'}),
  RouteCase(
      'sessions.get', (m) => m.sessions.get('s1'), 'GET', '/media/sessions/s1'),
  RouteCase(
    'sessions.update',
    (m) => m.sessions.update('s1', title: 'New', roomLocked: true),
    'PATCH',
    '/media/sessions/s1',
    body: const <String, dynamic>{'title': 'New', 'room_locked': true},
  ),
  RouteCase('sessions.start', (m) => m.sessions.start('s1'), 'POST',
      '/media/sessions/s1/start'),
  RouteCase('sessions.end', (m) => m.sessions.end('s1'), 'POST',
      '/media/sessions/s1/end'),
  RouteCase('sessions.cancel', (m) => m.sessions.cancel('s1'), 'DELETE',
      '/media/sessions/s1'),
  RouteCase(
    'sessions.join (resumes with the stored token)',
    (m) => m.sessions.join('s1', displayName: 'Ada'),
    'POST',
    '/media/sessions/s1/join',
    body: const <String, dynamic>{
      'display_name': 'Ada',
      'participant_token': tokenP1,
    },
  ),
  RouteCase(
    'sessions.participants',
    (m) => m.sessions.participants('s1', status: 'joined', offset: 0),
    'GET',
    '/media/sessions/s1/participants',
    query: const <String, String>{'status': 'joined', 'offset': '0'},
  ),
  RouteCase('sessions.getParticipant',
      (m) => m.sessions.getParticipant('s1', 'p1'), 'GET',
      '/media/sessions/s1/participants/p1'),
  RouteCase('sessions.leave', (m) => m.sessions.leave('s1', 'p1'), 'POST',
      '/media/sessions/s1/participants/p1/leave',
      participantToken: tokenP1),
  RouteCase(
    'sessions.updateMediaState',
    (m) => m.sessions.updateMediaState('s1', 'p1', cameraEnabled: true),
    'PATCH',
    '/media/sessions/s1/participants/p1/media-state',
    body: const <String, dynamic>{'camera_enabled': true},
    participantToken: tokenP1,
  ),
  RouteCase('sessions.speakers', (m) => m.sessions.speakers('s1'), 'GET',
      '/media/sessions/s1/speakers'),
  RouteCase('sessions.timeline',
      (m) => m.sessions.timeline('s1', limit: 50, offset: 0), 'GET',
      '/media/sessions/s1/timeline',
      query: const <String, String>{'limit': '50', 'offset': '0'}),
  RouteCase('sessions.tracks', (m) => m.sessions.tracks('s1'), 'GET',
      '/media/sessions/s1/tracks'),
  // ── Self-service (W, P) ──
  RouteCase('permissions.requestStage',
      (m) => m.permissions.requestStage('s1', 'p1', reason: 'q'), 'POST',
      '/media/sessions/s1/participants/p1/request-stage',
      body: const <String, dynamic>{'reason': 'q'},
      participantToken: tokenP1),
  RouteCase('permissions.cancelStageRequest',
      (m) => m.permissions.cancelStageRequest('s1', 'p1'), 'POST',
      '/media/sessions/s1/participants/p1/cancel-stage-request',
      participantToken: tokenP1),
  RouteCase('permissions.acceptStageInvite',
      (m) => m.permissions.acceptStageInvite('s1', 'p1'), 'POST',
      '/media/sessions/s1/participants/p1/accept-stage-invite',
      participantToken: tokenP1),
  RouteCase('permissions.declineStageInvite',
      (m) => m.permissions.declineStageInvite('s1', 'p1'), 'POST',
      '/media/sessions/s1/participants/p1/decline-stage-invite',
      participantToken: tokenP1),
  RouteCase('permissions.requestCamera',
      (m) => m.permissions.requestCamera('s1', 'p1'), 'POST',
      '/media/sessions/s1/participants/p1/request-camera',
      participantToken: tokenP1),
  RouteCase('permissions.requestMicrophone',
      (m) => m.permissions.requestMicrophone('s1', 'p1', reason: 'talk'),
      'POST', '/media/sessions/s1/participants/p1/request-microphone',
      body: const <String, dynamic>{'reason': 'talk'},
      participantToken: tokenP1),
  RouteCase('permissions.requestScreen',
      (m) => m.permissions.requestScreen('s1', 'p1'), 'POST',
      '/media/sessions/s1/participants/p1/request-screen',
      participantToken: tokenP1),
  RouteCase(
      'permissions.cancelRequest',
      (m) =>
          m.permissions.cancelRequest('s1', 'p1', MediaRequestType.camera),
      'POST',
      '/media/sessions/s1/participants/p1/cancel-request',
      body: const <String, dynamic>{'request_type': 'camera'},
      participantToken: tokenP1),
  RouteCase('permissions.stopScreenShare',
      (m) => m.permissions.stopScreenShare('s1', 'p1'), 'POST',
      '/media/sessions/s1/participants/p1/stop-screen-share',
      participantToken: tokenP1),
  RouteCase('permissions.listRequests',
      (m) => m.permissions.listRequests('s1'), 'GET',
      '/media/sessions/s1/permission-requests'),
  RouteCase('permissions.audit',
      (m) => m.permissions.audit('s1', limit: 10), 'GET',
      '/media/sessions/s1/permission-audit',
      query: const <String, String>{'limit': '10'}),
  // ── Host moderation (W, U, H): no participant token is sent ──
  ..._moderationCases(),
  RouteCase(
    'moderation.assignRole',
    (m) => m.moderation.assignRole('s1', 'p2', ClassroomRole.coHost),
    'POST',
    '/media/sessions/s1/participants/p2/assign-role',
    body: const <String, dynamic>{'role': 'co_host'},
  ),
  // ── Voice rooms ──
  RouteCase('voiceRooms.list', (m) => m.voiceRooms.list(status: 'live'),
      'GET', '/media/voice-rooms',
      query: const <String, String>{'status': 'live'}),
  RouteCase(
    'voiceRooms.create',
    (m) => m.voiceRooms.create(
      title: 'Lounge',
      roomType: 'stage',
      requireHandRaise: true,
    ),
    'POST',
    '/media/voice-rooms',
    body: const <String, dynamic>{
      'title': 'Lounge',
      'room_type': 'stage',
      'require_hand_raise': true,
    },
  ),
  RouteCase('voiceRooms.get', (m) => m.voiceRooms.get('v1'), 'GET',
      '/media/voice-rooms/v1'),
  RouteCase('voiceRooms.update',
      (m) => m.voiceRooms.update('v1', roomLocked: true), 'PATCH',
      '/media/voice-rooms/v1',
      body: const <String, dynamic>{'room_locked': true}),
  RouteCase('voiceRooms.start', (m) => m.voiceRooms.start('v1'), 'POST',
      '/media/voice-rooms/v1/start'),
  RouteCase('voiceRooms.end', (m) => m.voiceRooms.end('v1'), 'POST',
      '/media/voice-rooms/v1/end'),
  RouteCase('voiceRooms.transferHost',
      (m) => m.voiceRooms.transferHost('v1', 'vp2'), 'POST',
      '/media/voice-rooms/v1/transfer-host',
      body: const <String, dynamic>{'participant_id': 'vp2'}),
  RouteCase('voiceRooms.join', (m) => m.voiceRooms.join('v1'), 'POST',
      '/media/voice-rooms/v1/join',
      body: const <String, dynamic>{'participant_token': tokenVp1}),
  RouteCase('voiceRooms.participants',
      (m) => m.voiceRooms.participants('v1', voiceRole: 'listener'), 'GET',
      '/media/voice-rooms/v1/participants',
      query: const <String, String>{'voice_role': 'listener'}),
  RouteCase('voiceRooms.raiseHand',
      (m) => m.voiceRooms.raiseHand('v1', 'vp1'), 'POST',
      '/media/voice-rooms/v1/participants/vp1/raise-hand',
      participantToken: tokenVp1),
  RouteCase('voiceRooms.lowerHand',
      (m) => m.voiceRooms.lowerHand('v1', 'vp1'), 'POST',
      '/media/voice-rooms/v1/participants/vp1/lower-hand',
      participantToken: tokenVp1),
  ..._voiceHostCases(),
  // ── Breakout rooms ──
  RouteCase('breakoutRooms.list', (m) => m.breakoutRooms.list('s1'), 'GET',
      '/media/sessions/s1/breakout-rooms'),
  RouteCase('breakoutRooms.get', (m) => m.breakoutRooms.get('s1', 'b1'),
      'GET', '/media/sessions/s1/breakout-rooms/b1'),
  RouteCase('breakoutRooms.create',
      (m) => m.breakoutRooms.create('s1', title: 'A'), 'POST',
      '/media/sessions/s1/breakout-rooms',
      body: const <String, dynamic>{'title': 'A'}),
  RouteCase('breakoutRooms.update',
      (m) => m.breakoutRooms.update('s1', 'b1', title: 'B'), 'PATCH',
      '/media/sessions/s1/breakout-rooms/b1',
      body: const <String, dynamic>{'title': 'B'}),
  RouteCase('breakoutRooms.close', (m) => m.breakoutRooms.close('s1', 'b1'),
      'POST', '/media/sessions/s1/breakout-rooms/b1/close'),
  RouteCase('breakoutRooms.closeAll',
      (m) => m.breakoutRooms.closeAll('s1'), 'POST',
      '/media/sessions/s1/breakout-rooms/close-all'),
  RouteCase('breakoutRooms.delete',
      (m) => m.breakoutRooms.delete('s1', 'b1'), 'DELETE',
      '/media/sessions/s1/breakout-rooms/b1'),
  RouteCase('breakoutRooms.move',
      (m) => m.breakoutRooms.move('s1', 'b1', 'p2'), 'POST',
      '/media/sessions/s1/breakout-rooms/b1/participants/p2/move'),
  RouteCase('breakoutRooms.returnToMain',
      (m) => m.breakoutRooms.returnToMain('s1', 'p2'), 'POST',
      '/media/sessions/s1/breakout-rooms/participants/p2/return'),
  // ── Waiting room ──
  RouteCase('waitingRoom.queue', (m) => m.waitingRoom.queue('s1'), 'GET',
      '/media/sessions/s1/waiting-room/queue'),
  RouteCase('waitingRoom.status',
      (m) => m.waitingRoom.status('s1', 'e1'), 'GET',
      '/media/sessions/s1/waiting-room/e1',
      participantToken: tokenP1),
  RouteCase('waitingRoom.admit', (m) => m.waitingRoom.admit('s1', 'e1'),
      'POST', '/media/sessions/s1/waiting-room/e1/admit'),
  RouteCase('waitingRoom.reject',
      (m) => m.waitingRoom.reject('s1', 'e1', reason: 'no'), 'POST',
      '/media/sessions/s1/waiting-room/e1/reject',
      body: const <String, dynamic>{'reason': 'no'}),
  RouteCase('waitingRoom.ban', (m) => m.waitingRoom.ban('s1', 'e1'), 'POST',
      '/media/sessions/s1/waiting-room/e1/ban'),
  RouteCase('waitingRoom.admitAll', (m) => m.waitingRoom.admitAll('s1'),
      'POST', '/media/sessions/s1/waiting-room/admit-all'),
  // ── Speaker queue ──
  RouteCase('speakerQueue.list', (m) => m.speakerQueue.list('s1'), 'GET',
      '/media/sessions/s1/speaker-queue'),
  RouteCase('speakerQueue.join',
      (m) => m.speakerQueue.join('s1', 'p1', reason: 'q'), 'POST',
      '/media/sessions/s1/speaker-queue',
      body: const <String, dynamic>{'participant_id': 'p1', 'reason': 'q'},
      participantToken: tokenP1),
  RouteCase('speakerQueue.leave (self)',
      (m) => m.speakerQueue.leave('s1', 'p1'), 'DELETE',
      '/media/sessions/s1/speaker-queue/p1',
      participantToken: tokenP1),
  RouteCase('speakerQueue.leave (host removes another)',
      (m) => m.speakerQueue.leave('s1', 'p2'), 'DELETE',
      '/media/sessions/s1/speaker-queue/p2'),
  RouteCase('speakerQueue.promote (entry)',
      (m) => m.speakerQueue.promote('s1', entryId: 'e1'), 'POST',
      '/media/sessions/s1/speaker-queue/promote',
      body: const <String, dynamic>{'entry_id': 'e1'}),
  RouteCase('speakerQueue.promote (next)',
      (m) => m.speakerQueue.promote('s1'), 'POST',
      '/media/sessions/s1/speaker-queue/promote',
      body: const <String, dynamic>{}),
  RouteCase('speakerQueue.endTurn',
      (m) => m.speakerQueue.endTurn('s1', 'e1'), 'POST',
      '/media/sessions/s1/speaker-queue/entries/e1/end'),
  RouteCase('speakerQueue.remove', (m) => m.speakerQueue.remove('s1', 'e1'),
      'DELETE', '/media/sessions/s1/speaker-queue/entries/e1'),
  RouteCase('speakerQueue.setPriority',
      (m) => m.speakerQueue.setPriority('s1', 'e1', 5), 'PATCH',
      '/media/sessions/s1/speaker-queue/entries/e1/priority',
      body: const <String, dynamic>{'priority': 5}),
  // ── Attendance ──
  RouteCase('attendance.summary', (m) => m.attendance.summary('s1'), 'GET',
      '/media/sessions/s1/attendance'),
  RouteCase('attendance.events',
      (m) => m.attendance.events('s1', limit: 100), 'GET',
      '/media/sessions/s1/attendance/events',
      query: const <String, String>{'limit': '100'}),
];

List<RouteCase> _moderationCases() {
  final actions =
      <String, Future<Object?> Function(MediaModerationModule mod)>{
    'approve-camera': (x) => x.approveCamera('s1', 'p2', reason: 'r'),
    'reject-camera': (x) => x.rejectCamera('s1', 'p2', reason: 'r'),
    'revoke-camera': (x) => x.revokeCamera('s1', 'p2', reason: 'r'),
    'approve-microphone': (x) =>
        x.approveMicrophone('s1', 'p2', reason: 'r'),
    'reject-microphone': (x) => x.rejectMicrophone('s1', 'p2', reason: 'r'),
    'revoke-microphone': (x) => x.revokeMicrophone('s1', 'p2', reason: 'r'),
    'approve-screen': (x) => x.approveScreen('s1', 'p2', reason: 'r'),
    'reject-screen': (x) => x.rejectScreen('s1', 'p2', reason: 'r'),
    'revoke-screen': (x) => x.revokeScreen('s1', 'p2', reason: 'r'),
    'mute': (x) => x.mute('s1', 'p2', reason: 'r'),
    'unmute': (x) => x.unmute('s1', 'p2', reason: 'r'),
    'force-mute': (x) => x.forceMute('s1', 'p2', reason: 'r'),
    'clear-force-mute': (x) => x.clearForceMute('s1', 'p2', reason: 'r'),
    'hide-video': (x) => x.hideVideo('s1', 'p2', reason: 'r'),
    'show-video': (x) => x.showVideo('s1', 'p2', reason: 'r'),
    'pin': (x) => x.pin('s1', 'p2', reason: 'r'),
    'unpin': (x) => x.unpin('s1', 'p2', reason: 'r'),
    'spotlight': (x) => x.spotlight('s1', 'p2', reason: 'r'),
    'unspotlight': (x) => x.unspotlight('s1', 'p2', reason: 'r'),
    'approve-stage': (x) => x.approveStageRequest('s1', 'p2', reason: 'r'),
    'reject-stage': (x) => x.rejectStageRequest('s1', 'p2', reason: 'r'),
    'invite-to-stage': (x) => x.inviteToStage('s1', 'p2', reason: 'r'),
    'remove-from-stage': (x) => x.removeFromStage('s1', 'p2', reason: 'r'),
    'promote': (x) => x.promote('s1', 'p2', reason: 'r'),
    'demote': (x) => x.demote('s1', 'p2', reason: 'r'),
    'kick': (x) => x.kick('s1', 'p2', reason: 'r'),
    'ban': (x) => x.ban('s1', 'p2', reason: 'r'),
  };
  return <RouteCase>[
    for (final entry in actions.entries)
      RouteCase(
        'moderation ${entry.key}',
        (m) => entry.value(m.moderation),
        'POST',
        '/media/sessions/s1/participants/p2/${entry.key}',
        body: const <String, dynamic>{'reason': 'r'},
      ),
  ];
}

List<RouteCase> _voiceHostCases() {
  final actions =
      <String, Future<Object?> Function(MediaVoiceRoomsModule voice)>{
    'promote': (x) => x.promote('v1', 'vp2'),
    'demote': (x) => x.demote('v1', 'vp2'),
    'mute': (x) => x.mute('v1', 'vp2'),
    'unmute': (x) => x.unmute('v1', 'vp2'),
    'accept-hand': (x) => x.acceptHand('v1', 'vp2'),
    'reject-hand': (x) => x.rejectHand('v1', 'vp2'),
    'add-moderator': (x) => x.addModerator('v1', 'vp2'),
    'remove-moderator': (x) => x.removeModerator('v1', 'vp2'),
  };
  return <RouteCase>[
    for (final entry in actions.entries)
      RouteCase(
        'voiceRooms ${entry.key}',
        (m) => entry.value(m.voiceRooms),
        'POST',
        '/media/voice-rooms/v1/participants/vp2/${entry.key}',
      ),
  ];
}

/// Every SDK REST route declared by `register()` in routes.go (admin-only
/// routes excluded; the `SelfActions`, `ModerationActions`,
/// `VoiceSelfActions` and `VoiceHostActions` loops expanded). The signaling
/// WebSocket (`GET /media/signal`) is covered by MediaSignalingConnection.
const Set<String> backendSdkRoutes = <String>{
  'GET /media/overview',
  'GET /media/usage',
  'GET /media/settings',
  'PUT /media/settings',
  'GET /media/participants',
  'GET /media/participants/:participantId',
  'PATCH /media/participants/:participantId/telemetry',
  'GET /media/sessions',
  'POST /media/sessions',
  'GET /media/sessions/by-join-token',
  'GET /media/sessions/:sessionId',
  'PATCH /media/sessions/:sessionId',
  'POST /media/sessions/:sessionId/start',
  'POST /media/sessions/:sessionId/end',
  'DELETE /media/sessions/:sessionId',
  'POST /media/sessions/:sessionId/join',
  'GET /media/sessions/:sessionId/participants',
  'GET /media/sessions/:sessionId/speakers',
  'GET /media/sessions/:sessionId/timeline',
  'GET /media/sessions/:sessionId/tracks',
  'GET /media/sessions/:sessionId/permission-requests',
  'GET /media/sessions/:sessionId/permission-audit',
  'GET /media/sessions/:sessionId/waiting-room/queue',
  'POST /media/sessions/:sessionId/waiting-room/admit-all',
  'GET /media/sessions/:sessionId/waiting-room/:entryId',
  'POST /media/sessions/:sessionId/waiting-room/:entryId/admit',
  'POST /media/sessions/:sessionId/waiting-room/:entryId/reject',
  'POST /media/sessions/:sessionId/waiting-room/:entryId/ban',
  'GET /media/sessions/:sessionId/breakout-rooms',
  'POST /media/sessions/:sessionId/breakout-rooms',
  'POST /media/sessions/:sessionId/breakout-rooms/close-all',
  'POST /media/sessions/:sessionId/breakout-rooms/participants/:participantId/return',
  'GET /media/sessions/:sessionId/breakout-rooms/:roomId',
  'PATCH /media/sessions/:sessionId/breakout-rooms/:roomId',
  'POST /media/sessions/:sessionId/breakout-rooms/:roomId/close',
  'DELETE /media/sessions/:sessionId/breakout-rooms/:roomId',
  'POST /media/sessions/:sessionId/breakout-rooms/:roomId/participants/:participantId/move',
  'GET /media/sessions/:sessionId/attendance',
  'GET /media/sessions/:sessionId/attendance/events',
  'GET /media/sessions/:sessionId/speaker-queue',
  'POST /media/sessions/:sessionId/speaker-queue',
  'POST /media/sessions/:sessionId/speaker-queue/promote',
  'POST /media/sessions/:sessionId/speaker-queue/entries/:entryId/end',
  'DELETE /media/sessions/:sessionId/speaker-queue/entries/:entryId',
  'PATCH /media/sessions/:sessionId/speaker-queue/entries/:entryId/priority',
  'DELETE /media/sessions/:sessionId/speaker-queue/:participantId',
  'GET /media/sessions/:sessionId/participants/:participantId',
  'POST /media/sessions/:sessionId/participants/:participantId/leave',
  'PATCH /media/sessions/:sessionId/participants/:participantId/media-state',
  'POST /media/sessions/:sessionId/participants/:participantId/request-stage',
  'POST /media/sessions/:sessionId/participants/:participantId/cancel-stage-request',
  'POST /media/sessions/:sessionId/participants/:participantId/accept-stage-invite',
  'POST /media/sessions/:sessionId/participants/:participantId/decline-stage-invite',
  'POST /media/sessions/:sessionId/participants/:participantId/request-camera',
  'POST /media/sessions/:sessionId/participants/:participantId/request-microphone',
  'POST /media/sessions/:sessionId/participants/:participantId/request-screen',
  'POST /media/sessions/:sessionId/participants/:participantId/cancel-request',
  'POST /media/sessions/:sessionId/participants/:participantId/stop-screen-share',
  'POST /media/sessions/:sessionId/participants/:participantId/approve-camera',
  'POST /media/sessions/:sessionId/participants/:participantId/reject-camera',
  'POST /media/sessions/:sessionId/participants/:participantId/revoke-camera',
  'POST /media/sessions/:sessionId/participants/:participantId/approve-microphone',
  'POST /media/sessions/:sessionId/participants/:participantId/reject-microphone',
  'POST /media/sessions/:sessionId/participants/:participantId/revoke-microphone',
  'POST /media/sessions/:sessionId/participants/:participantId/approve-screen',
  'POST /media/sessions/:sessionId/participants/:participantId/reject-screen',
  'POST /media/sessions/:sessionId/participants/:participantId/revoke-screen',
  'POST /media/sessions/:sessionId/participants/:participantId/mute',
  'POST /media/sessions/:sessionId/participants/:participantId/unmute',
  'POST /media/sessions/:sessionId/participants/:participantId/force-mute',
  'POST /media/sessions/:sessionId/participants/:participantId/clear-force-mute',
  'POST /media/sessions/:sessionId/participants/:participantId/hide-video',
  'POST /media/sessions/:sessionId/participants/:participantId/show-video',
  'POST /media/sessions/:sessionId/participants/:participantId/pin',
  'POST /media/sessions/:sessionId/participants/:participantId/unpin',
  'POST /media/sessions/:sessionId/participants/:participantId/spotlight',
  'POST /media/sessions/:sessionId/participants/:participantId/unspotlight',
  'POST /media/sessions/:sessionId/participants/:participantId/approve-stage',
  'POST /media/sessions/:sessionId/participants/:participantId/reject-stage',
  'POST /media/sessions/:sessionId/participants/:participantId/invite-to-stage',
  'POST /media/sessions/:sessionId/participants/:participantId/remove-from-stage',
  'POST /media/sessions/:sessionId/participants/:participantId/promote',
  'POST /media/sessions/:sessionId/participants/:participantId/demote',
  'POST /media/sessions/:sessionId/participants/:participantId/assign-role',
  'POST /media/sessions/:sessionId/participants/:participantId/kick',
  'POST /media/sessions/:sessionId/participants/:participantId/ban',
  'GET /media/voice-rooms',
  'POST /media/voice-rooms',
  'GET /media/voice-rooms/:roomId',
  'PATCH /media/voice-rooms/:roomId',
  'POST /media/voice-rooms/:roomId/start',
  'POST /media/voice-rooms/:roomId/end',
  'POST /media/voice-rooms/:roomId/transfer-host',
  'POST /media/voice-rooms/:roomId/join',
  'GET /media/voice-rooms/:roomId/participants',
  'POST /media/voice-rooms/:roomId/participants/:participantId/raise-hand',
  'POST /media/voice-rooms/:roomId/participants/:participantId/lower-hand',
  'POST /media/voice-rooms/:roomId/participants/:participantId/promote',
  'POST /media/voice-rooms/:roomId/participants/:participantId/demote',
  'POST /media/voice-rooms/:roomId/participants/:participantId/mute',
  'POST /media/voice-rooms/:roomId/participants/:participantId/unmute',
  'POST /media/voice-rooms/:roomId/participants/:participantId/accept-hand',
  'POST /media/voice-rooms/:roomId/participants/:participantId/reject-hand',
  'POST /media/voice-rooms/:roomId/participants/:participantId/add-moderator',
  'POST /media/voice-rooms/:roomId/participants/:participantId/remove-moderator',
};

/// Replaces the concrete ids used by [routeCases] with route parameters.
String routePattern(RouteCase c) {
  const params = <String, String>{
    's1': ':sessionId',
    'v1': ':roomId',
    'b1': ':roomId',
    'e1': ':entryId',
    'p1': ':participantId',
    'p2': ':participantId',
    'vp1': ':participantId',
    'vp2': ':participantId',
  };
  final segments =
      c.path.split('/').map((s) => params[s] ?? s).join('/');
  return '${c.method} $segments';
}

/// `service.AllEvents` from backend/internal/modules/media/service/events.go,
/// pasted verbatim (77 names, same order).
const List<String> backendAllEvents = <String>[
  'session_started', 'session_updated', 'session_ended', 'session_archived',
  'room_empty', 'host_left', 'host_returned', 'participant_joined',
  'participant_left', 'participant_reconnected', 'participant_kicked',
  'participant_banned', 'participant_media_state_changed',
  'participant_speaking_changed', 'participant_state_changed',
  'participant_role_changed', 'participant_requested_stage',
  'participant_cancelled_request', 'participant_stage_approved',
  'participant_stage_rejected', 'participant_invited_to_stage',
  'participant_invite_accepted', 'participant_invite_declined',
  'participant_removed_stage', 'participant_promoted', 'participant_demoted',
  'camera_requested', 'microphone_requested', 'screen_requested',
  'camera_permission_granted', 'camera_permission_revoked',
  'camera_permission_rejected', 'microphone_permission_granted',
  'microphone_permission_revoked', 'microphone_permission_rejected',
  'screen_permission_granted', 'screen_permission_revoked',
  'screen_permission_rejected', 'screen_share_started',
  'screen_share_stopped', 'participant_muted', 'participant_unmuted',
  'participant_force_muted', 'participant_force_mute_cleared',
  'participant_video_hidden', 'participant_video_visible',
  'participant_pinned', 'participant_unpinned', 'participant_spotlighted',
  'participant_unspotlighted', 'voice_room.started', 'voice_room.updated',
  'voice.participant_joined', 'voice.hand_raised', 'voice.hand_lowered',
  'voice.speaker_promoted', 'voice.speaker_removed', 'voice.muted',
  'voice.unmuted', 'voice.host_changed', 'voice.moderator_added',
  'voice.moderator_removed', 'breakout.created', 'breakout.updated',
  'breakout.closed', 'breakout.deleted', 'breakout.participant_joined',
  'breakout.participant_left', 'waiting.participant_joined',
  'waiting.admitted', 'waiting.rejected', 'waiting.banned',
  'attendance.joined', 'attendance.left', 'speaker_queue.updated',
  'speaker_queue.promoted', 'speaker_queue.done',
];

void main() {
  group('Media routes (verb + path + headers + body)', () {
    for (final c in routeCases) {
      test('${c.method} ${c.path} <- ${c.name}', () async {
        final h = harness((_) async => ok(genericData));
        addTearDown(h.superso.dispose);
        seed(h.superso);

        await c.call(h.superso.media);

        final request = h.requests.single;
        expect(request.method, c.method);
        expect(request.url.path, '/v1${c.path}');
        expect(request.url.queryParameters, c.query);
        expect(request.headers['x-api-key'], 'sp_test_key');
        // U routes: the end-user access token is attached automatically.
        expect(request.headers['authorization'], 'Bearer $userJwt');
        expect(request.headers[mediaParticipantTokenHeader], c.participantToken);
        if (c.body == null) {
          expect(request.body, isEmpty);
        } else {
          expect(jsonDecode(request.body), c.body);
        }
      });
    }

    test('the SDK covers exactly the backend SDK route set', () {
      final covered = routeCases.map(routePattern).toSet();
      expect(covered.difference(backendSdkRoutes), isEmpty,
          reason: 'SDK calls a route the backend does not register');
      expect(backendSdkRoutes.difference(covered), isEmpty,
          reason: 'backend route without an SDK method');
      expect(backendSdkRoutes, hasLength(105));
    });
  });

  group('Participant tokens', () {
    test('join stores the issued token and self-service reuses it', () async {
      final h = harness((request) async {
        if (request.url.path.endsWith('/join')) {
          return ok(<String, dynamic>{
            'participant': <String, dynamic>{
              'id': 'p9',
              'session_id': 's9',
              'status': 'ready',
            },
            'participant_token': 'tok9',
            'participant_token_expires_at': '2026-10-01T00:00:00Z',
            'admission': 'waiting',
            'waiting_entry': <String, dynamic>{
              'id': 'e9',
              'session_id': 's9',
              'participant_id': 'p9',
              'status': 'waiting',
              'position': 1,
            },
            'breakout_room_id': 'b9',
            'ice_servers': <Map<String, dynamic>>[
              <String, dynamic>{
                'urls': <String>['stun:stun.example.test:3478'],
              },
            ],
            'media_constraints': <String, dynamic>{
              'max_video_bitrate_kbps': 1500,
              'resolution': '720p',
              'fps': 30,
              'noise_suppression': true,
              'echo_cancellation': true,
            },
            'signal_path': '/v1/media/signal',
          });
        }
        return ok(<String, dynamic>{
          'participant': <String, dynamic>{'id': 'p9', 'session_id': 's9'},
          'request': <String, dynamic>{
            'id': 'r1',
            'request_type': 'camera',
            'status': 'pending',
          },
        });
      });
      addTearDown(h.superso.dispose);

      final joined = await h.superso.media.sessions.join('s9');
      final result = joined.data;
      expect(jsonDecode(h.requests.first.body), <String, dynamic>{});
      expect(result.isWaiting, isTrue);
      expect(result.waitingEntry?.id, 'e9');
      expect(result.breakoutRoomId, 'b9');
      expect(result.iceServers.single.urls, <String>[
        'stun:stun.example.test:3478',
      ]);
      expect(result.mediaConstraints.resolution, '720p');
      expect(result.mediaConstraints.maxVideoBitrateKbps, 1500);
      expect(result.signalPath, '/v1/media/signal');
      expect(h.superso.media.tokens.forParticipant('p9'), 'tok9');
      expect(h.superso.media.tokens.forSession('s9'), 'tok9');

      final self =
          await h.superso.media.permissions.requestCamera('s9', 'p9');
      expect(h.requests.last.headers[mediaParticipantTokenHeader], 'tok9');
      expect(self.data.request?.requestType, 'camera');
      expect(self.data.participant.id, 'p9');
    });

    test('join(resume: false) does not send a stored token', () async {
      final h = harness((_) async => ok(genericData));
      addTearDown(h.superso.dispose);
      seed(h.superso);
      await h.superso.media.sessions
          .join('s1', resume: false, joinToken: 'jt', password: 'pw');
      expect(jsonDecode(h.requests.single.body), <String, dynamic>{
        'password': 'pw',
        'join_token': 'jt',
      });
    });

    test('an explicit participantToken overrides the stored one', () async {
      final h = harness((_) async => ok(genericData));
      addTearDown(h.superso.dispose);
      seed(h.superso);
      await h.superso.media.sessions
          .leave('s1', 'p1', participantToken: 'other');
      expect(h.requests.single.headers[mediaParticipantTokenHeader], 'other');
    });

    test('no token is sent for a participant without a stored token',
        () async {
      final h = harness((_) async => ok(genericData));
      addTearDown(h.superso.dispose);
      await h.superso.media.sessions
          .updateMediaState('s1', 'p5', microphoneEnabled: false);
      expect(
        h.requests.single.headers.containsKey(mediaParticipantTokenHeader),
        isFalse,
      );
    });
  });

  group('Media errors', () {
    Future<void> expectError(
      http.Response response,
      Matcher matcher,
    ) async {
      final h = harness((_) async => response);
      addTearDown(h.superso.dispose);
      await expectLater(
        h.superso.media.moderation.kick('s1', 'p2'),
        throwsA(matcher),
      );
    }

    test('MEDIA_NOT_HOST -> HostAuthorizationError', () async {
      await expectError(
        fail(403, 'MEDIA_NOT_HOST', 'not a host'),
        isA<HostAuthorizationError>()
            .having((e) => e.code, 'code', 'MEDIA_NOT_HOST')
            .having((e) => e.status, 'status', 403),
      );
    });

    test('MEDIA_INSUFFICIENT_RANK -> HostAuthorizationError', () async {
      await expectError(
        fail(403, 'MEDIA_INSUFFICIENT_RANK', 'rank'),
        isA<HostAuthorizationError>()
            .having((e) => e.code, 'code', 'MEDIA_INSUFFICIENT_RANK'),
      );
    });

    test('other MEDIA_* codes surface verbatim as MediaError', () async {
      await expectError(
        fail(403, 'MEDIA_PARTICIPANT_MISMATCH', 'mismatch'),
        allOf(
          isA<MediaError>()
              .having((e) => e.code, 'code', 'MEDIA_PARTICIPANT_MISMATCH')
              .having((e) => e.status, 'status', 403),
          isNot(isA<HostAuthorizationError>()),
        ),
      );
      await expectError(
        fail(404, 'MEDIA_SESSION_NOT_FOUND', 'nope'),
        isA<MediaError>()
            .having((e) => e.code, 'code', 'MEDIA_SESSION_NOT_FOUND')
            .having((e) => e.status, 'status', 404),
      );
      await expectError(
        fail(409, 'MEDIA_SESSION_ENDED', 'ended'),
        isA<MediaError>().having((e) => e.code, 'code', 'MEDIA_SESSION_ENDED'),
      );
    });

    test('MediaErrorCodes lists every backend code', () {
      expect(MediaErrorCodes.all, hasLength(32));
      expect(MediaErrorCodes.all, contains('MEDIA_INVALID_PASSWORD'));
      expect(
        MediaErrorCodes.all.every((c) => c.startsWith('MEDIA_')),
        isTrue,
      );
    });

    test('an empty session title is rejected before any request', () {
      final h = harness((_) async => ok(null));
      addTearDown(h.superso.dispose);
      expect(
        () => h.superso.media.sessions.create(title: '  '),
        throwsA(isA<ValidationError>()),
      );
      expect(h.requests, isEmpty);
    });

    test('owner is never assignable', () {
      final h = harness((_) async => ok(null));
      addTearDown(h.superso.dispose);
      expect(
        () => h.superso.media.moderation
            .assignRole('s1', 'p2', ClassroomRole.owner),
        throwsA(isA<ValidationError>()),
      );
      expect(h.requests, isEmpty);
    });
  });

  group('Response envelopes', () {
    test('paginated participants', () async {
      final h = harness((_) async => ok(<String, dynamic>{
            'items': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'p1', 'session_id': 's1', 'is_host': true},
            ],
            'total': 3,
            'limit': 1,
            'offset': 0,
            'has_more': true,
          }));
      addTearDown(h.superso.dispose);
      final page = (await h.superso.media.sessions.participants('s1')).data;
      expect(page.participants.single.isHost, isTrue);
      expect(page.total, 3);
      expect(page.hasMore, isTrue);
    });

    test('named collections', () async {
      final h = harness((request) async {
        final path = request.url.path;
        if (path.endsWith('/speakers')) {
          return ok(<String, dynamic>{
            'speakers': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'p1', 'is_speaking': true},
            ],
            'count': 1,
          });
        }
        if (path.endsWith('/waiting-room/queue')) {
          return ok(<String, dynamic>{
            'entries': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'e1',
                'participant_id': 'p1',
                'status': 'waiting',
                'participant': <String, dynamic>{
                  'id': 'p1',
                  'display_name': 'Ada',
                },
              },
            ],
            'total': 1,
          });
        }
        if (path.endsWith('/admit-all')) {
          return ok(<String, dynamic>{'admitted': 4});
        }
        if (path.endsWith('/close-all')) {
          return ok(<String, dynamic>{'closed': 2});
        }
        if (path.endsWith('/breakout-rooms')) {
          return ok(<String, dynamic>{
            'rooms': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'b1',
                'title': 'A',
                'status': 'open',
                'participant_ids': <String>['p1', 'p2'],
              },
            ],
            'total': 1,
          });
        }
        if (path.endsWith('/permission-requests')) {
          return ok(<String, dynamic>{
            'requests': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'r1', 'request_type': 'screen'},
            ],
            'total': 1,
          });
        }
        if (path.endsWith('/usage')) {
          return ok(<String, dynamic>{
            'usage': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'u1'},
            ],
            'days': 30,
          });
        }
        if (path.endsWith('/by-join-token')) {
          return ok(<String, dynamic>{
            'session': <String, dynamic>{'id': 's1', 'status': 'live'},
            'valid': true,
          });
        }
        if (path.endsWith('/speaker-queue')) {
          return ok(<String, dynamic>{
            'session_id': 's1',
            'entries': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'q1', 'participant_id': 'p1'},
            ],
            'total': 1,
          });
        }
        return ok(<String, dynamic>{
          'participant': <String, dynamic>{'id': 'p1'},
          'tracks': <Map<String, dynamic>>[
            <String, dynamic>{'id': 't1'},
          ],
        });
      });
      addTearDown(h.superso.dispose);
      final media = h.superso.media;

      expect((await media.sessions.speakers('s1')).data.single.isSpeaking,
          isTrue);
      final queue = (await media.waitingRoom.queue('s1')).data;
      expect(queue.single.participant?.displayName, 'Ada');
      expect((await media.waitingRoom.admitAll('s1')).data, 4);
      expect((await media.breakoutRooms.closeAll('s1')).data, 2);
      expect((await media.breakoutRooms.list('s1')).data.single.participantIds,
          <String>['p1', 'p2']);
      expect(
          (await media.permissions.listRequests('s1')).data.single.requestType,
          'screen');
      expect((await media.usage()).data.single.id, 'u1');
      final resolved = (await media.sessions.byJoinToken('jt')).data;
      expect(resolved.valid, isTrue);
      expect(resolved.session.isLive, isTrue);
      expect((await media.speakerQueue.list('s1')).data.entries.single.id,
          'q1');
      final detail = (await media.participants.get('p1')).data;
      expect(detail.participant.id, 'p1');
      expect(detail.tracks.single.id, 't1');
    });

    test('telemetry resolves to null on 202 (analytics disabled)', () async {
      final h = harness((_) async => ok(null, status: 202));
      addTearDown(h.superso.dispose);
      final result =
          await h.superso.media.participants.pushTelemetry('p1', rttMs: 10);
      expect(result.data, isNull);
    });
  });

  group('Signaling reconnect decisions (contract §6/§14)', () {
    SignalingReconnectDecision decide(
      String? code, {
      SignalingRole role = SignalingRole.publisher,
      String? reason,
    }) =>
        decideSignalingReconnect(
          role: role,
          disconnectCode: code,
          reason: reason,
        );

    test('never reconnect after kick, ban, session end or leave', () {
      for (final code in <String>[
        MediaDisconnectCodes.kicked,
        MediaDisconnectCodes.banned,
        MediaDisconnectCodes.sessionEnded,
        MediaDisconnectCodes.left,
      ]) {
        for (final role in SignalingRole.values) {
          expect(decide(code, role: role).action,
              SignalingReconnectAction.none,
              reason: '$code / $role');
        }
      }
    });

    test('publish revoked stops the publisher only', () {
      expect(decide(MediaDisconnectCodes.publishRevoked).action,
          SignalingReconnectAction.none);
      expect(
        decide(MediaDisconnectCodes.publishRevoked,
                role: SignalingRole.subscriber)
            .action,
        SignalingReconnectAction.reconnect,
      );
    });

    test('breakout moved reconnects into the room named by reason', () {
      final d = decide(MediaDisconnectCodes.breakoutMoved, reason: 'b1');
      expect(d.action, SignalingReconnectAction.reconnectToBreakout);
      expect(d.breakoutRoomId, 'b1');
    });

    test('breakout closed reconnects to the main room', () {
      expect(decide(MediaDisconnectCodes.breakoutClosed).action,
          SignalingReconnectAction.reconnectToMain);
    });

    test('timeout and network drops back off and resume', () {
      expect(decide(MediaDisconnectCodes.connectionTimeout).action,
          SignalingReconnectAction.reconnect);
      expect(decide(null).action, SignalingReconnectAction.reconnect);
    });

    test('ready frame exposes token, breakout room and media constraints',
        () {
      final ready = MediaSignalingReady.fromFrame(<String, dynamic>{
        'type': 'ready',
        'role': 'publisher',
        'session_id': 's1',
        'participant_id': 'p1',
        'participant_token': 'tok',
        'breakout_room_id': 'b1',
        'ice_servers': <Map<String, dynamic>>[
          <String, dynamic>{
            'urls': <String>['turn:turn.example.test'],
            'username': 'u',
            'credential': 'c',
          },
        ],
        'media_constraints': <String, dynamic>{'fps': 24},
      });
      expect(ready.role, SignalingRole.publisher);
      expect(ready.participantToken, 'tok');
      expect(ready.breakoutRoomId, 'b1');
      expect(ready.iceServers.single.username, 'u');
      expect(ready.mediaConstraints?.fps, 24);
    });

    test('track_info sources match the wire vocabulary', () {
      expect(MediaTrackSource.values.map((s) => s.wireValue).toList(),
          <String>['camera', 'microphone', 'screen']);
    });
  });

  group('Realtime event catalogue', () {
    test('MediaEvents.all equals backend AllEvents exactly', () {
      expect(backendAllEvents, hasLength(77));
      expect(backendAllEvents.toSet(), hasLength(77));
      expect(MediaEvents.all, equals(backendAllEvents.toSet()));
    });

    test('permission decisions are a subset of the catalogue', () {
      expect(MediaEvents.permissionDecisions, <String>{
        'camera_permission_granted',
        'camera_permission_revoked',
        'camera_permission_rejected',
        'microphone_permission_granted',
        'microphone_permission_revoked',
        'microphone_permission_rejected',
        'screen_permission_granted',
        'screen_permission_revoked',
        'screen_permission_rejected',
      });
      expect(MediaEvents.all.containsAll(MediaEvents.permissionDecisions),
          isTrue);
    });

    test('removed v0.3 names are never catalogued', () {
      for (final name in MediaEvents.all) {
        expect(name.startsWith('stage.'), isFalse, reason: name);
        expect(name.startsWith('classroom.'), isFalse, reason: name);
      }
      for (final removed in <String>[
        'publisher_joined',
        'subscriber_joined',
        'permissions_updated',
        'participant_permission_updated',
      ]) {
        expect(MediaEvents.all, isNot(contains(removed)));
      }
    });

    test('MediaEvent decodes the participant and session payloads', () {
      final event = MediaEvent.fromJson(<String, dynamic>{
        'event': MediaParticipantEvents.joined,
        'data': <String, dynamic>{
          'session_id': 's1',
          'participant_id': 'p1',
          'participant': <String, dynamic>{
            'id': 'p1',
            'display_name': 'Ada',
          },
        },
      });
      expect(event.sessionId, 's1');
      expect(event.participantId, 'p1');
      expect(event.asParticipant.displayName, 'Ada');

      final updated = MediaEvent.fromJson(<String, dynamic>{
        'event': MediaSessionEvents.updated,
        'data': <String, dynamic>{
          'session_id': 's1',
          'session': <String, dynamic>{'id': 's1', 'title': 'Renamed'},
        },
      });
      expect(updated.asSession.title, 'Renamed');
    });
  });
}
