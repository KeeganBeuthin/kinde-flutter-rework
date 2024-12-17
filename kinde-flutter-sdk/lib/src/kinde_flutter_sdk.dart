import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    as secure_store;
import 'package:hive/hive.dart';
import 'package:jose/jose.dart';
import 'package:kinde_flutter_sdk/kinde_flutter_sdk.dart';
import 'package:kinde_flutter_sdk/src/handle_network_error_mixin.dart';
import 'package:kinde_flutter_sdk/src/keys/keys_api.dart';
import 'package:kinde_flutter_sdk/src/kinde_error.dart';
import 'package:kinde_flutter_sdk/src/store/store.dart';
import 'package:kinde_flutter_sdk/src/token/auth_state.dart';
import 'package:kinde_flutter_sdk/src/token/refresh_token_interceptor.dart';
import 'package:kinde_flutter_sdk/src/token/token_api.dart';
import 'package:kinde_flutter_sdk/src/token/token_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pubspec_parse/pubspec_parse.dart';

class KindeFlutterSDK with TokenUtils, HandleNetworkMixin {
  static const _orgCodeParamName = 'org_code';
  static const _orgNameParamName = 'org_name';
  static const _audienceParamName = 'audience';
  static const _createOrgParamName = 'is_create_org';
  static const _redirectParamName = 'redirect';
  static const _postLogoutRedirectParamName = 'post_logout_redirect_uri';
  static const _registrationPageParamName = 'start_page';
  static const _registrationPageParamValue = 'registration';
  static const _authPath = '/oauth2/auth';
  static const _tokenPath = '/oauth2/token';
  static const _logoutPath = '/logout';
  static const _defaultScopes = ['openid', 'profile', 'email', 'offline'];
  static const _bearerAuth = 'kindeBearerAuth';
  static const _clientIdParamName = 'client_id';

  // Singleton
  static KindeFlutterSDK? _instance;

  @override
  AuthState? get authState => _store.authState;

  static AuthConfig? _config;
  late KindeApi _kindeApi;
  late KeysApi _keysApi;
  late TokenApi _tokenApi;
  late AuthorizationServiceConfiguration _serviceConfiguration;

  static KindeFlutterSDK get instance {
    _instance ??= KindeFlutterSDK._internal();
    return _instance ?? KindeFlutterSDK._internal();
  }

  KindeFlutterSDK._internal() {
    if (_config == null) {
      throw KindeError('KindeFlutterSDK have not been configured');
    }

    var domainUrl = "";
    if (_config!.authDomain.startsWith('https')) {
      domainUrl = _config!.authDomain;
    } else if (_config!.authDomain.startsWith('http')) {
      domainUrl = _config!.authDomain.replaceFirst('http', "https");
    } else {
      domainUrl = 'https://${_config!.authDomain}';
    }

    _serviceConfiguration = AuthorizationServiceConfiguration(
        authorizationEndpoint: '$domainUrl$_authPath',
        tokenEndpoint: '$domainUrl$_tokenPath',
        endSessionEndpoint: '$domainUrl$_logoutPath');

    Dio dio = Dio(BaseOptions(
      baseUrl: domainUrl,
    ));

    _kindeApi = KindeApi(dio: dio, interceptors: [
      BearerAuthInterceptor(),
      RefreshTokenInterceptor(
        dio: dio,
        refreshToken: getToken,
      ),
    ]);
    _keysApi = KeysApi(_kindeApi.dio);
    _tokenApi = TokenApi(_kindeApi.dio);

    if (_store.keys == null) {
      _keysApi.getKeys().then((value) {
        _store.keys = value;
      });
    }

    var token = authState?.accessToken;
    if (token != null) {
      _kindeApi.setBearerAuth(_bearerAuth, token);
    }
  }

  Store get _store => Store.instance;

