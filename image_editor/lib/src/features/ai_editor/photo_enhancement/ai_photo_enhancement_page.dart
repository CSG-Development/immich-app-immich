import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_editor/src/common/utils/async_error_runner.dart';
import 'package:image_editor/src/common/widgets/editor_action_app_bar.dart';
import 'package:image_editor/src/core/interfaces.dart';
import 'package:image_editor/src/core/models/init_configs/ai_editor_init_configs.dart';
import 'package:image_editor/src/core/models/init_configs/ai_enhancement_models.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/ai_enhancement_parameters.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/ai_photo_enhancement_pipeline.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/photo_enhancement_service.dart' as pe;
import 'package:image_editor/src/features/ai_editor/photo_enhancement/portrait_enhancement_service.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/onnx_model_loader.dart';
import 'package:image_editor/src/features/ai_editor/common/models/history_stack.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/model_download_dialog.dart';
import 'package:logging/logging.dart';
import 'package:pro_image_editor/shared/widgets/flat_icon_text_button.dart';

/// Standalone page that exposes photo enhancement effects (portrait enhancement,
/// super resolution, optional relight) on top of the existing AI editor configs.
///
/// The page owns its own `PhotoEnhancementService` instance and returns the
/// final edited bytes via `Navigator.pop(bytes)` when the user taps "Done".
class AiPhotoEnhancementPage extends StatefulWidget {
  const AiPhotoEnhancementPage({super.key, required this.initConfigs, required this.initialImageBytes});

  final AiEditorInitConfigs initConfigs;
  final Uint8List initialImageBytes;

  @override
  State<AiPhotoEnhancementPage> createState() => _AiPhotoEnhancementPageState();
}

class _AiPhotoEnhancementPageState extends State<AiPhotoEnhancementPage> {
  static final Logger _log = Logger('AiPhotoEnhancementPage');
  late final pe.PhotoEnhancementService _service;
  late HistoryStack<Uint8List> _history;
  bool _isProcessing = false;

  // Simple preset + strength wiring for the portrait pipeline-backed effect.
  AiEnhancementParameters _currentParams = AiEnhancementParameters.portrait;
  String _currentPreset = 'Portrait';

  List<ImageEffect> get _effects => _service.effects;
  Uint8List get _currentBytes => _history.current;
  bool get _canUndo => _history.canUndo;
  bool get _canRedo => _history.canRedo;

