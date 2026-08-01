/// The AI module — the Superso AI Gateway.
///
/// Dart port of `supersosdk/src/ai/*`.
///
/// **Scope.** `docs/ai.md` documents exactly one REST endpoint:
/// `POST /v1/ai/chat`. Everything else (usage, analytics, logs, limits,
/// settings, and any live provider or model catalog) is described only as an
/// Admin Dashboard *page* — no endpoint, method, or schema is ever given, and
/// the backend's SDK route table registers exactly one route. Those surfaces
/// live behind the Admin JWT API, a different authentication model than this
/// SDK's `X-API-Key` design.
///
/// This module therefore implements chat (real, working), plus provider and
/// model reference lookups that are static and synchronous — never a network
/// call, because no such endpoint exists. Shipping methods that would reliably
/// 404 would be worse than omitting them.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import '../client/superso_http_client.dart';
import '../errors/superso_error.dart';
import '../interfaces/sdk_module.dart';
import '../types/common.dart';

/// The author of a chat message.
enum MessageRole {
  /// Instructions that steer the assistant's behaviour.
  system('system'),

  /// A message from the end user.
  user('user'),

  /// A message produced by the model.
  assistant('assistant');

  const MessageRole(this.wireValue);

  /// The value sent to and received from the backend.
  final String wireValue;

  /// Parses a wire value, defaulting to [user] for anything unrecognized.
  static MessageRole fromWire(String? value) => values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => MessageRole.user,
      );
}

/// The `provider` values the gateway accepts.
///
/// Providers are configured and enabled per project through the Admin
/// Dashboard. This SDK never hardcodes provider-specific request or response
/// handling — the gateway normalizes that server-side and returns the same
/// shape regardless of provider.
enum AIProviderName {
  /// OpenAI.
  openai('openai'),

  /// Anthropic Claude.
  anthropic('anthropic'),

  /// Google Gemini.
  gemini('gemini'),

  /// xAI Grok.
  xai('xai'),

  /// DeepSeek.
  deepseek('deepseek'),

  /// OpenRouter.
  openrouter('openrouter'),

  /// Self-hosted Ollama.
  ollama('ollama'),

  /// Any OpenAI-compatible custom endpoint.
  custom('custom');

  const AIProviderName(this.wireValue);

  /// The value sent to the backend.
  final String wireValue;

  /// Parses a wire value, returning `null` for anything unrecognized.
  static AIProviderName? fromWire(String? value) {
    for (final provider in values) {
      if (provider.wireValue == value) return provider;
    }
    return null;
  }
}

/// One message in a conversation turn.
@immutable
class ChatMessage {
  /// Creates a message.
  const ChatMessage({required this.role, required this.content});

  /// Creates a [MessageRole.system] message.
  const ChatMessage.system(this.content) : role = MessageRole.system;

  /// Creates a [MessageRole.user] message.
  const ChatMessage.user(this.content) : role = MessageRole.user;

  /// Creates a [MessageRole.assistant] message.
  const ChatMessage.assistant(this.content) : role = MessageRole.assistant;

  /// Decodes a message from JSON.
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: MessageRole.fromWire(json['role'] as String?),
        content: json['content'] as String? ?? '',
      );

  /// Who authored this message.
  final MessageRole role;

  /// The message text.
  final String content;

  /// Encodes this message to the platform's JSON shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'role': role.wireValue,
        'content': content,
      };

  @override
  String toString() => 'ChatMessage(${role.wireValue}: $content)';
}

/// Token accounting for one completion.
///
/// The wire response carries `tokens_in`/`tokens_out`/`total_tokens`; this
/// exposes them under the `prompt`/`completion` vocabulary the documentation's
/// example response uses, so code written against either naming works.
@immutable
class TokenUsage {
  /// Creates a usage record.
  const TokenUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });

  /// Tokens consumed by the prompt.
  final int promptTokens;

  /// Tokens produced by the model.
  final int completionTokens;

  /// The sum of both.
  final int totalTokens;

  @override
  String toString() =>
      'TokenUsage(prompt: $promptTokens, completion: $completionTokens, '
      'total: $totalTokens)';
}

/// A single completion choice.
///
/// The documented example response wraps the assistant message in an
/// OpenAI-style `choices[]` array. The backend actually returns a single flat
/// `message` field — no `choices`, no `finish_reason`. This is synthesized
/// client-side so code following the documented example still finds
/// `choices.first`; [finishReason] is always `null`, because the backend never
/// sends one.
@immutable
class Choice {
  /// Creates a choice.
  const Choice({required this.index, required this.message, this.finishReason});

