import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';

class AlbumItemCount extends StatelessWidget {
  final int count;
  const AlbumItemCount({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const Icon(Icons.photo_library_outlined, size: 20),
          const SizedBox(width: 8),
          Text(
            'items_count'.t(
              context: context,
              args: {'count': count},
            ),
            style: context.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
} 