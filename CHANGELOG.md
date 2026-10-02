# Changelog

All notable changes to `superso_flutter_sdk` are documented in this file.

## 0.4.0

**Media Engine v0.4.0 contract**, mirroring `supersosdk` 0.4.0. `lib/src/media` now maps 1:1 onto `backend/internal/modules/media/api/routes.go` (SDK router `/v1/media`): every one of the 105 REST routes has exactly one SDK method and every SDK method has a registered route. Breaking for Media callers.

Added:

- Participant tokens (`MediaParticipantTokens`): `sessions.join()` / `voiceRooms.join()` store the issued token; participant-scoped calls send it as `X-Media-Participant-Token`; signaling sends it as `participant_token`; `join()` resumes with it.
- Sessions: `update()`, `join()`, `getParticipant()`, `leave()`, `updateMediaState()`, `timeline()`, `tracks()`, `speakers()`, `cancel()`; permissions `listRequests()` / `audit()`; participant list filters and the `{items,total,limit,offset,has_more}` page envelope (`MediaPage`).
- Moderation: the full host set incl. `forceMute`, `clearForceMute`, `assignRole`, `kick`, `ban`; permissions: request/cancel/accept/decline/stop-screen-share self-service returning `{participant, request?}`.
- Voice rooms: `update()`, `transferHost()`, `join()`, raise/lower hand and every host action.
- Waiting room (`queue`, `status`, `admit`, `reject`, `ban`, `admitAll`), breakout rooms (full host set incl. `closeAll`, `returnToMain`), speaker queue and attendance modules.
- Signaling: `ready` metadata, `track_info`, `disconnect` frames with the v0.4.0 reconnect rules (no reconnect after `MEDIA_KICKED`/`MEDIA_BANNED`/`MEDIA_SESSION_ENDED`/`MEDIA_LEFT`; breakout re-routing on `MEDIA_BREAKOUT_MOVED`/`MEDIA_BREAKOUT_CLOSED`).
- Events: `MediaEvents.all` equals the backend `AllEvents` (77 names, incl. the nine permission decisions in `MediaEvents.permissionDecisions`).
- Errors carry the backend `MEDIA_*` code (`MediaErrorCodes`); `MEDIA_NOT_HOST` / `MEDIA_INSUFFICIENT_RANK` raise `HostAuthorizationError`.

Changed:

- `permissions.cancelRequest()` rejects `MediaRequestType.speaking` (legacy value only).

Removed:

- `MediaClassroomModule` (use attendance / speaker queue), session-level raise/lower hand and `requestScreenShare` (use the permission self-service calls), waiting-room enqueue (use `join`), stage-v007 events (`stage.*`), `classroom.*` events, `publisher_joined`, `subscriber_joined`, `permissions_updated`, `participant_permission_updated`; settings `simulcast_enabled`, `adaptive_bitrate_enabled`; removed session fields (`reactions_enabled`, `polls_enabled`, `classroom_mode`, `stage_locked`, `speaker_timer_seconds`, `spatial_audio_enabled`).

Verification note: no Dart/Flutter toolchain could be installed in the build environment (see `docs/internal/MEDIA_ENGINE_FINAL_AUDIT.md`); route and event parity were verified by static analysis against the backend route inventory, and `dart analyze` / `flutter test` must be run before publishing.

## 0.3.12

**Public Media endpoint synchronization audit**, mirroring `supersosdk` 0.3.12. Every active Media feature's documented endpoint set was inventoried against `docs/media.md`, the backend routers, and this SDK. One real gap was found and fixed; everything else already matched exactly.

Added:

- `MediaSessionsModule.speakers(sessionId)` — `GET /v1/media/sessions/:sessionId/speakers` (docs §19 "Active Speaker Detection"), exposed as `superso.media.sessions.speakers(sessionId)`. This route was always documented as an SDK (`X-API-Key`) endpoint but the backend only ever registered it on the Admin-JWT router; the Flutter SDK simply had no method for it. The backend gap is now closed (`SDKHandler.GetActiveSpeakers`, delegating to the same, already-implemented `MediaServices.GetActiveSpeakers`), so this is now a real, working call returning `List<MediaParticipant>`.

