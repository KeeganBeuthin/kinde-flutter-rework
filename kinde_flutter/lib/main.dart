import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:kinde_flutter_sdk/kinde_flutter_sdk.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:kinde_flutter/encrypted_box.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await dotenv.load(fileName: ".env");
  
  await KindeFlutterSDK.initializeSDK(
    authDomain: dotenv.env['KINDE_AUTH_DOMAIN']!,
    authClientId: dotenv.env['KINDE_AUTH_CLIENT_ID']!,
    loginRedirectUri: 'com.example.kindeflutter.auth://kinde_callback',
    logoutRedirectUri: dotenv.env['KINDE_LOGOUT_REDIRECT_URI']!,
    scopes: ["email", "profile", "offline", "openid"]
  );

   await EncryptedBox.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kinde Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Kinde Flutter Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final kindeClient = KindeFlutterSDK.instance;
  final ValueNotifier<bool> _loading = ValueNotifier(false);
  final ValueNotifier<UserProfileV2?> _profile = ValueNotifier(null);
  final ValueNotifier<bool> _loggedIn = ValueNotifier(false);
  final ValueNotifier<Map<String, dynamic>> _testResults = ValueNotifier({});

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    print('\n=== Initial App Launch Check ===');
    print('Checking stored auth state...');
    
    final isAuthenticated = await kindeClient.isAuthenticate();
    final authState = kindeClient.authState;
    
    print('Has Stored Auth State: ${authState != null}');
    print('Has Stored Refresh Token: ${authState?.refreshToken != null}');
    print('Token Expiration: ${authState?.accessTokenExpirationDateTime}');
    print('Is Authenticated: $isAuthenticated');
    
    _loggedIn.value = isAuthenticated;
    
    if (isAuthenticated) {
      _getProfile();
    }
  }

  void _signIn() {
    kindeClient.login(type: AuthFlowType.pkce).then((token) {
      if (token != null) {
        print('Login Token: $token');
        _loggedIn.value = true;
        _getProfile();
      } else {
        print('Login failed: No token received');
      }
    }).catchError((error) {
      print('Login Error: $error');
    });
  }

  void _signOut() {
    kindeClient.logout().then((value) {
      _loggedIn.value = false;
      _profile.value = null;
      print('Signed out successfully');
    }).catchError((error) {
      print('Sign Out Error: $error');
    });
  }

  void _signUp() {
    kindeClient.register().catchError((error) {
      print('Sign Up Error: $error');
    });
  }

  void _getProfile() {
    _loading.value = true;
    kindeClient.getUserProfileV2().then((profile) async {
      _profile.value = profile;
      print('User Profile: ${profile?.givenName}');
    }).whenComplete(() => _loading.value = false).catchError((error) {
      print('Get Profile Error: $error');
    });
  }

  void _testTokenState() async {
    print('\n=== Current Token State ===');
    final token = await kindeClient.getToken();
    final authState = kindeClient.authState;
    print('Token Present: ${token != null}');
    print('Token Expiration: ${authState?.accessTokenExpirationDateTime}');
    print('Has Refresh Token: ${authState?.refreshToken != null}');
  }

  void _testProfileFetch() async {
    print('\n=== Testing Profile Fetch ===');
    try {
      final profile = await kindeClient.getUserProfileV2();
      print('Profile Request Success: ${profile?.email}');
    } catch (e) {
      print('Profile Request Failed: $e');
    }
  }

  void _testClaims() async {
    print('\n=== Testing Claims ===');
    try {
      final token = await kindeClient.getToken();
      if (token != null) {
        final jwt = JWT.decode(token);
        final payload = jwt.payload;
        print('Claims from token:');
        print('Audience: ${payload['aud']}');
        print('Given Name: ${payload['given_name']}');
        print('All Claims: $payload');
      }
    } catch (e) {
      print('Claims Test Failed: $e');
    }
  }

  void _testPermissions() async {
    print('\n=== Testing Permissions ===');
    try {
      final token = await kindeClient.getToken();
      if (token != null) {
        final jwt = JWT.decode(token);
        print('Permissions: ${jwt.payload['permissions']}');
      }
    } catch (e) {
      print('Permissions Test Failed: $e');
    }
  }

  void _testFeatureFlags() async {
    print('\n=== Testing Feature Flags ===');
    try {
      final token = await kindeClient.getToken();
      if (token != null) {
        final jwt = JWT.decode(token);
        print('Feature Flags: ${jwt.payload['feature_flags']}');
      }
    } catch (e) {
      print('Feature Flags Test Failed: $e');
    }
  }

  void _testOrganizations() async {
    print('\n=== Testing Organizations ===');
    try {
      final token = await kindeClient.getToken();
      if (token != null) {
        final jwt = JWT.decode(token);
        print('Organization Code: ${jwt.payload['org_code']}');
      }
    } catch (e) {
      print('Organizations Test Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                ListenableBuilder(
                  listenable: Listenable.merge([_loading, _profile]),
                  builder: (context, _) {
                    return Column(
                      children: [
                        if (_loading.value)
                          const CircularProgressIndicator()
                        else if (_profile.value != null)
                          Text('Welcome ${_profile.value?.givenName ?? "User"}!'),
                      ],
                    );
                  },
                ),
                ValueListenableBuilder(
                  valueListenable: _loggedIn,
                  builder: (_, isLoggedIn, __) {
                    if (!isLoggedIn) {
                      return Column(
                        children: [
                          ElevatedButton(
                            onPressed: _signIn,
                            child: const Text('Sign In'),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _signUp,
                            child: const Text('Sign Up'),
                          ),
                        ],
                      );
                    }

                    return Column(
                      children: [
                        // Auth Section
                        _buildSection(
                          'Authentication Tests',
                          [
                            _buildTestButton('Sign Out', _signOut, Colors.red),
                            _buildTestButton('Check Token State', _testTokenState, Colors.orange),
                            _buildTestButton('Test Profile Fetch', _testProfileFetch, Colors.blue),
                          ],
                        ),

                        // Claims Section
                        _buildSection(
                          'Claims Tests',
                          [
                            _buildTestButton('Test Claims', _testClaims, Colors.green),
                          ],
                        ),

                        // Permissions Section
                        _buildSection(
                          'Permissions Tests',
                          [
                            _buildTestButton('Test Permissions', _testPermissions, Colors.purple),
                          ],
                        ),

                        // Feature Flags Section
                        _buildSection(
                          'Feature Flags Tests',
                          [
                            _buildTestButton('Test Feature Flags', _testFeatureFlags, Colors.teal),
                          ],
                        ),

                        // Organizations Section
                        _buildSection(
                          'Organizations Tests',
                          [
                            _buildTestButton('Test Organizations', _testOrganizations, Colors.indigo),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> buttons) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...buttons,
        ],
      ),
    );
  }

  Widget _buildTestButton(String label, VoidCallback onPressed, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
        ),
        child: Text(label),
      ),
    );
  }
}