// Example app for superso_flutter_sdk.
//
// Demonstrates the two modules shipped in 0.3.0: sign-in via the Auth module
// (with automatic token capture and an auth-state stream), and a paginated
// query via the Database module.
//
// Replace `_baseUrl` and `_apiKey` with your own project's values.

import 'package:flutter/material.dart';
import 'package:superso_flutter_sdk/superso_flutter_sdk.dart';

const String _baseUrl = 'https://api.superso.io/v1';
const String _apiKey = 'sp_live_replace_me';

void main() => runApp(const SupersoExampleApp());

/// Root widget owning the single [Superso] instance for the app's lifetime.
class SupersoExampleApp extends StatefulWidget {
  /// Creates the example app.
  const SupersoExampleApp({super.key});

  @override
  State<SupersoExampleApp> createState() => _SupersoExampleAppState();
}

class _SupersoExampleAppState extends State<SupersoExampleApp> {
  late final Superso _superso;

  @override
  void initState() {
    super.initState();
    // One instance, created once, shared by every screen.
    _superso = Superso(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      logger: (level, message, [error]) => debugPrint('[$level] $message'),
    );
  }

  @override
  void dispose() {
    // Releases the HTTP connection pool and the auth-state stream controller.
    _superso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Superso Example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: StreamBuilder<AuthState>(
        stream: _superso.auth.authStateChanges,
        initialData: _superso.auth.currentState,
        builder: (context, snapshot) {
          final signedIn = snapshot.data?.isSignedIn ?? false;
          return signedIn
              ? PostsScreen(superso: _superso)
              : LoginScreen(superso: _superso);
        },
      ),
    );
  }
}

/// Email + password sign-in.
class LoginScreen extends StatefulWidget {
  /// Creates the login screen.
  const LoginScreen({required this.superso, super.key});

  /// The shared SDK instance.
  final Superso superso;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Tokens are captured automatically — no setAccessToken() call needed.
      await widget.superso.auth.login(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on AuthenticationError {
      setState(() => _error = 'Incorrect email or password.');
    } on NetworkError {
      setState(
          () => _error = 'Could not reach the server. Check your network.');
    } on SupersoError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 24),
            if (_error != null) ...<Widget>[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: _busy ? null : _login,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A paginated list of documents from the `posts` collection.
class PostsScreen extends StatefulWidget {
  /// Creates the posts screen.
  const PostsScreen({required this.superso, super.key});

  /// The shared SDK instance.
  final Superso superso;

  @override
  State<PostsScreen> createState() => _PostsScreenState();
}

class _PostsScreenState extends State<PostsScreen> {
  /// Cancels the in-flight query if the screen is disposed mid-request.
  final CancelToken _cancel = CancelToken();

  late Future<DatabasePage<DatabaseDocument<Map<String, dynamic>>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _cancel.cancel('PostsScreen disposed');
    super.dispose();
  }

  Future<DatabasePage<DatabaseDocument<Map<String, dynamic>>>> _load() async {
    final response = await widget.superso.database
        .collection('posts')
        .where('published', WhereOperator.equal, true)
        .orderBy('created_at', OrderByDirection.desc)
        .limit(20)
        .get();
    return response.data;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Posts'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => widget.superso.auth.logout(),
          ),
        ],
      ),
      body: FutureBuilder<DatabasePage<DatabaseDocument<Map<String, dynamic>>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final error = snapshot.error;
          if (error is CollectionNotFoundError) {
            return const Center(child: Text('No "posts" collection yet.'));
          }
          if (error != null) {
            return Center(child: Text('$error'));
          }

          final page = snapshot.data!;
          if (page.items.isEmpty) {
            return const Center(child: Text('No published posts.'));
          }
          return ListView.builder(
            itemCount: page.items.length,
            itemBuilder: (context, i) {
              final doc = page.items[i];
              return ListTile(
                title: Text('${doc.data['title'] ?? '(untitled)'}'),
                // Always docId — never `id` — for follow-up operations.
                subtitle: Text(doc.docId),
              );
            },
          );
        },
      ),
    );
  }
}