No routes were removed, renamed, or rerouted through the Admin API. No other gaps were found — every other documented Video/Audio/Voice Room/Screen Share/Participant/Moderation/Waiting Room/Stage/Permission/Breakout Room/Speaker Queue/Analytics/Telemetry endpoint already had a corresponding, correctly-scoped (non-Admin-coupled) SDK method.

## 0.3.11

**Feature removal — Classroom, Polls, Whiteboard, Reactions, Chat, and Webhooks were removed from Media Core**, mirroring `supersosdk` 0.3.11. See `docs/media.md` for the full removal record. This is a breaking change for any caller using the removed methods/event names; there are no replacement endpoints.

Removed from `MediaClassroomModule` (`superso.media.classroom`):

- `sendReaction()`, `reactionSummary()`, `createPoll()`, `listPolls()`, `vote()`, `pollResults()`, `raiseHand()`, `lowerHand()` — the backend Admin routes and SDK routes backing these were removed. The module now exposes only its still-supported subset: `attendanceSummary()`, `listSpeakerQueue()`, `joinSpeakerQueue()`, `leaveSpeakerQueue()` (class kept as `MediaClassroomModule`, not renamed).

Removed from `MediaClassroomEvents`:

- `reaction`, `pollCreated`, `pollActivated`, `pollEnded`, `pollResults`, `pollVoteReceived`, `handRaised`, `handLowered`, `stageLocked`, `stageUnlocked`.

Unaffected (kept as-is): `attendanceJoined`, `attendanceLeft`, `speakerPromoted`, `speakerDone`, `speakerQueueUpdated`, `roleChanged`, `forceMuted`, `forceMuteCleared` — these back still-active Attendance, Speaker Queue, and SDK Moderation functionality. `MediaStageEvents.handRaised`/`handLowered` and `MediaVoiceRoomEvents.handRaised`/`handLowered` are unrelated, unaffected features. The Flutter SDK never implemented Webhooks, Chat, or Whiteboard client methods, so there is no other SDK-facing change for those three features.

## 0.3.10

Analytics + Telemetry audit, mirroring `supersosdk` 0.3.10.

`MediaSessionsModule.timeline()`/`.tracks()`, `MediaModule.usage()`, and
`MediaParticipantsModule.pushTelemetry()` were verified against the real
backend and found route-complete, matching the same
`GET /usage`/`GET /sessions/:id/timeline`/`PATCH /participants/:id/telemetry`
contract as the JS SDK. `timeline()`/`tracks()`/`usage()` already use this
SDK's established `List<MediaResource>` pattern (real data accessible via
`.raw` alongside typed getters), consistent with every other list endpoint
here — no change needed there.

### Fixed

- `pushTelemetry()` previously discarded the entire response body
  (`ApiResponse<void>`, `decoder: (_) {}`), even though docs/media.md §25
  documents the server as returning "the full updated participant object"
  — the same response `supersosdk`'s `telemetry.push()` already surfaces as
  a `MediaParticipant`. There was no way to read the just-recomputed
  `connection_score`/`network_quality` without an extra, separate `get()`
  call. Now returns `ApiResponse<MediaParticipant>`, decoded with the same
  `_participant` decoder `get()` already uses.

## 0.3.9

Speaker Queue + Attendance audit, mirroring `supersosdk` 0.3.9. No code
changes were required in this SDK.

`MediaClassroomModule.listSpeakerQueue()`/`joinSpeakerQueue()`/
`leaveSpeakerQueue()`/`attendanceSummary()` were verified against the real
backend and found route-complete, matching the exact same
`GET/POST/DELETE .../speaker-queue` and `GET .../attendance` contract as
the JS SDK.

The response-shape bug fixed in `supersosdk` 0.3.9 (bare-array responses
mistyped as `{ queue: [...] }` / `{ summary: [...] }`) does not affect this
SDK: `_resourceList`'s decoder already checks `data is List<dynamic>`
before falling back to a keyed wrapper, so it has always decoded these
bare-array responses correctly.

