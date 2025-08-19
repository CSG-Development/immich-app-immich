import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/upload_profile_image.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/widgets/common/immich_loading_indicator.dart';
import 'package:immich_mobile/widgets/common/user_circle_avatar.dart';

class DrawerProfileInfoBox extends HookConsumerWidget {
  const DrawerProfileInfoBox({
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final uploadProfileImageStatus =
        ref.watch(uploadProfileImageProvider).status;
    final user = ref.watch(currentUserProvider);

    buildUserProfileImage() {
      if (user == null) {
        return const CircleAvatar(
          radius: 20,
          backgroundImage: AssetImage('assets/immich-logo.png'),
          backgroundColor: Colors.transparent,
        );
      }

      final userImage = UserCircleAvatar(
        radius: 32,
        size: 64,
        user: user,
      );

      if (uploadProfileImageStatus == UploadProfileStatus.loading) {
        return const SizedBox(
          height: 60,
          width: 60,
          child: ImmichLoadingIndicator(borderRadius: 30),
        );
      }

      return userImage;
    }

    pickUserProfileImage() async {
      final XFile? image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxHeight: 1024,
        maxWidth: 1024,
      );

      if (image != null) {
        var success =
            await ref.watch(uploadProfileImageProvider.notifier).upload(image);

        if (success) {
          final profileImagePath =
              ref.read(uploadProfileImageProvider).profileImagePath;
          ref.watch(authProvider.notifier).updateUserProfileImagePath(
                profileImagePath,
              );
          if (user != null) {
            ref.read(currentUserProvider.notifier).refresh();
          }
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: pickUserProfileImage,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              buildUserProfileImage(),
              Positioned(
                bottom: -3.2,
                right: -3.2,
                child: Material(
                  color: context.colorScheme.surfaceContainerHighest,
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50.0),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4.8),
                    child: Icon(
                      Icons.camera_alt_outlined,
                      color: context.primaryColor,
                      size: 19.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(
          height: 8.8,
        ),
        Text(
          authState.name,
          style: context.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.textTheme.bodySmall?.color?.withValues(alpha: 0.87),
          ),
        ),
        Text(
          authState.userEmail,
          style: context.textTheme.displayMedium?.copyWith(
            fontWeight: FontWeight.w400,
            color: context.textTheme.bodySmall?.color?.withValues(alpha: 0.87),
          ),
        ),
      ],
    );
  }
}
