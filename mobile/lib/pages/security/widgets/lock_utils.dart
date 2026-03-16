import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';

bool isLandscapePhone(BuildContext context) =>
    !context.isTablet && MediaQuery.orientationOf(context) == Orientation.landscape;