## 0.3.8

Breakout Rooms + Classroom audit, mirroring `supersosdk` 0.3.8.
`MediaRoomsModule`'s 2 breakout-room routes and `MediaClassroomModule`'s 12
Classroom Engine routes were verified against the real backend and found
route-complete — all use the generic `MediaResource` wrapper for breakout
rooms (an established, pre-existing pattern; no incorrect typed fields to
fix there, unlike the JS SDK's dedicated `BreakoutRoom` interface).

### Fixed

- `MediaClassroomModule.raiseHand()`/`lowerHand()` declared and decoded
  their response as [MediaParticipant] — but the backend's
  `SDKClassroomHandler.RaiseHandV7`/`LowerHandV7` respond with `data: null`.
  Every call silently produced an empty-shell participant (`id: ''`, every
  other field `null`) instead of reflecting the real (empty) response.
  Changed both methods' return type to `Future<ApiResponse<void>>`, matching
  `supersosdk`'s `classroom.raiseHand()`/`lowerHand()`, which already
  correctly returned `Promise<void>`.

### Added

- `MediaSession` gained the ten Enterprise v7 classroom-configuration
  fields (`sessionMode`, `classroomMode`, `attendanceEnabled`,
  `reactionsEnabled`, `pollsEnabled`, `stageLocked`, `speakerTimerSeconds`,
  `allowSelfUnmute`, `topic`, `spatialAudioEnabled`) for parity with
  `supersosdk`'s `MediaSession` interface, which already declared these.
  The backend previously never returned any of these fields on a session
  response at all (see the backend note below) — `stageLocked` in
  particular is actively written by `classroom.lockStage`/`unlockStage`,
  so a host locking the stage had no way to read that state back through
  any session fetch on either SDK.

### Backend note (not a Flutter SDK change)

`repository.GetSession`/`ListSessions` never selected the ten
`live_sessions` classroom-configuration columns back out of the database,
and `dto.SessionResponse` never carried them, so no session response from
the Admin API or the SDK API included them — regardless of their real
value in the database. Fixed on the backend; both SDKs now correctly
receive these fields.

## 0.3.7

Stage + Permission Engine audit, mirroring `supersosdk` 0.3.7.
`MediaModerationModule`'s stage self-service methods and
`MediaPermissionsModule`'s six Permission Engine methods were verified
against the real backend routes and found route-complete. Two real bugs
found and fixed, plus the same three missing dotted stage events added to
`supersosdk` 0.3.7 (this SDK already had zero of the three, unlike the JS
SDK which was missing only two — this codebase never had `stage.hand_raised`
paired correctly with a `hand_lowered`, nor either invite event).

### Fixed

- `MediaPermissionsModule.requestCamera()`/`requestMicrophone()`/
  `requestScreen()` declared and decoded their response as
  [MediaParticipant] — but the backend's `RequestCamera`/`RequestMicrophone`/
  `RequestScreen` handlers actually respond with a `PermissionRequestResponse`
  (a request record: `id`, `request_type`, `status`, `reason`, `reviewed_by`,
  `reviewed_at`, `expires_at`, `created_at`, `updated_at` — a completely
  different shape). Every call to these three methods was silently decoding
  the wrong type. Added a new `PermissionRequest` model
  (`lib/src/media/media_types.dart`, mirroring `supersosdk`'s `PermissionRequest`
  interface exactly) and changed these three methods' return type to
  `Future<ApiResponse<PermissionRequest>>`.

### Added

- `MediaStageEvents.handLowered` (`'stage.hand_lowered'`),
  `.inviteAccepted` (`'stage.invite_accepted'`), `.inviteDeclined`
  (`'stage.invite_declined'`) — all three are real, dispatched events this
  catalogue was missing entirely.
- `PermissionRequest` class (`lib/src/media/media_types.dart`).

## 0.3.6

Moderation + Waiting Room audit, mirroring `supersosdk` 0.3.6.
`MediaModerationModule` (approve/reject/revoke camera/microphone/screen,
mute/unmute/forceMute/clearForceMute, hideVideo/showVideo,
pin/unpin/spotlight/unspotlight, the stage actions, promote/demote,
assignRole) and `kick` on the participants API were verified against the
real Go route registration and found complete and correct. The Waiting
Room's two SDK methods (`enqueueWaitingRoom`, `getWaitingRoomEntry`) were
verified to correctly and deliberately omit the Admin-JWT-only management
actions, matching `docs/media.md` exactly.

Two real gaps, both event-catalogue accuracy, neither a route change —
identical in nature to the two found in `supersosdk` 0.3.6:

1. `MediaParticipantEvents.updated` (`participant_updated`) was modeled but
   never actually broadcast by any backend code — checked every
   `broadcastMedia`/`permEvent`/`stageEvent` call site to confirm. Removed.
2. The backend's `KickParticipant` was fixed (this release's backend
   change, see the platform-level notes) to finally broadcast
   `participant_kicked` — a name this catalogue did not yet have. Added as
   `MediaParticipantEvents.kicked`.