  static Future<void> initializeSDK(
      {required String authDomain,
      required String authClientId,
      required String loginRedirectUri,
      required String logoutRedirectUri,
      List<String> scopes = _defaultScopes,
      String? audience}) async {
    _config = AuthConfig(
        authDomain: authDomain,
        authClientId: authClientId,
        loginRedirectUri: loginRedirectUri,
        logoutRedirectUri: logoutRedirectUri,
        scopes: scopes,
        audience: audience);

    secure_store.FlutterSecureStorage secureStorage =
        const secure_store.FlutterSecureStorage(
            aOptions: secure_store.AndroidOptions());

    Future<List<int>> getSecureKey(
        secure_store.FlutterSecureStorage secureStorage) async {
      var containsEncryptionKey =
          await secureStorage.containsKey(key: 'encryptionKey');
      if (!containsEncryptionKey) {
        var key = Hive.generateSecureKey();
        await secureStorage.write(
            key: 'encryptionKey', value: base64UrlEncode(key));
        return key;
      } else {
        final base64 = await secureStorage.read(key: 'encryptionKey');
        return base64Url.decode(base64!);
      }
    }

    final secureKey = await getSecureKey(secureStorage);

    final path = await getTemporaryDirectory();

    await Store.init(HiveAesCipher(secureKey), path.path);
  }

  Future<void> logout() async {
    if (Platform.isIOS) {
      final browser = ChromeSafariBrowser();
      await browser.open(url: _buildEndSessionUrl()).then((value) async {
        await browser.close();
      });
    } else {
      await launchUrl(_buildEndSessionUrl());
    }
    _kindeApi.setBearerAuth(_bearerAuth, '');
    await Store.instance.clear();
  }

  Future<String?> login({
    AuthFlowType? type,
    String? orgCode,
    String? loginHint,
    AuthUrlParams? authUrlParams,
  }) async {
    return _redirectToKinde(
      type: type,
      orgCode: orgCode,
      loginHint: loginHint,
      additionalParams: authUrlParams?.toMap() ?? {},
    );
  }

  Future<String?> _redirectToKinde(
      {AuthFlowType? type,
        String? orgCode,
        String? loginHint,
        Map<String, String> additionalParams = const {}}) async {
    final params = HashMap<String, String>.from(additionalParams);
    if (orgCode != null) {
      params.putIfAbsent(_orgCodeParamName, () => orgCode);
    }
    if (_config?.audience != null) {
      params.putIfAbsent(_audienceParamName, () => _config!.audience!);
    }

    if (type == AuthFlowType.pkce) {
      return _pkceLogin(loginHint, params);
    } else {
      return _normalLogin(loginHint, params);
    }
  }

  Future<void> register({
    AuthFlowType? type,
    String? orgCode,
    String? loginHint,
    AuthUrlParams? authUrlParams,
  }) async {
    final additionalParams = {
      _registrationPageParamName: _registrationPageParamValue
    };
    if (authUrlParams != null) {
      additionalParams.addAll(authUrlParams.toMap());
    }

    await _redirectToKinde(
        type: type,
        orgCode: orgCode,
        loginHint: loginHint,
        additionalParams: additionalParams);
  }

  Future<UserProfileV2?> getUserProfileV2() async {
    return _kindeApi.getOAuthApi().getUserProfileV2().then((value) {
      return value.data;
    }).catchError((error) {
      throw handleError(error);
    });
  }

  Future<UserProfile?> getUser() async {
    return _kindeApi.getOAuthApi().getUser().then((value) {
      return value.data;
    }).catchError((error) {
      throw handleError(error);
    });
  }

  Future<void> createOrg({required String orgName, AuthFlowType? type}) async {
    await _redirectToKinde(type: type, orgCode: null, additionalParams: {
      _registrationPageParamName: _registrationPageParamValue,
      _createOrgParamName: "true",
      _orgNameParamName: orgName
    });
  }

  Future<String?> getToken() async {
    print('\n=== Token Refresh Attempt ===');
    print('Current Time: ${DateTime.now()}');
    print('Has Auth State: ${authState != null}');
    print('Has Refresh Token: ${authState?.refreshToken != null}');
    print('Token Expiration: ${authState?.accessTokenExpirationDateTime}');
    
    if (await isAuthenticate()) {
      print('Still authenticated, returning existing token');
      return _store.authState?.accessToken;
    }
    
    try {
      if (authState?.refreshToken == null) {
        print('❌ No refresh token available');
        throw KindeError("Session expired or invalid");
      }
      
      print('Attempting token refresh...');
      final params = authState!.createRequestTokenParam()
        ..putIfAbsent(_clientIdParamName, () => _config!.authClientId);
      
      final data = await _tokenApi.retrieveToken(
        _config!.authClientId,
        params,
      );
      print('Token refresh successful');
      
      _store.authState = AuthState.fromJson(data as Map<String, dynamic>);
      _kindeApi.setBearerAuth(_bearerAuth, _store.authState?.accessToken ?? '');
      return _store.authState?.accessToken;
    } catch (e) {
      print('❌ Token refresh error: $e');
      rethrow;
    }
  }

