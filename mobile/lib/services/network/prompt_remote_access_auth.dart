import 'package:flutter/material.dart';
import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/widgets/forms/login/remote_code_dialog.dart';
import 'package:logging/logging.dart';

final _log = Logger('PromptRemoteAccessAuth');

Future<bool> promptRemoteAccessAuth({
  required BuildContext context,
  required RemoteProvider remoteProvider,
  required String email,
  bool skipInitialCodeSend = false,
  VoidCallback? onEmailNotAllowed,
}) async {
  if (remoteProvider.isAuthenticated) {
    _log.info('[OTP] promptRemoteAccessAuth skip reason=already_authenticated email=$email');
    return true;
  }

  _log.info('[OTP] promptRemoteAccessAuth start email=$email skipInitialCodeSend=$skipInitialCodeSend');
  var remoteOk = false;
  await showRemoteCodeModal(
    context: context,
    remoteProvider: remoteProvider,
    email: email,
    skipInitialCodeSend: skipInitialCodeSend,
    onEmailNotAllowed: onEmailNotAllowed,
    onSuccess: () async => remoteOk = true,
  );
  _log.info('[OTP] promptRemoteAccessAuth end email=$email success=$remoteOk');
  return remoteOk;
}