### Added

- `MediaParticipantEvents.kicked` (`'participant_kicked'`).

### Removed

- `MediaParticipantEvents.updated` (`'participant_updated'`) — never
  dispatched by the backend. Each moderation action already emits its own
  specifically-named event (`muted`, `pinned`, `videoHidden`, `kicked`,
  ...); there was never a generic catch-all.

## 0.3.5

Voice Rooms + Screen Share audit, mirroring `supersosdk` 0.3.5. Both
features' REST/SDK route coverage were already complete and correct
(`MediaVoiceRoomsModule` and the screen-share methods on
`MediaPermissionsModule`/`MediaModerationModule` already matched the real
backend routes exactly, including correctly omitting the Admin-JWT-only
Voice Room moderation and screen-share-approval actions this SDK's API key
cannot reach). Two real bugs and one real gap were found and fixed, all in
`MediaParticipant`.

### Fixed

- `MediaParticipant.handRaised` read a `hand_raised` JSON key that does not
  exist in any real backend response (docs/media.md §14.7: the field is
  `hand_raised_at`, a nullable timestamp) — every decoded participant had
  `handRaised == null` regardless of actual state. Now derived from
  `hand_raised_at != null`, and the raw timestamp is exposed as the new
  `handRaisedAt` field.
- `MediaParticipant.screenSharing` read a `screen_sharing` JSON key that
  does not exist — the real field is `screen_share_active`. Every decoded
  participant had `screenSharing == null` regardless of actual state.

### Added

- `MediaParticipant.isSpeaking`, `.audioLevel`, `.lastSpokeAt`,
  `.totalSpokeSec` (Voice Rooms, docs/media.md §14.7) — previously only
  reachable via `.raw`.
- `MediaParticipant.screenPermission`, `.screenRequestedAt`,
  `.screenStartedAt` (Screen Share) — previously only reachable via `.raw`.
- `stage.screen_share_requested`, `.screenShareApproved`,
  `.screenShareRejected`, `.screenShareRevoked`, `.screenShareStopped` to
  `MediaStageEvents` (`media_events.dart`) — real, broadcast events
  (`stageEvent()` in `service/media_services.go`) that neither SDK
  previously modeled, even though `docs/media.md` already documented them.

## 0.3.4

Video/Audio completeness: adds the raw WebRTC signaling transport
(`GET /v1/media/signal`) that was entirely absent from this SDK's Media
module. Every other piece of the documented Video/Audio contract (session
lifecycle, participants, permissions, moderation, telemetry, voice rooms)
was already implemented and unaffected; this release closes the one real
gap found in a full audit against `docs/media.md` and `supersosdk`
(mirrored 1:1 from its `signaling.ts`/`connection.ts`/`websocket.ts`,
`publishers.ts`, `subscribers.ts`).