  Future<bool> isAuthenticate() async {
    print('\n=== Authentication Check ===');
    print('Has Auth State: ${authState != null}');
    if (authState != null) {
      print('Token Expiration: ${authState!.accessTokenExpirationDateTime}');
      print('Is Expired: ${authState!.isExpired()}');
    }
    
    final isValid = await _checkToken();
    print('Token Valid: $isValid');
    
    return authState != null && !authState!.isExpired() && isValid;
  }

  Future<String?> _normalLogin(
      String? loginHint, Map<String, String> additionalParams) async {
    const appAuth = FlutterAppAuth();
    return await appAuth
        .authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        _config!.authClientId,
        _config!.loginRedirectUri,
        serviceConfiguration: _serviceConfiguration,
        scopes: _config!.scopes,
        promptValues: ['login'],
        loginHint: loginHint,
        additionalParameters: additionalParams,
      ),
    )
        .then((value) {
      if (additionalParams.containsKey(_orgNameParamName)) {
        return additionalParams[_orgNameParamName];
      }
      _saveState(value);
      return value?.accessToken;
    }).catchError((ex) {
      return null;
    });
  }

  Future<String?> _pkceLogin(
      String? loginHint, Map<String, String> additionalParams) async {
    const appAuth = FlutterAppAuth();
    try {
      final value = await appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          _config!.authClientId,
          _config!.loginRedirectUri,
          serviceConfiguration: _serviceConfiguration,
          scopes: _config!.scopes,
          promptValues: ['login'],
          loginHint: loginHint,
          additionalParameters: additionalParams,
          preferEphemeralSession: false,
        ),
      );
      
      if (additionalParams.containsKey(_orgNameParamName)) {
        return additionalParams[_orgNameParamName];
      }
      _saveState(value);
      return value?.accessToken;
    } catch (ex) {
      return null;
    }
  }

  WebUri _buildEndSessionUrl() {
    var uri = WebUri(_serviceConfiguration.endSessionEndpoint!)
        .replace(queryParameters: {
      _postLogoutRedirectParamName: _config!.logoutRedirectUri,
      _redirectParamName: _config!.logoutRedirectUri,
    });
    return WebUri.uri(uri);
  }

  Future<bool> _checkToken() async {
    final keys = _store.keys?.keys;
    final currentToken = _store.authState?.accessToken;
    
    if (keys == null || keys.isEmpty || currentToken == null) {
      return false;
    }
    
    try {
      final key = keys.first;
      var jwt = JsonWebToken.unverified(currentToken);

      var jwk = JsonWebKey.fromJson(key.toJson());
      var keyStore = JsonWebKeyStore()..addKey(jwk);

      final isValid = await jwt.verify(keyStore);
      
      // Additional expiry check
      if (isValid && _store.authState?.accessTokenExpirationDateTime != null) {
        final now = DateTime.now();
        return now.isBefore(_store.authState!.accessTokenExpirationDateTime!);
      }
      
      return isValid;
    } catch (e) {
      return false;  // Any verification error means invalid token
    }
  }

  _saveState(TokenResponse? tokenResponse) {
    if (tokenResponse?.accessToken == null || tokenResponse?.idToken == null) {
      return;
    }
    
    // Force 60 second expiration for testing
    final shortExpiration = DateTime.now().add(Duration(seconds: 60));
    print('Setting short expiration: $shortExpiration');
    
    _store.authState = AuthState(
      accessToken: tokenResponse?.accessToken,
      idToken: tokenResponse?.idToken,
      accessTokenExpirationDateTime: shortExpiration,  // Override normal expiration
      refreshToken: tokenResponse?.refreshToken,
      scope: tokenResponse?.scopes?.join(' ')
    );
    _kindeApi.setBearerAuth(_bearerAuth, tokenResponse?.accessToken ?? '');
  }

  Future<String> _getVersion() async {
    try {
      final fileContent = await rootBundle.loadString(
        "packages/kinde_flutter_sdk/pubspec.yaml",
      );
      final pubspec = Pubspec.parse(fileContent);
      return pubspec.version?.canonicalizedVersion ?? '';
    } catch (exception) {
      return '';
    }
  }
}