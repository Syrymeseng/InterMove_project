import 'package:flutter_test/flutter_test.dart';
import '../lib/auth_service.dart';
void main(){
  test('Connection settings normalize URL and restrict insecure remote transport',(){
    expect(AuthService.validateEndpoint(' https://example.org/api/ '),'https://example.org/api');
    expect(AuthService.validateEndpoint('http://127.0.0.1:8787/'),'http://127.0.0.1:8787');
    for(final url in ['http://192.168.1.2:8787','ftp://example.org','https://user:pass@example.org','https://example.org?key=secret','https://example.org#fragment']){
      expect(()=>AuthService.validateEndpoint(url),throwsFormatException);
    }
  });
  test('Server configuration is used without compile-time define',(){
    final auth=AuthService(null);addTearDown(auth.close);
    auth.configure('https://team.example.org/');
    expect(auth.endpoint,'https://team.example.org');expect(auth.remote,isTrue);
    auth.configure('');expect(auth.remote,isFalse);
  });
}