  /// Position in the choices list. Always 0.
  final int index;

  /// The assistant's message.
  final ChatMessage message;

  /// Always `null` — the backend does not report a finish reason.
  final String? finishReason;
}

/// The result of a chat completion.
///
/// [provider], [model], [message], [tokensIn], [tokensOut], [totalTokens], and
/// [latencyMs] are exactly what `POST /v1/ai/chat` returns. [choices] and
/// [usage] are derived convenience views — see [Choice].
@immutable
class ChatResponse {
  /// Creates a chat response.
  const ChatResponse({
    required this.provider,
    required this.model,
    required this.message,
    required this.tokensIn,
    required this.tokensOut,
    required this.totalTokens,
    required this.latencyMs,
    required this.choices,
    required this.usage,
  });

  /// Decodes and normalizes a response from the wire shape.
  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    final message = ChatMessage.fromJson(
      json['message'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
    final tokensIn = (json['tokens_in'] as num?)?.toInt() ?? 0;
    final tokensOut = (json['tokens_out'] as num?)?.toInt() ?? 0;
    final total = (json['total_tokens'] as num?)?.toInt() ?? 0;
    return ChatResponse(
      provider: json['provider'] as String? ?? '',
      model: json['model'] as String? ?? '',
      message: message,
      tokensIn: tokensIn,
      tokensOut: tokensOut,
      totalTokens: total,
      latencyMs: (json['latency_ms'] as num?)?.toInt() ?? 0,
      choices: <Choice>[Choice(index: 0, message: message)],
      usage: TokenUsage(
        promptTokens: tokensIn,
        completionTokens: tokensOut,
        totalTokens: total,
      ),
    );
  }

  /// The provider that served this completion.
  final String provider;

  /// The model that produced it.
  final String model;

  /// The assistant's reply.
  final ChatMessage message;

  /// Tokens consumed by the prompt.
  final int tokensIn;

  /// Tokens produced by the model.
  final int tokensOut;

  /// The sum of both.
  final int totalTokens;

  /// End-to-end latency, in milliseconds.
  final int latencyMs;

  /// Synthesized OpenAI-style choices list. Always exactly one entry.
  final List<Choice> choices;

  /// Synthesized token usage view.
  final TokenUsage usage;

  /// The reply text — shorthand for `message.content`.
  String get text => message.content;

  @override
  String toString() =>
      'ChatResponse($provider/$model, ${totalTokens} tokens, ${latencyMs}ms)';
}

/// A documented gateway provider.
@immutable
class AIProvider {
  /// Creates a provider reference entry.
  const AIProvider({
    required this.name,
    required this.value,
    required this.notes,
  });

  /// Human-readable name, e.g. `Anthropic Claude`.
  final String name;

  /// The value to pass as `provider`.
  final AIProviderName value;

  /// The documented model notes for this provider.
  final String notes;

  @override
  String toString() => 'AIProvider(${value.wireValue})';
}

/// Base class for every AI-domain error.
class AIError extends SupersoError {
  /// Creates an AI error.
  const AIError(
    String message, {
    int? status,
    String? code,
    Object? details,
  }) : super(message: message, status: status, code: code, details: details);
}

/// The requested provider is unknown, not configured, or not enabled.
///
/// Named `AIProviderError` because the Notification module already exports a
/// `ProviderError`.
class AIProviderError extends AIError {
  /// Creates a provider error.
  const AIProviderError(
    String message, [
    int? status,
    Object? details,
  ]) : super(message, status: status, code: 'AI_PROVIDER_ERROR', details: details);
}

/// The requested model is unavailable or was rejected by the provider.
class AIModelError extends AIError {
  /// Creates a model error.
  const AIModelError(
    String message, [
    int? status,
    Object? details,
  ]) : super(message, status: status, code: 'AI_MODEL_ERROR', details: details);
}

/// Wraps an AI call, normalizing failures into the AI error hierarchy.
///
/// Authentication, permission, rate-limit, and network errors pass through
/// unchanged, because their meaning does not depend on the module.
Future<T> withAIErrors<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on AuthenticationError {
    rethrow;
  } on PermissionError {
    rethrow;
  } on RateLimitError {
    rethrow;
  } on NetworkError {
    rethrow;
  } on CancelledError {
    rethrow;
  } on SupersoError catch (error) {
    throw AIError(
      error.message,
      status: error.status,
      code: error.code,
      details: error.details,
    );
  } on Object catch (error) {
    throw AIError('$error');
  }
}

