import 'dart:convert';
import 'dart:io';

import 'package:content_sources/content_sources.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Directory dir;
  late Uri root;
  var approved = false;

  setUp(() async {
    approved = false;
    dir = await Directory.systemTemp.createTemp('login-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    root = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      final path = request.uri.path;
      final body = await utf8.decoder.bind(request).join();
      final out = request.response..headers.contentType = ContentType.json;
      if (path == '/api/app/v1/login') {
        final creds = jsonDecode(body) as Map;
        out.write(
          jsonEncode(
            creds['password'] == 'right'
                ? {'status': true, 'auth_token': 'tok-1'}
                : {'status': false, 'message': 'Wrong username or password'},
          ),
        );
      } else if (path == '/action/qrcode/') {
        expect(request.headers.value('c-api-key'), isNotEmpty);
        out.write(
          jsonEncode({
            'success': true,
            'result': {
              'code': 'AbC123',
              'url': 'https://30nama.com/auth/AbC123',
            },
          }),
        );
      } else if (path == '/action/qrlogin/code/AbC123') {
        out.write(
          jsonEncode(
            approved
                ? {
                    'success': true,
                    'result': {'usertoken': 'user-tok'},
                  }
                : {'success': false, 'result': null},
          ),
        );
      } else if (path == '/rest/login') {
        expect(request.headers.value('API-KEY'), hasLength(16));
        expect(request.headers.value('Authorization'), startsWith('Basic '));
        final form = Uri.splitQueryString(body);
        out.write(
          jsonEncode(
            form['password'] == 'right'
                ? {'status': 'success', 'user_id': '42', 'email': form['email']}
                : {'status': 'error', 'data': 'Email or password is wrong'},
          ),
        );
      } else {
        out.statusCode = 404;
      }
      await out.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  test(
    'DigiMoviez password sign-in saves the token; wrong password fails',
    () async {
      final file = File('${dir.path}/digi.json');
      final p = DigiMoviezProvider(
        http: ProviderHttp(),
        logger: MemoryLogger(),
        sessionFile: file,
        apiRoot: root.resolve('/api/app/v1'),
      );
      expect(await p.signedIn, isFalse);
      await expectLater(
        p.signIn('me', 'wrong'),
        throwsA(
          isA<ContentSourceFailure>().having(
            (e) => e.message,
            'message',
            'Wrong username or password',
          ),
        ),
      );
      await p.signIn('me', 'right');
      expect(jsonDecode(file.readAsStringSync())['auth_token'], 'tok-1');
      expect(await p.signedIn, isTrue);
      await p.signOut();
      expect(await p.signedIn, isFalse);
      await p.dispose();
    },
  );

  test('30nama QR: code, waiting, then approved saves the session', () async {
    final file = File('${dir.path}/30.json');
    final p = ThirtyNamaProvider(
      http: ProviderHttp(),
      logger: MemoryLogger(),
      sessionFile: file,
      actionUrl: root.resolve('/action'),
    );
    final login = await p.startQrLogin();
    expect(login.code, 'AbC123');
    expect(login.url.toString(), 'https://30nama.com/auth/AbC123');
    expect(await p.pollQrLogin(login.code), isFalse);
    approved = true;
    expect(await p.pollQrLogin(login.code), isTrue);
    expect(jsonDecode(file.readAsStringSync())['access_token'], 'user-tok');
    expect(await p.signedIn, isTrue);
    await p.dispose();
  });

  test(
    'MovieJavan email sign-in saves the user id; wrong password fails',
    () async {
      final file = File('${dir.path}/mj.json');
      final a = MovieJavanAccount(
        http: ProviderHttp(),
        logger: MemoryLogger(),
        sessionFile: file,
        apiRoot: root.resolve('/rest'),
      );
      expect(await a.signedIn, isFalse);
      await expectLater(
        a.signIn('me@x.com', 'wrong'),
        throwsA(
          isA<ContentSourceFailure>().having(
            (e) => e.message,
            'message',
            'Email or password is wrong',
          ),
        ),
      );
      await a.signIn('me@x.com', 'right');
      expect(jsonDecode(file.readAsStringSync())['user_id'], '42');
      expect(await a.signedIn, isTrue);
      await a.signOut();
      expect(await a.signedIn, isFalse);
    },
  );
}
