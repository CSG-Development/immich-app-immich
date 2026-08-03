/// iOS Local Network permission dialog puts the app in `inactive` before the
/// user answers. Showing the Remote Access OTP while that dialog is up renders
/// the modal underneath it and leaves a stuck state if the user then taps Allow.
///
/// [settleDelay] covers the race where discovery/resolve finishes a moment
/// before Flutter delivers the inactive lifecycle event.
const Duration curatorLocalNetPermissionOtpSettleDelay = Duration(milliseconds: 400);

/// Returns true when Remote Access OTP must wait for the next foreground resume
/// (likely because the OS Local Network permission dialog is on screen).
Future<bool> shouldDeferRemoteAccessOtpForLocalNetPermission({
  required bool isIos,
  required bool remoteAuthenticated,
  required bool Function() isAppBlockingUi,
  Duration settleDelay = curatorLocalNetPermissionOtpSettleDelay,
}) async {
  if (!isIos || remoteAuthenticated) {
    return false;
  }
  if (isAppBlockingUi()) {
    return true;
  }
  await Future<void>.delayed(settleDelay);
  return isAppBlockingUi();
}