This is signaling-transport-only, exactly like `supersosdk`: no WebRTC
media-capture engine (no `RTCPeerConnection`, no camera/microphone capture)
is bundled. The host Flutter application supplies its own WebRTC plugin
(e.g. `flutter_webrtc`) and wires its offer/answer/ICE-candidate calls
through the connection this module returns — no new package dependency was
added.

### Added

- `lib/src/media/media_signaling.dart` (new file):
  - `SignalingRole` enum (`publisher`/`subscriber`).
  - `IceServerConfig`, `IceCandidatePayload`, `SessionDescriptionPayload`,
    `MediaSignalingReady`, `MediaSignalingError`, `MediaSignalingInfo`
    models — Dart port of `supersosdk/src/media/types.ts`'s signaling
    section.
  - `MediaSignalingConnection` — the connection class itself. Exchanges
    `ready`/`offer`/`answer`/`ice_candidate`/`ping`/`pong`/`error` frames
    over the shared `RealtimeSocket` transport, reconnects automatically
    with the documented exponential backoff (100ms→200ms→...→30s cap), and
    exposes `onReady` (carrying the `ice_servers` the docs require the
    peer connection be configured with — see the `docs/media.md` fixes
    below), `onOffer`, `onAnswer`, `onIceCandidate`, `onParticipantJoined`,
    `onParticipantLeft`, `onSessionEnded`, `onError`, `onAuthMissing`,
    `connectionState`, `state`, `isConnected`, `info()`, `sendOffer()`,
    `sendAnswer()`, `sendIceCandidate()`, `restartIce()`, `disconnect()`,
    `dispose()`.
- `MediaModule.publishers` (`MediaPublishersModule`) and
  `MediaModule.subscribers` (`MediaSubscribersModule`) — each own a
  `MediaSignalingConnection` and expose `join(sessionId)` /  `leave()`,
  matching `supersosdk`'s `media.publishers`/`media.subscribers`.
- `MediaModule.websocket` — an independent `MediaSignalingConnection` for
  opening a raw signaling connection directly with either role, matching
  `supersosdk`'s `media.websocket`.
- `RealtimeSocket.reconnectAttempts` (`lib/src/realtime/realtime_socket.dart`)
  — a small additive getter needed by `MediaSignalingInfo`; no existing
  behavior changed.

### Fixed (documentation only — no other SDK code affected)

- `docs/media.md` §24.1 "Message Protocol": added the `ready` message (the
  backend has always sent it immediately after connect — `engine/signaling.go`
  — but no SDK and no version of this document ever modeled it, so neither
  SDK exposed the ICE server list the docs' own "Locked Systems" section
  requires the peer connection be configured with). Also removed the false
  claim that `participant_joined`/`participant_left`/`session_ended` are
  sent over this socket — they are not; that lifecycle is delivered on the
  separate `media.<sessionId>` Realtime channel (§24.2), which every SDK
  already correctly subscribes to.
- `docs/media.md` §24.2 "Enterprise Events": replaced a stale dotted-name
  event table (`participant.joined`, `session.started`, `active_speaker`,
  `hand_raised`, `spotlight_on`, ...) that predated both SDKs' own v0.3.0
  event-name corrections (see `supersosdk`'s `events.ts` — every one of
  those dotted names was already documented there as fictitious) with the
  real, underscore-separated names both SDKs have used correctly all along.
- `docs/media.md` §12/§13: updated the publisher/subscriber signaling
  diagrams to show the `ready` step before the offer/answer exchange.

## 0.3.3

Media cleanup: removes obsolete Invitations, Share Links, Lobby Chat, Session
Chat, and Whiteboard APIs from the Media module, mirroring `supersosdk` 0.3.3
exactly. These features are being retired platform-wide; the backend no
longer serves their endpoints. All other Media/Live Classroom functionality
(sessions, participants, publishers, subscribers, voice rooms, breakout
rooms, waiting room, tracks, devices, analytics, usage, audit logs, media
settings, reactions, polls, attendance, speaker queue, stage
invite/accept/decline, moderation, and classroom controls) is unchanged.

