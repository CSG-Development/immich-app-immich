import 'package:flutter/material.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/models/user.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/widgets/images/remote_image_provider.dart';

Widget userAvatar(BuildContext context, UserDto u, {double? radius}) {
  final serverEndpoint = Store.tryGet(StoreKey.serverEndpoint);
  final url = serverEndpoint != null && serverEndpoint.isNotEmpty
      ? "$serverEndpoint/users/${u.id}/profile-image"
      : null;
  final nameFirstLetter = u.name.isNotEmpty ? u.name[0] : "";
  return CircleAvatar(
    radius: radius,
    backgroundColor: context.primaryColor.withAlpha(50),
    foregroundImage: url != null ? RemoteImageProvider(url: url) : null,
    // silence errors if user has no profile image, use initials as fallback
    onForegroundImageError: (exception, stackTrace) {},
    child: Text(nameFirstLetter.toUpperCase()),
  );
}
