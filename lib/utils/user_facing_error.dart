import '../repositories/live_data_access.dart';

class UserFacingError {
  const UserFacingError._();

  static String message(
    Object error, {
    String fallback = 'Something went wrong. Please try again.',
  }) {
    if (error is LiveOperationUnavailable) return error.message;
    final value = error.toString().toLowerCase();
    if (value.contains('access was activated, but sign-in')) {
      return 'Your account was activated. Return to Sign In and use your new username and password.';
    }
    if (value.contains('matching child record already exists')) {
      return 'A matching child record already exists. Review that record before linking or registering another child.';
    }
    if (value.contains('already been reviewed')) {
      return 'This request has already been reviewed. Refresh the list.';
    }
    if (value.contains('pending request already exists')) {
      return 'A request for this child is already awaiting review.';
    }
    if (value.contains('guardian sex')) {
      return 'Choose a relationship that matches the guardian’s sex.';
    }
    if (value.contains('correction reason')) {
      return 'Enter a reason for this correction.';
    }
    if (value.contains('rejection reason') ||
        value.contains('review decision')) {
      return 'Enter a reason for rejecting this request.';
    }
    if (value.contains('birth date cannot be after a recorded vaccination')) {
      return 'The birth date must not be after a recorded vaccination.';
    }
    if (value.contains('guardian access is already linked')) {
      return 'This guardian already has online access.';
    }
    if (value.contains('activation could not be confirmed')) {
      return 'Activation could not be confirmed. Try signing in before activating again.';
    }
    if (value.contains('activation code') ||
        value.contains('invitation is no longer')) {
      return 'The activation code is invalid or no longer available. Ask the health center for a new code.';
    }
    if (value.contains('username must contain')) {
      return 'Username must contain 4 to 40 letters, numbers, dots, underscores, or hyphens.';
    }
    if (value.contains('password must contain')) {
      return 'Use a password containing 8 to 128 characters.';
    }
    if (value.contains('exceeds the available stock') ||
        value.contains('insufficient usable stock')) {
      return 'The quantity is greater than the available usable stock.';
    }
    if (value.contains('sms reminders are disabled')) {
      return 'SMS reminders are disabled for one or more selected guardians.';
    }
    if (value.contains('valid philippine mobile number')) {
      return 'A selected guardian does not have a valid Philippine mobile number.';
    }
    if (value.contains('already sent or started within the last 10 minutes')) {
      return 'A selected reminder was already sent or started recently. Check follow-up history before retrying.';
    }
    if (value.contains('send at most 20 sms')) {
      return 'Select at most 20 reminders for each SMS batch.';
    }
    if (value.contains('sms request') &&
        (value.contains('failed') || value.contains('uncertain'))) {
      return error.toString().replaceFirst('Bad state: ', '');
    }
    if (value.contains('sms delivery is not configured')) {
      return 'SMS delivery is not configured on the server.';
    }
    if (value.contains('username is already') ||
        value.contains('username already')) {
      return 'That username is already in use. Choose another username.';
    }
    if (value.contains('network') ||
        value.contains('socket') ||
        value.contains('connection')) {
      return 'Unable to connect. Check your internet connection and try again.';
    }
    if (value.contains('permission') ||
        value.contains('row-level security') ||
        value.contains('not authorized')) {
      return 'You do not have permission to complete this action.';
    }
    if (value.contains('not found')) {
      return 'The requested record could not be found.';
    }
    if (value.contains('already been recorded') ||
        value.contains('duplicate')) {
      return 'This record has already been saved.';
    }
    if (value.contains('signed-in user is required')) {
      return 'Your session has expired. Sign in again to continue.';
    }
    return fallback;
  }
}
