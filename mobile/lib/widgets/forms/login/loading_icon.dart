import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:immich_mobile/constants/colors.dart';

class LoadingIcon extends StatefulWidget {
  final String? text;
  const LoadingIcon({super.key, this.text});

  @override
  State<LoadingIcon> createState() => _LoadingIconState();
}

class _LoadingIconState extends State<LoadingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  static const _brandStroke = '#1976D2';
  static const _trackStroke = '#E0E0E0';
  String? _svgTemplate;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _loadSvg();
  }

  Future<void> _loadSvg() async {
    final svg = await rootBundle.loadString('assets/circular-progress-indicator.svg');
    if (!mounted) return;
    setState(() => _svgTemplate = svg);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _toHex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // SG dark: small = sgBrandColorDark (#8CD873), big = greyBorderDark (#616161).
    // Light: keep SVG track (#E0E0E0) and brand stroke via sgBrandColorLight.
    final indicatorColor = isDark ? sgBrandColorDark : sgBrandColorLight;
    final trackColor = isDark ? greyBorderDark : null;

    var svg = _svgTemplate?.replaceAll(_brandStroke, _toHex(indicatorColor));
    if (trackColor != null && svg != null) {
      svg = svg.replaceAll(_trackStroke, _toHex(trackColor));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Column(
        children: [
          FittedBox(
            child: RotationTransition(
              turns: _controller,
              child: svg == null
                  ? SizedBox(
                      height: 48,
                      width: 48,
                      child: CircularProgressIndicator(
                        color: indicatorColor,
                        backgroundColor: trackColor,
                      ),
                    )
                  : SvgPicture.string(
                      svg,
                      height: 48,
                    ),
            ),
          ),
          if (widget.text != null) ...[
            const SizedBox(height: 16.0),
            Text(widget.text!, style: const TextStyle()),
          ],
        ],
      ),
    );
  }
}
