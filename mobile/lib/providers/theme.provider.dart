import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/colors.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/theme/color_scheme.dart';
import 'package:immich_mobile/theme/dynamic_theme.dart';
import 'package:immich_mobile/theme/theme_data.dart';

final immichThemeProvider = StateProvider<ImmichTheme>((ref) {
  // Mode does not affect ImmichTheme contents — watch only the fields that do.
  final themeConfig = ref.watch(
    appConfigProvider.select(
      (config) => (
        primaryColor: config.theme.primaryColor,
        dynamicTheme: config.theme.dynamicTheme,
        colorfulInterface: config.theme.colorfulInterface,
      ),
    ),
  );

  final ImmichTheme? dynamicTheme = DynamicTheme.theme;
  final useDynamicThemeForPreset = themeConfig.primaryColor != ImmichColorPreset.sg;
  final currentTheme = (themeConfig.dynamicTheme && useDynamicThemeForPreset && dynamicTheme != null)
      ? dynamicTheme
      : themeConfig.primaryColor.themeOfPreset;

  return themeConfig.colorfulInterface ? currentTheme : decolorizeSurfaces(theme: currentTheme);
});
