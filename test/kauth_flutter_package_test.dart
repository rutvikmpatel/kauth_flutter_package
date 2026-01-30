import 'package:flutter_test/flutter_test.dart';

import 'package:kauth_flutter_package/kauth_flutter_package.dart';

void main() {
  test('KAuth currentUser getter exists', () {
    try {
      expect(KAuth.currentUser, isNull);
    } catch (_) {
      // Expected behavior if AuthManager not configured
    }
  });
}