/// Static, doc-sourced provider reference data.
///
/// Every method here is synchronous and performs no network call: the
/// documentation's "Supported Providers" table is the only place providers are
/// described, and no `X-API-Key` endpoint lists which are configured for a
/// project.
///
/// There is deliberately no `default()` or `enabled()`: which provider is
/// default or enabled is per-project server-side state with no SDK-visible
/// representation. To use the gateway's documented default selection, simply
/// omit `provider` from a chat call.
class AIProvidersModule {
  /// Creates the providers reference module.
  const AIProvidersModule();

  static const List<AIProvider> _providers = <AIProvider>[
    AIProvider(
      name: 'OpenAI',
      value: AIProviderName.openai,
      notes: 'GPT-4o, GPT-4, GPT-3.5, o1, o3',
    ),
    AIProvider(
      name: 'Anthropic Claude',
      value: AIProviderName.anthropic,
      notes: 'Claude Sonnet, Opus, Haiku',
    ),
    AIProvider(
      name: 'Google Gemini',
      value: AIProviderName.gemini,
      notes: 'Gemini 2.0 Flash, 1.5 Pro, 1.5 Flash',
    ),
    AIProvider(
      name: 'xAI Grok',
      value: AIProviderName.xai,
      notes: 'Grok-2, Grok-beta',
    ),
    AIProvider(
      name: 'DeepSeek',
      value: AIProviderName.deepseek,
      notes: 'deepseek-chat, deepseek-reasoner',
    ),
    AIProvider(
      name: 'OpenRouter',
      value: AIProviderName.openrouter,
      notes: '100+ models via unified endpoint',
    ),
    AIProvider(
      name: 'Ollama (Local)',
      value: AIProviderName.ollama,
      notes: 'Self-hosted, no API key required',
    ),
    AIProvider(
      name: 'Custom Endpoint',
      value: AIProviderName.custom,
      notes: 'Any OpenAI-compatible endpoint',
    ),
  ];

  /// Every documented provider.
  List<AIProvider> list() => List<AIProvider>.unmodifiable(_providers);

  /// Looks up a provider by its wire value.
  ///
  /// Throws an [AIProviderError] if [provider] is not a documented value.
  AIProvider get(String provider) {
    for (final entry in _providers) {
      if (entry.value.wireValue == provider) return entry;
    }
    throw AIProviderError(
      '"$provider" is not a documented Superso AI Gateway provider. '
      'Supported values: '
      '${_providers.map((p) => p.value.wireValue).join(', ')}.',
    );
  }

  /// Whether [provider] is a documented value.
  bool supports(String provider) =>
      _providers.any((p) => p.value.wireValue == provider);

  /// An alias of [supports].
  bool exists(String provider) => supports(provider);
}

/// Static, doc-sourced model reference data.
///
/// The documentation never publishes a machine-readable model catalog — the
/// notes column is free-form prose — and no `X-API-Key` endpoint returns one.
/// These methods therefore return the literal documented notes per provider,
/// not a fabricated list of exact model IDs.
class AIModelsModule {
  /// Creates the models reference module bound to [_providers].
  const AIModelsModule(this._providers);

  final AIProvidersModule _providers;

  /// The documented model notes for every provider.
  Map<AIProviderName, String> list() => <AIProviderName, String>{
        for (final provider in _providers.list()) provider.value: provider.notes,
      };

  /// The documented model notes for one provider.
  ///
  /// Throws an [AIProviderError] if [provider] is unknown.
  String byProvider(String provider) => _providers.get(provider).notes;
}

/// A stateful multi-turn conversation.
///
/// [send] appends the user message, calls the gateway with the full history
/// (plus any seeded system prompt), appends the assistant's reply, and returns
/// the reply text. [history], [clear], and [reset] make no network call.
///
/// ```dart
/// final chat = superso.ai.session(
///   systemPrompt: 'You are a helpful coding assistant.',
/// );
/// print(await chat.send('What does Iterable.fold do?'));
/// print(await chat.send('Show me an example.'));
/// ```
class ConversationSession {
  /// Creates a session. Obtain one from [AIModule.session].
  ConversationSession(
    this._send, {
    this.systemPrompt,
    this.provider,
    this.model,
  }) {
    _messages = _seed();
  }

