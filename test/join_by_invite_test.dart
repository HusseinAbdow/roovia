import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:roovia/models/join_request_model.dart';
import 'package:roovia/services/invite_parsing.dart';

void main() {
  group('parseJoinInviteResult', () {
    test('parses a valid backend response', () {
      final request = parseJoinInviteResult(
        const {
          'requestId': 'req-1',
          'houseId': 'house-1',
          'houseName': 'Sun House',
          'status': 'pending',
        },
        'user-1',
      );

      expect(request.id, 'req-1');
      expect(request.houseId, 'house-1');
      expect(request.userId, 'user-1');
      expect(request.status, JoinRequestStatus.pending);
    });

    test('defaults missing status to pending and trims values', () {
      final request = parseJoinInviteResult(
        const {'requestId': '  req-1 ', 'houseId': 'house-1'},
        '  user-1 ',
      );

      expect(request.id, 'req-1');
      expect(request.status, JoinRequestStatus.pending);
      expect(request.userId, 'user-1');
    });

    test('rejects malformed payloads without leaking details', () {
      expect(
        () => parseJoinInviteResult(const {'houseId': 'house-1'}, 'user-1'),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'Could not join this house right now.'),
        ),
      );
      expect(
        () => parseJoinInviteResult(const {'requestId': 'req-1'}, 'user-1'),
        throwsStateError,
      );
      expect(
        () => parseJoinInviteResult(const {'requestId': 'req-1', 'houseId': 'house-1'}, '  '),
        throwsStateError,
      );
      expect(
        () => parseJoinInviteResult(const <String, dynamic>{}, 'user-1'),
        throwsStateError,
      );
    });
  });

  group('joinInviteErrorMessage', () {
    FirebaseFunctionsException errorFor(String code, [String message = '']) {
      return FirebaseFunctionsException(code: code, message: message);
    }

    test('maps known backend failures to safe messages', () {
      expect(
        joinInviteErrorMessage(errorFor('invalid-argument', 'Invalid code.')).message,
        'Invalid code.',
      );
      expect(
        joinInviteErrorMessage(errorFor('already-exists', 'anything')).message,
        'A pending request already exists for this house.',
      );
      expect(
        joinInviteErrorMessage(errorFor('unauthenticated', 'x')).message,
        'You must be signed in to join a house.',
      );
      expect(
        joinInviteErrorMessage(errorFor('deadline-exceeded', 'x')).message,
        contains('timed out'),
      );
      expect(
        joinInviteErrorMessage(errorFor('failed-precondition', 'House is full.')).message,
        'House is full.',
      );
    });

    test('unknown failures become generic', () {
      expect(
        joinInviteErrorMessage(errorFor('internal', 'stack trace details')).message,
        'Could not join this house right now.',
      );
      expect(
        joinInviteErrorMessage(errorFor('failed-precondition', '')).message,
        'Could not join this house right now.',
      );
    });
  });
}