### Removed

- `MediaWhiteboardModule` (`superso.media.whiteboard`) and its ten methods —
  `start()`, `getActive()`, `end()`, `updatePermissions()`, `clear()`,
  `listActions()`, `draw()`, `addShape()`, `addText()`, `erase()`, `undo()`,
  `redo()`, `sendPointer()`.
- `MediaInvitesModule` (`superso.media.invites`) and its five methods —
  `create()`, `createLink()`, `validate()`, `accept()`, `resolveLink()`.
- `MediaClassroomModule.sendChatMessage()` and `.listChat()` (Session Chat).
- `MediaRoomsModule.listLobbyChat()` and `.sendLobbyMessage()` (Lobby Chat).
- Models: `WhiteboardSession`, `WhiteboardAction`, `WhiteboardActionLog`
  (`lib/src/media/media_types.dart`).
- `WhiteboardPermissionError` (`lib/src/media/media_module.dart`); the
  `WHITEBOARD_DRAW_NOT_PERMITTED` special case in `withMediaErrors()` is gone
  along with it.
- `MediaEvent.asWhiteboardAction` getter.
- Event catalogues: `MediaWhiteboardEvents` (entire class); the five
  `classroom.chat_message*` entries from `MediaClassroomEvents`; the three
  `lobby.*` entries from `MediaRoomEvents` (`lib/src/media/media_events.dart`).
- `MediaModule.whiteboard` and `MediaModule.invites` fields.

This does **not** touch `acceptStageInvite()` / `declineStageInvite()` /
`inviteToStage()` (the unrelated "invite a participant onto the stage"
raise-hand flow), `MediaSession.joinToken` (the unrelated per-session
identity token), or any other working Media API.

## 0.3.2

Notification Event Engine completion: mirrors `supersosdk` 0.3.2 exactly. See
`docs/notification.md`'s "Events" section for the full reference.

> Note: the originating spec for this release called for a bump to `0.3.1`,
> but that version number was already used by the OTP migration entry below.
> This release is `0.3.2` instead so no history is overwritten.

### Added

- `NotificationModule.createEvent()` / `.updateEvent()` / `.deleteEvent()` /
  `.listEvents()` / `.getEvent()` / `.mapTemplates()` / `.updateStatus()` /
  `.triggerEvent()` (alias of `.trigger()`) — flat, Event-suffixed methods,
  backed by a new internal `EventsModule` (`lib/src/notification/notification_module.dart`).
  Not exposed as a public `.events` property, matching how `send()`/
  `broadcast()`/`trigger()` are flat methods rather than submodules — this
  mirrors `supersosdk`'s `NotificationEventsModule` exposure exactly.