  @override
  void initState() {
    super.initState();
    _history = HistoryStack<Uint8List>(widget.initialImageBytes);
    _service = pe.PhotoEnhancementService(configs: widget.initConfigs);
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<_SuperResolutionConfigResult?> _showSuperResolutionConfigDialog() {
    return showDialog<_SuperResolutionConfigResult>(
      context: context,
      builder: (context) {
        const options = <int>[1024, 2048, 4096];
        int selected = 1; // default to medium (2048)

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Super resolution settings'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Maximum output size'),
                  const SizedBox(height: 8),
                  Slider(
                    value: selected.toDouble(),
                    min: 0,
                    max: (options.length - 1).toDouble(),
                    divisions: options.length - 1,
                    label: '${options[selected]} px',
                    onChanged: (v) {
                      setState(() {
                        selected = v.round().clamp(0, options.length - 1);
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Higher values produce larger images but may use more memory '
                    'and take longer to process.',
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(_SuperResolutionConfigResult(maxOutputSide: options[selected]));
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<_DenoiseConfigResult?> _showDenoiseConfigDialog() {
    return showDialog<_DenoiseConfigResult>(
      context: context,
      builder: (context) {
        const sizeSteps = <int>[128, 256, 512, 1024];
        const sigmaSteps = <double>[0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4];

        double tSize = 1 / (sizeSteps.length - 1); // 256 default
        double tSigma = 2 / (sigmaSteps.length - 1); // 0.2 default

        int _sizeFromT(double value) {
          final idx = (value * (sizeSteps.length - 1)).round().clamp(0, sizeSteps.length - 1);
          return sizeSteps[idx];
        }

        double _sigmaFromT(double value) {
          final idx = (value * (sigmaSteps.length - 1)).round().clamp(0, sigmaSteps.length - 1);
          return sigmaSteps[idx];
        }

        return StatefulBuilder(
          builder: (context, setState) {
            final currentSigma = _sigmaFromT(tSigma);
            return AlertDialog(
              title: const Text('Denoise settings'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Detail level'),
                  Slider(
                    value: tSize,
                    divisions: sizeSteps.length - 1,
                    onChanged: (v) {
                      setState(() {
                        tSize = v;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text('Lower levels are faster. Higher levels keep more fine detail but may take longer.'),
                  const SizedBox(height: 16),
                  const Text('Denoise strength'),
                  Slider(
                    value: tSigma,
                    divisions: sigmaSteps.length - 1,
                    onChanged: (v) {
                      setState(() {
                        tSigma = v;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text('Higher strength removes more visible noise, but can make the image look smoother.'),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(_DenoiseConfigResult(sigma: currentSigma, modelSize: _sizeFromT(tSize)));
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _ensureModelPermission(ImageEffect effect) async {
    final configs = widget.initConfigs;

    String? modelPathOrUrl;
    String? modelName;

    if (effect is PortraitEnhancementService) {
      modelPathOrUrl = configs.personMattingModelPathEffective;
      modelName = 'Portrait enhancement';
    } else if (effect is pe.SuperResolutionEffect) {
      modelPathOrUrl = configs.realEsrganModelPathEffective;
      modelName = 'Super resolution';
    } else if (effect is pe.ModelZooSuperResolutionEffect) {
      modelPathOrUrl = configs.superResolutionModelPathEffective;
      modelName = 'Super resolution (Model Zoo)';
    } else if (effect is pe.ModnetBackgroundEnhancementEffect) {
      modelPathOrUrl = configs.backgroundModelPathEffective;
      modelName = 'Background (MODNet)';
    } else if (effect is pe.RelightEffect) {
      modelPathOrUrl = configs.fcnSegmentationModelPathEffective;
      modelName = 'Relight';
    } else if (effect is pe.FastdvdnetDenoiseEnhancementEffect) {
      modelPathOrUrl = configs.fastdvdnetModelPathEffective;
      modelName = 'Denoise';
    }

    if (modelPathOrUrl == null || modelName == null || !OnnxModelLoader.isRemoteUrl(modelPathOrUrl)) {
      return true;
    }

    final ok = await showModelDownloadDialog(context, modelPathOrUrl: modelPathOrUrl, modelName: modelName);
    return ok;
  }

  Future<void> _runEffect(ImageEffect effect) async {
    if (_isProcessing || _currentBytes.isEmpty) return;
    AiPhotoEnhancementPipeline? tmpPipeline;
    await runWithBusyAndError<void>(
      context: context,
      state: this,
      setBusy: () => setState(() => _isProcessing = true),
      clearBusy: () => setState(() => _isProcessing = false),
      errorMessageBuilder: (_, __) => 'Failed to apply "${effect.name}". Please try again.',
      onError: (error, stackTrace) => _log.warning('Enhancement effect "${effect.name}" failed', error, stackTrace),
      run: () async {
        final allowed = await _ensureModelPermission(effect);
        if (!allowed) {
          return;
        }

        ImageEffect effective = effect;

        // For super-resolution effects, show a small config dialog to let
        // the user choose output size and then construct a fresh effect
        // instance with those settings.
        if (effect is pe.SuperResolutionEffect || effect is pe.ModelZooSuperResolutionEffect) {
          final config = await _showSuperResolutionConfigDialog();
          if (config == null) return;

          final configs = widget.initConfigs;
          if (effect is pe.SuperResolutionEffect) {
            effective = pe.SuperResolutionEffect(
              modelPathOrUrl: configs.realEsrganModelPathEffective,
              maxOutputSide: config.maxOutputSide,
            );
          } else if (effect is pe.ModelZooSuperResolutionEffect) {
            effective = pe.ModelZooSuperResolutionEffect(
              modelPathOrUrl: configs.superResolutionModelPathEffective,
              maxOutputSide: config.maxOutputSide,
            );
          }
        }

        if (effect is pe.FastdvdnetDenoiseEnhancementEffect) {
          final config = await _showDenoiseConfigDialog();
          if (config == null) return;

          effective = pe.FastdvdnetDenoiseEnhancementEffect(
            modelPathOrUrl: widget.initConfigs.fastdvdnetModelPathEffective,
            noiseSigma: config.sigma,
            modelSize: config.modelSize,
          );
        }

        // If the user selected a preset, rebuild the portrait effect with those
        // parameters so the pipeline actually uses the chosen strengths.
        if (effective is PortraitEnhancementService) {
          tmpPipeline = AiPhotoEnhancementPipeline(
            modelConfig: AiEnhancementModelConfig.fromInitConfigs(widget.initConfigs),
          );
          effective = PortraitEnhancementService(
            personMattingModelPathOrUrl: widget.initConfigs.personMattingModelPathEffective,
            pipeline: tmpPipeline,
            params: _currentParams,
          );
        }

        final result = await effective.apply(_currentBytes);
        if (!mounted) return;
        if (result.isEmpty) {
          // If the effect failed gracefully, keep the previous bytes to avoid
          // surprising the user with a blank image.
          setState(() {});
          return;
        }

        setState(() {
          _history.push(result);
        });
      },
    );
    await tmpPipeline?.dispose();
  }

  void _handleUndo() {
    if (_isProcessing || !_canUndo) return;
    setState(() {
      _history.undo();
    });
  }

  void _handleRedo() {
    if (_isProcessing || !_canRedo) return;
    setState(() {
      _history.redo();
    });
  }

  void _handleClose() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _handleDone() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(_currentBytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.initConfigs.theme;

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: EditorActionAppBar(
          theme: theme,
          title: 'Enhance',
          onBack: _handleClose,
          onUndo: _handleUndo,
          onRedo: _handleRedo,
          onConfirm: _handleDone,
          canUndo: _canUndo,
          canRedo: _canRedo,
          isBusy: _isProcessing,
          confirmTooltip: 'Apply',
        ),
        body: SafeArea(
          child: Stack(
            children: [
              _buildImagePreview(),
              if (_isProcessing)
                Positioned.fill(
                  child: Container(
                    color: Colors.black26,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
              Positioned(left: 0, right: 0, bottom: 0, child: _buildEffectsBar()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: AspectRatio(
          aspectRatio: 1,
          child: FittedBox(
            fit: BoxFit.contain,
            child: _currentBytes.isEmpty ? const SizedBox.shrink() : Image.memory(_currentBytes, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Widget _buildEffectsBar() {
    final theme = Theme.of(context);

    if (_effects.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      color: theme.bottomAppBarTheme.color ?? Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Preset row.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PresetChip(
                label: 'Portrait',
                selected: _currentPreset == 'Portrait',
                onSelected: _isProcessing
                    ? null
                    : () {
                        setState(() {
                          _currentPreset = 'Portrait';
                          _currentParams = AiEnhancementParameters.portrait;
                        });
                      },
              ),
              _PresetChip(
                label: 'Landscape',
                selected: _currentPreset == 'Landscape',
                onSelected: _isProcessing
                    ? null
                    : () {
                        setState(() {
                          _currentPreset = 'Landscape';
                          _currentParams = AiEnhancementParameters.landscape;
                        });
                      },
              ),
              _PresetChip(
                label: 'Night',
                selected: _currentPreset == 'Night',
                onSelected: _isProcessing
                    ? null
                    : () {
                        setState(() {
                          _currentPreset = 'Night';
                          _currentParams = AiEnhancementParameters.night;
                        });
                      },
              ),
              _PresetChip(
                label: 'Neutral',
                selected: _currentPreset == 'Neutral',
                onSelected: _isProcessing
                    ? null
                    : () {
                        setState(() {
                          _currentPreset = 'Neutral';
                          _currentParams = AiEnhancementParameters.neutral;
                        });
                      },
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Effects row (buttons).
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final effect in _effects)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: FlatIconTextButton(
                      label: Text(effect.name, style: const TextStyle(fontSize: 10.0, color: Colors.white)),
                      icon: Icon(effect.icon, size: 22, color: Colors.white),
                      onPressed: _isProcessing ? null : () => _runEffect(effect),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuperResolutionConfigResult {
  const _SuperResolutionConfigResult({required this.maxOutputSide});

  final int maxOutputSide;
}

class _DenoiseConfigResult {
  const _DenoiseConfigResult({required this.sigma, required this.modelSize});

  final double sigma;
  final int modelSize;
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.selected, required this.onSelected});

  final String label;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 10.0)),
        selected: selected,
        onSelected: onSelected == null ? null : (_) => onSelected!(),
      ),
    );
  }
}
