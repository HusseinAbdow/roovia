import 'package:flutter_test/flutter_test.dart';

import 'package:roovia/main.dart';

void main() {
  group('resolveAuthHome', () {
    test('initializing always shows splash, even with user or error', () {
      expect(
        resolveAuthHome(initializing: true, hasError: false, hasUser: false),
        AuthHome.splash,
      );
      expect(
        resolveAuthHome(initializing: true, hasError: false, hasUser: true),
        AuthHome.splash,
      );
      expect(
        resolveAuthHome(initializing: true, hasError: true, hasUser: false),
        AuthHome.splash,
      );
    });

    test('authenticated user opens main', () {
      expect(
        resolveAuthHome(initializing: false, hasError: false, hasUser: true),
        AuthHome.main,
      );
    });

    test('no user opens login', () {
      expect(
        resolveAuthHome(initializing: false, hasError: false, hasUser: false),
        AuthHome.login,
      );
    });

    test('stream error does not resolve to signed-out', () {
      expect(
        resolveAuthHome(initializing: false, hasError: true, hasUser: false),
        AuthHome.error,
      );
      expect(
        resolveAuthHome(initializing: false, hasError: true, hasUser: true),
        AuthHome.error,
      );
    });
  });

  group('notificationHasDestination', () {
    test('null or empty payload has no destination', () {
      expect(notificationHasDestination(null), isFalse);
      expect(notificationHasDestination({}), isFalse);
      expect(
        notificationHasDestination({'expenseId': '  ', 'houseId': ' '}),
        isFalse,
      );
    });

    test('expense destination wins when present', () {
      expect(
        notificationHasDestination({'expenseId': 'exp-1', 'houseId': ''}),
        isTrue,
      );
      expect(
        notificationHasDestination({'expenseId': '  exp-1  '}),
        isTrue,
      );
    });

    test('house destination routes when expense is absent', () {
      expect(
        notificationHasDestination({'houseId': 'house-1'}),
        isTrue,
      );
    });

    test('unrelated payload does not route to private screens', () {
      expect(
        notificationHasDestination({'type': 'chat', 'title': 'Hi'}),
        isFalse,
      );
    });
  });
}
