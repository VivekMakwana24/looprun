import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/router.dart';
import 'package:looprun/ui/auth/auth_view_model.dart';

String? r(AuthStatus s, bool accepted, String loc) =>
    appRedirect(status: s, disclosureAccepted: accepted, location: loc);

void main() {
  test('while the session is loading everything goes to the splash screen', () {
    expect(r(AuthStatus.unknown, false, '/home'), splashPath);
    expect(r(AuthStatus.unknown, true, '/run/1'), splashPath);
    expect(r(AuthStatus.unknown, false, splashPath), isNull);
  });

  test('signed out goes to sign-in from anywhere', () {
    expect(r(AuthStatus.signedOut, true, '/home'), signInPath);
    expect(r(AuthStatus.signedOut, false, disclosurePath), signInPath);
    expect(r(AuthStatus.signedOut, false, signInPath), isNull);
  });

  test('signed in without the disclosure accepted goes to the disclosure first', () {
    expect(r(AuthStatus.signedIn, false, '/home'), disclosurePath);
    expect(r(AuthStatus.signedIn, false, '/run/1'), disclosurePath);
    expect(r(AuthStatus.signedIn, false, signInPath), disclosurePath);
    expect(r(AuthStatus.signedIn, false, disclosurePath), isNull);
  });

  test('signed in with the disclosure accepted reaches the app', () {
    expect(r(AuthStatus.signedIn, true, '/home'), isNull);
    expect(r(AuthStatus.signedIn, true, '/run/1'), isNull);
    expect(r(AuthStatus.signedIn, true, signInPath), homePath);
    expect(r(AuthStatus.signedIn, true, disclosurePath), homePath);
    expect(r(AuthStatus.signedIn, true, splashPath), homePath);
  });
}
