import 'package:cloud_functions/cloud_functions.dart';

import '../models/join_request_model.dart';

/// Parses a joinByInvite Callable result into a [JoinRequest].
/// Pure and unit-testable: throws [StateError] on malformed payloads.
JoinRequest parseJoinInviteResult(Map<String, dynamic> result, String userId) {
  final normalizedUserId = userId.trim();
  final trimmedStatus = (result['status'] as String?)?.trim() ?? '';
  final status = trimmedStatus.isNotEmpty ? trimmedStatus : JoinRequestStatus.pending;
  final request = JoinRequest(
    id: (result['requestId'] as String?)?.trim() ?? '',
    houseId: (result['houseId'] as String?)?.trim() ?? '',
    userId: normalizedUserId,
    status: status,
  );

  if (request.id.isEmpty || request.houseId.isEmpty || normalizedUserId.isEmpty) {
    throw StateError('Could not join this house right now.');
  }
  return request;
}

/// Maps a joinByInvite Callable failure to a user-safe [StateError].
/// Server messages are curated membership states; anything else becomes a
/// generic failure so backend internals never reach the UI.
StateError joinInviteErrorMessage(FirebaseFunctionsException error) {
  switch (error.code) {
    case 'invalid-argument':
      return StateError('Invalid code.');
    case 'already-exists':
      return StateError('A pending request already exists for this house.');
    case 'unauthenticated':
      return StateError('You must be signed in to join a house.');
    case 'deadline-exceeded':
      return StateError('Request timed out. Please check your network and try again.');
    case 'failed-precondition':
      final detail = error.message ?? '';
      return StateError(
        detail.isNotEmpty ? detail : 'Could not join this house right now.',
      );
    default:
      return StateError('Could not join this house right now.');
  }
}