- `NotificationModule.getEventHistory(id)` — the backend's `GET
  /notifications/events/:id/history` endpoint is new in this release; this
  method did not previously exist because the endpoint didn't either.
- `NotificationEvent`, `EventTemplateMapping`, `NotificationEventPage`, and
  `EventHistoryResult` models in `lib/src/notification/notification_types.dart`.
- `EventError` in `lib/src/notification/notification_module.dart`.

### Changed

- Template mapping is now optional when creating or updating an event
  (`createEvent(eventKey: ..., name: ...)` with no `templates` is valid — map
  channels later with `mapTemplates()`). Only `trigger()`/`triggerEvent()`
  still requires at least one mapping, throwing `EventError`/`TriggerError`
  (HTTP 422, `event_no_templates`) if none exist.

## 0.3.1

Backend upgrade: Email Verification and Password Reset are now exclusively
OTP-based across the whole platform (backend, both SDKs, Admin Dashboard).
See the backend and `supersosdk` changelogs for the full account of what
changed there.

### Audit — no SDK code changes required

`lib/src/auth` was audited end-to-end against this migration and found to
already be fully OTP-first, mirroring `supersosdk/src/auth` exactly:

- `EmailModule.sendVerification` / `EmailModule.verify` — always sent and
  validated a numeric code; there was never a link-based variant anywhere in
  this package.
- `PasswordModule.forgot` / `PasswordModule.reset` — `reset()` has always
  taken a `code` parameter, never a reset token or callback URL.

No `link`, `token`, or callback-URL concept exists anywhere under `lib/src/auth`
(verified by search). The retired backend flow
(`POST /auth/email/verify-link`, `AuthSettings.VerificationMethod`) was never
reachable through this SDK and required no client-side removal.

### Changed

- Doc comments on `EmailModule.sendVerification`/`verify` and
  `PasswordModule.forgot` now state explicitly that these flows are OTP-only.
- Version bumped to `0.3.1` to track the platform-wide OTP migration and stay
  aligned with `supersosdk`, even though this package's public API and
  behavior are unchanged.

## 0.3.0+1

Publishability pass. No API changes, no functionality removed.

### Fixed — compile errors

- **Parser failure in `media_module.dart` and `realtime_types.dart`.**
  `data is Map<String, dynamic> ? a : b` is genuinely ambiguous to the Dart
  parser: it reads `Map<String, dynamic>?` as a nullable type and then fails on
  the rest of the conditional, cascading into `expected ':'`,
  `missing_identifier`, and `non_bool_condition`. Both `dataAsMap` getters are
  now written as blocks with a promoted local.
- **`realtime_module.dart` used `SupersoError` without importing it.**
- **`realtime_socket.dart` used pattern-matching (`if (x case final String y
  when ...)`) inside a map literal.** Rewritten as plain null checks — the
  behaviour is identical and it removes any dependency on pattern support.
- **`NotificationSchedule` declared `this.createdAt` / `this.updatedAt` in its
  constructor with no matching fields.** Fields added.
- **`notification_module.dart` called `Iterable.firstOrNull`**, which lives in
  `package:collection`, not `dart:core`. Replaced with an explicit loop, so no
  new dependency was needed.
- **`storage_module.dart` called `Stream.whereType`**, which does not exist —
  `whereType` is on `Iterable`. Replaced with `where` + `map`.
- **Bare `const {}` literals** replaced with `const <String, dynamic>{}` so
  inference can never resolve them as a `Set`.

### Fixed — behaviour

- **Constructing `Superso` no longer opens a WebSocket.** `RealtimeModule`
  wired its internal frame listener to the lazily-connecting `messages` stream,
  so merely building the SDK dialled the network and produced unhandled async
  errors. `RealtimeSocket` now exposes `rawMessages` for internal wiring, and
  lazy connects log their failure instead of throwing into the void.
- **Cancellation no longer leaks an unhandled error** when a request completes
  after its `CancelToken` fired.

### Changed — packaging

- `http_parser` moved from `dev_dependencies` to `dependencies`: it is imported
  from `lib/src/utils/mime.dart`, so it is a real runtime dependency.
- Package description shortened to 145 characters (pub.dev penalises anything
  over 180).
- Added `topics` for pub.dev discoverability, and a `.gitignore` covering
  `build/`, `.dart_tool/`, and `pubspec.lock` so build output is never
  published. Existing artifacts removed from the tree.
- `public_member_api_docs` is still enabled as a lint but is no longer promoted
  to an error. Documentation completeness is a pub.dev *score* dimension, not a
  publishability gate, and promoting a style lint to an error breaks
  `flutter analyze` for any consumer analysing their whole dependency tree.
  Removed `missing_return` from the error list — it no longer exists in current
  SDKs and an unrecognised code is itself a warning.

### Fixed — tests

- The cancellation test never passed its token to a request, so it asserted a
  throw that could not happen. It now exercises `CancelToken` through the
  shared client, which is the layer the feature lives in, and a second test
  covers cancelling a request already in flight.
- `withMediaErrors` and `mapRealtimeRestError` only looked for the backend's
  error code nested under `error`. The shared client hands the error object
  through directly for most endpoints, so `WHITEBOARD_DRAW_NOT_PERMITTED` was
  never matched and surfaced as a generic host-authorization failure. Both now
  accept either shape.

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