  final Future<ChatResponse> Function({
    required List<ChatMessage> messages,
    String? provider,
    String? model,
    double? temperature,
    int? maxTokens,
  }) _send;

  /// An optional system prompt seeded as the first message.
  final String? systemPrompt;

  /// The provider used for every turn, unless overridden per call.
  final String? provider;

  /// The model used for every turn, unless overridden per call.
  final String? model;

  late List<ChatMessage> _messages;

  /// Sends [content] as a user message and returns the assistant's reply.
  Future<String> send(
    String content, {
    String? provider,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    _messages.add(ChatMessage.user(content));
    final response = await _send(
      messages: List<ChatMessage>.of(_messages),
      provider: provider ?? this.provider,
      model: model ?? this.model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    _messages.add(response.message);
    return response.message.content;
  }

  /// The full history so far, including any seeded system prompt.
  ///
  /// Returns a copy; mutating it does not affect the session.
  List<ChatMessage> history() => List<ChatMessage>.unmodifiable(_messages);

  /// Empties the history entirely, including the seeded system prompt.
  void clear() => _messages = <ChatMessage>[];

  /// Restores the history to its initial state — the seeded system prompt and
  /// nothing else.
  void reset() => _messages = _seed();

  List<ChatMessage> _seed() => <ChatMessage>[
        if (systemPrompt != null) ChatMessage.system(systemPrompt!),
      ];
}

/// The composition root for the Superso AI Gateway.
///
/// ```dart
/// final reply = await superso.ai.complete('Write a haiku about the ocean.');
///
/// final response = await superso.ai.chat(
///   messages: [const ChatMessage.user('Explain CRDTs briefly.')],
///   provider: 'anthropic',
/// );
/// print('${response.data.text} (${response.data.totalTokens} tokens)');
/// ```
class AIModule implements SdkModule {
  /// Creates the AI module bound to [client].
  AIModule(this.client)
      : providers = const AIProvidersModule(),
        models = const AIModelsModule(AIProvidersModule());

  @override
  final SupersoHttpClient client;

  /// Static provider reference data.
  final AIProvidersModule providers;

  /// Static model reference data.
  final AIModelsModule models;

  /// `POST /v1/ai/chat` — sends a conversation and returns the completion.
  ///
  /// Throws a [ValidationError] if [messages] is empty, matching the backend's
  /// own `ErrMissingMessages` check without a round trip.
  ///
  /// [stream] is accepted because the backend DTO carries the field, but the
  /// gateway is non-streaming regardless of its value; it is reserved for
  /// future use.
  Future<ApiResponse<ChatResponse>> chat({
    required List<ChatMessage> messages,
    String? provider,
    String? model,
    double? temperature,
    int? maxTokens,
    bool? stream,
    String? userId,
  }) {
    if (messages.isEmpty) {
      throw const ValidationError(
        'Superso: at least one message is required to start a chat.',
      );
    }
    return withAIErrors(
      () => client.post<ChatResponse>(
        '/ai/chat',
        body: <String, dynamic>{
          'messages': messages.map((m) => m.toJson()).toList(growable: false),
          if (provider != null) 'provider': provider,
          if (model != null) 'model': model,
          if (temperature != null) 'temperature': temperature,
          if (maxTokens != null) 'max_tokens': maxTokens,
          if (stream != null) 'stream': stream,
          if (userId != null) 'user_id': userId,
        },
        decoder: (data) => ChatResponse.fromJson(
          data as Map<String, dynamic>? ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  /// A convenience wrapper over [chat] that takes a single prompt and returns
  /// just the reply text.
  Future<String> complete(
    String prompt, {
    String? provider,
    String? model,
    double? temperature,
    int? maxTokens,
    String? userId,
  }) async {
    final response = await chat(
      messages: <ChatMessage>[ChatMessage.user(prompt)],
      provider: provider,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
      userId: userId,
    );
    return response.data.text;
  }

  /// Starts a stateful multi-turn conversation.
  ConversationSession session({
    String? systemPrompt,
    String? provider,
    String? model,
  }) {
    return ConversationSession(
      ({
        required List<ChatMessage> messages,
        String? provider,
        String? model,
        double? temperature,
        int? maxTokens,
      }) async {
        final response = await chat(
          messages: messages,
          provider: provider,
          model: model,
          temperature: temperature,
          maxTokens: maxTokens,
        );
        return response.data;
      },
      systemPrompt: systemPrompt,
      provider: provider,
      model: model,
    );
  }
}
