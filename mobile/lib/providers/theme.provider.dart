import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/colors.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/theme/color_scheme.dart';
import 'package:immich_mobile/theme/dynamic_theme.dart';
import 'package:immich_mobile/theme/theme_data.dart';

final immichThemeProvider = StateProvider<ImmichTheme>((ref) {
  final themeConfig = ref.watch(appConfigProvider.select((config) => config.theme));

  final ImmichTheme? dynamicTheme = DynamicTheme.theme;
  final useDynamicThemeForPreset = themeConfig.primaryColor != ImmichColorPreset.sg;
  final currentTheme = (themeConfig.dynamicTheme && useDynamicThemeForPreset && dynamicTheme != null)
      ? dynamicTheme
      : themeConfig.primaryColor.themeOfPreset;

  return themeConfig.colorfulInterface ? currentTheme : decolorizeSurfaces(theme: currentTheme);
});
