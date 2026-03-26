import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/common/utils/async_error_runner.dart';
import 'package:image_editor/src/common/widgets/editor_action_app_bar.dart';
import 'package:image_editor/src/core/interfaces.dart';
import 'package:image_editor/src/core/models/init_configs/ai_editor_init_configs.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/photo_enhancement_service.dart' as pe;
import 'package:image_editor/src/features/ai_editor/common/utils/layout_utils.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/onnx_model_loader.dart';
import 'package:image_editor/src/features/ai_editor/common/models/history_stack.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/ai_modal_ui.dart';
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
  late final Size _sourceImageSize;

  List<ImageEffect> get _effects => _service.effects;
  Uint8List get _currentBytes => _history.current;
  bool get _canUndo => _history.canUndo;
  bool get _canRedo => _history.canRedo;

  @override
  void initState() {
    super.initState();
    _history = HistoryStack<Uint8List>(widget.initialImageBytes);
    final decoded = img.decodeImage(widget.initialImageBytes);
    _sourceImageSize = decoded != null
        ? Size(decoded.width.toDouble(), decoded.height.toDouble())
        : const Size(1, 1);
    _service = pe.PhotoEnhancementService(
      configs: widget.initConfigs,
    );
  }

  int? _fixedInputSizeForSuperResolutionModel([String? modelPathOrUrl]) {
    final path = (modelPathOrUrl ?? widget.initConfigs.realEsrganX2ModelPathEffective).toLowerCase();
    if (path.contains('x4-256') || path.endsWith('realesrgan-x4-256.onnx')) {
      return 256;
    }
    if (path.endsWith('realesrgan-x4.onnx')) {
      return 64;
    }
    return null;
  }

  @override
  void dispose() {
    // Dispose model sessions asynchronously on page teardown.
    unawaited(_service.dispose());
    _clearImageCaches();
    super.dispose();
  }

  Future<_SuperResolutionConfigResult?> _showSuperResolutionConfigDialog() {
    return showDialog<_SuperResolutionConfigResult>(
      context: context,
      builder: (context) {
        final modelOptions = <_SrModelOption>[
          _SrModelOption(
            label: 'Default (configured)',
            modelPathOrUrl: widget.initConfigs.realEsrganX2ModelPathEffective,
          ),
          const _SrModelOption(
            label: 'RealESRGAN x4 (dynamic)',
            modelPathOrUrl:
                'https://huggingface.co/AXERA-TECH/Real-ESRGAN/resolve/main/onnx/realesrgan-x4.onnx',
          ),
        ];
        var selectedModelPath = modelOptions.first.modelPathOrUrl;
        final outputOptions = List<int>.generate(13, (i) => 512 + i * 128);
        const dynamicInputOptions = <int>[128, 256, 384, 512];
        int selectedOutput = 4; // default to balanced (1024)
        int selectedInput = _fixedInputSizeForSuperResolutionModel(selectedModelPath) != null ? 0 : 1;
        bool useFixedSquareInput = true;
        var useArtifactPostprocess = false;
        var modelReady = false;
        var isCheckingModel = true;
        const contentTextStyle = AiModalUi.contentStyle;
        const noteTextStyle = AiModalUi.noteStyle;
        final srcW = _sourceImageSize.width;
        final srcH = _sourceImageSize.height;
        final srcLongestSide = srcW > srcH ? srcW : srcH;
        final srcMegaPixels = (srcW * srcH) / 1000000.0;
        final srcBytesMb = widget.initialImageBytes.length / (1024.0 * 1024.0);

        String? _buildRiskWarning({
          required int maxOutputSide,
          required int workingInput,
          required bool fixedSquareInput,
        }) {
          final aggressiveOutput = maxOutputSide >= 1536;
          final veryAggressiveOutput = maxOutputSide >= 2048;
          final largeSource = srcMegaPixels >= 3.5 || srcLongestSide >= 1800;
          final veryLargeSource = srcMegaPixels >= 5.0 || srcLongestSide >= 2400;
          final heavyFile = srcBytesMb >= 4.0;
          final tinyWorkingInput = workingInput <= 128;
          final hugeGap = srcLongestSide > 0 && (maxOutputSide / srcLongestSide) >= 1.2;
          if (!largeSource && !heavyFile && !aggressiveOutput) return null;

          final b = StringBuffer();
          if (largeSource || heavyFile) {
            b.write(
              'Warning: source image is already high resolution '
              '(${srcW.toInt()}x${srcH.toInt()}, ${srcMegaPixels.toStringAsFixed(2)} MP, '
              '${srcBytesMb.toStringAsFixed(1)} MB). ',
            );
            b.write(
              'Super resolution is primarily intended for low/medium quality images. '
              'On large images it may increase RAM/CPU pressure and can cause instability '
              '(freeze, restart, or process kill).',
            );
            if (aggressiveOutput) {
              b.write(' Current output ${maxOutputSide}px increases this risk.');
            }
            b.write(' Prefer lower output size or disable artifact postprocess.');
          } else {
            b.write(
              'Warning: high output size (${maxOutputSide}px) may cause high RAM/CPU pressure '
              'and unstable behavior on some devices.',
            );
          }

          if (veryAggressiveOutput || veryLargeSource || heavyFile) {
            b.write(' Recommended safer output: 1024 or 1536.');
          }
          if (!fixedSquareInput && tinyWorkingInput && hugeGap) {
            b.write(' Avoid very low working input for more stable results.');
          }
          return b.toString();
        }

        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> refreshModelReady() async {
              setState(() {
                isCheckingModel = true;
              });
              final ready = await OnnxModelLoader.isLocallyAvailable(selectedModelPath);
              if (!context.mounted) return;
              setState(() {
                modelReady = ready;
                isCheckingModel = false;
              });
            }

            if (isCheckingModel) {
              Future<void>.microtask(refreshModelReady);
            }

            final fixedInputSize = _fixedInputSizeForSuperResolutionModel(selectedModelPath);
            final fixedShapeModel = fixedInputSize != null;
            final currentInputOptions = fixedShapeModel
                ? <int>[fixedInputSize]
                : dynamicInputOptions;
            if (selectedInput >= currentInputOptions.length) {
              selectedInput = currentInputOptions.length - 1;
            }
            final selectedOutputSide = outputOptions[selectedOutput];
            final workingInputSize = currentInputOptions[selectedInput];
            final riskWarning = _buildRiskWarning(
              maxOutputSide: selectedOutputSide,
              workingInput: workingInputSize,
              fixedSquareInput: useFixedSquareInput,
            );

            return AlertDialog(
              title: const Text('Super resolution settings'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedModelPath,
                    style: AiModalUi.selectorValueStyle,
                    decoration: AiModalUi.selectDecoration('SR model'),
                    items: modelOptions
                        .map(
                          (option) => DropdownMenuItem<String>(
                            value: option.modelPathOrUrl,
                            child: Text(option.label, style: AiModalUi.selectorValueStyle),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        selectedModelPath = value;
                        selectedInput = 0;
                        useFixedSquareInput = true;
                        isCheckingModel = true;
                      });
                    },
                  ),
                  if (_fixedInputSizeForSuperResolutionModel(selectedModelPath) case final fixed?)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'This model uses fixed ${fixed}x$fixed input.',
                        style: noteTextStyle,
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (isCheckingModel)
                    const Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Checking model availability...', style: noteTextStyle),
                      ],
                    )
                  else if (modelReady)
                    const Text('Model ready on this device.', style: noteTextStyle)
                  else
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Selected model is not downloaded yet.',
                            style: noteTextStyle,
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final ok = await showModelDownloadDialog(
                              context,
                              modelPathOrUrl: selectedModelPath,
                              modelName: 'Super resolution',
                            );
                            if (!context.mounted) return;
                            if (ok) {
                              setState(() {
                                isCheckingModel = true;
                              });
                            }
                          },
                          child: const Text('Download'),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  if (riskWarning != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.45)),
                      ),
                      child: Text(
                        riskWarning,
                        style: AiModalUi.noteStyle,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const Text('Maximum output size', style: AiModalUi.sectionTitleStyle),
                  const SizedBox(height: 8),
                  Slider(
                    value: selectedOutput.toDouble(),
                    min: 0,
                    max: (outputOptions.length - 1).toDouble(),
                    divisions: outputOptions.length - 1,
                    label: '${outputOptions[selectedOutput]} px',
                    onChanged: (v) {
                      setState(() {
                        selectedOutput = v.round().clamp(0, outputOptions.length - 1);
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Higher values produce larger images but use significantly more memory '
                    'and can become unstable on large source photos.',
                    style: noteTextStyle,
                  ),
                  if (!fixedShapeModel) ...[
                    const SizedBox(height: 16),
                    const Text('Working input size', style: AiModalUi.sectionTitleStyle),
                    const SizedBox(height: 8),
                    Slider(
                      value: selectedInput.toDouble(),
                      min: 0,
                      max: (currentInputOptions.length - 1).toDouble(),
                      divisions:
                          currentInputOptions.length > 1 ? currentInputOptions.length - 1 : null,
                      label: '${currentInputOptions[selectedInput]} px',
                      onChanged: (v) {
                        setState(() {
                          selectedInput = v.round().clamp(0, currentInputOptions.length - 1);
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Higher values can keep more detail, but increase RAM usage and latency.',
                      style: noteTextStyle,
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Use fixed square input', style: contentTextStyle),
                      subtitle: const Text(
                        'Keeps model input square. Turn off to keep original aspect ratio.',
                        style: noteTextStyle,
                      ),
                      value: useFixedSquareInput,
                      onChanged: (value) {
                        setState(() {
                          useFixedSquareInput = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Artifact removal postprocess', style: contentTextStyle),
                    subtitle: const Text('Use extra artifact cleanup after enhancement.', style: noteTextStyle),
                    value: useArtifactPostprocess,
                    onChanged: (value) {
                      setState(() {
                        useArtifactPostprocess = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')),
                TextButton(
                  onPressed: (!modelReady || isCheckingModel)
                      ? null
                      : () {
                          final workingInputSize = currentInputOptions[selectedInput];
                          Navigator.of(context).pop(
                            _SuperResolutionConfigResult(
                              modelPathOrUrl: selectedModelPath,
                              maxOutputSide: outputOptions[selectedOutput],
                              maxInputSide: workingInputSize,
                              fixedInputSize: useFixedSquareInput ? workingInputSize : null,
                              enableArtifactPostprocess: useArtifactPostprocess,
                            ),
                          );
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
        var useArtifactPostprocess = true;

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
                  const Text('Detail level', style: AiModalUi.sectionTitleStyle),
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
                  const Text(
                    'Lower levels are faster. Higher levels keep more fine detail but may take longer.',
                    style: AiModalUi.noteStyle,
                  ),
                  const SizedBox(height: 16),
                  const Text('Denoise strength', style: AiModalUi.sectionTitleStyle),
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
                  const Text(
                    'Higher strength removes more visible noise, but can make the image look smoother.',
                    style: AiModalUi.noteStyle,
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Artifact removal postprocess', style: AiModalUi.contentStyle),
                    subtitle: const Text(
                      'Use an extra cleanup pass after denoise. Turn off to keep more native detail.',
                      style: AiModalUi.noteStyle,
                    ),
                    value: useArtifactPostprocess,
                    onChanged: (value) {
                      setState(() {
                        useArtifactPostprocess = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      _DenoiseConfigResult(
                        sigma: currentSigma,
                        modelSize: _sizeFromT(tSize),
                        enableArtifactPostprocess: useArtifactPostprocess,
                      ),
                    );
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

  Future<_RelightConfigResult?> _showRelightConfigDialog() {
    return showDialog<_RelightConfigResult>(
      context: context,
      builder: (context) {
        var selectedPreset = _RelightPreset.balanced;
        double strength = widget.initConfigs.relightStrength.clamp(-0.4, 1.0);
        double gamma = widget.initConfigs.relightMaskGamma.clamp(0.25, 2.5);
        double blur = widget.initConfigs.relightMaskBlurRadius.clamp(0.0, 10.0);
        var useArtifactPostprocess = false;

        void applyPreset(_RelightPreset preset) {
          switch (preset) {
            case _RelightPreset.subtle:
              strength = 0.16;
              gamma = 1.2;
              blur = 1.0;
              break;
            case _RelightPreset.natural:
              strength = 0.2;
              gamma = 1.1;
              blur = 1.2;
              break;
            case _RelightPreset.balanced:
              strength = 0.25;
              gamma = 1.0;
              blur = 1.5;
              break;
            case _RelightPreset.studio:
              strength = 0.32;
              gamma = 1.3;
              blur = 1.8;
              break;
            case _RelightPreset.portraitPop:
              strength = 0.34;
              gamma = 1.25;
              blur = 2.0;
              break;
            case _RelightPreset.softGlow:
              strength = 0.22;
              gamma = 0.85;
              blur = 3.0;
              break;
            case _RelightPreset.strong:
              strength = 0.42;
              gamma = 1.35;
              blur = 2.0;
              break;
            case _RelightPreset.dramatic:
              strength = 0.52;
              gamma = 1.6;
              blur = 1.4;
              break;
            case _RelightPreset.goldenHour:
              strength = 0.28;
              gamma = 0.9;
              blur = 3.2;
              break;
            case _RelightPreset.blueHour:
              strength = 0.18;
              gamma = 1.05;
              blur = 3.6;
              break;
            case _RelightPreset.backlitFix:
              strength = 0.46;
              gamma = 0.82;
              blur = 2.6;
              break;
            case _RelightPreset.flatSceneBoost:
              strength = 0.38;
              gamma = 1.45;
              blur = 1.2;
              break;
          }
        }

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Relight settings'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Preset', style: AiModalUi.sectionTitleStyle),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<_RelightPreset>(
                    value: selectedPreset,
                    style: AiModalUi.selectorValueStyle,
                    decoration: AiModalUi.selectDecoration('Lighting preset'),
                    items: _RelightPreset.values
                        .map(
                          (preset) => DropdownMenuItem<_RelightPreset>(
                            value: preset,
                            child: Text(preset.label, style: AiModalUi.selectorValueStyle),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        selectedPreset = value;
                        applyPreset(value);
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Text('Strength (${strength.toStringAsFixed(2)})', style: AiModalUi.sectionTitleStyle),
                  Slider(
                    value: strength,
                    min: -0.4,
                    max: 1.0,
                    divisions: 28,
                    onChanged: (v) {
                      setState(() {
                        strength = v;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Text('Mask focus (${gamma.toStringAsFixed(2)})', style: AiModalUi.sectionTitleStyle),
                  Slider(
                    value: gamma,
                    min: 0.25,
                    max: 2.5,
                    divisions: 45,
                    onChanged: (v) {
                      setState(() {
                        gamma = v;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Text('Mask smoothness (${blur.toStringAsFixed(1)})', style: AiModalUi.sectionTitleStyle),
                  Slider(
                    value: blur,
                    min: 0.0,
                    max: 10.0,
                    divisions: 20,
                    onChanged: (v) {
                      setState(() {
                        blur = v;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Artifact removal postprocess', style: AiModalUi.contentStyle),
                    subtitle: const Text(
                      'Use extra artifact cleanup after relight.',
                      style: AiModalUi.noteStyle,
                    ),
                    value: useArtifactPostprocess,
                    onChanged: (value) {
                      setState(() {
                        useArtifactPostprocess = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    _RelightConfigResult(
                      preset: selectedPreset,
                      strength: strength,
                      maskGamma: gamma,
                      maskBlurRadius: blur,
                      enableArtifactPostprocess: useArtifactPostprocess,
                    ),
                  ),
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

    if (effect is pe.SuperResolutionEffect) {
      modelPathOrUrl = effect.modelPathOrUrl;
      modelName = 'Super resolution';
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

    if (modelPathOrUrl == null || modelName == null) {
      return true;
    }

    final ok = await showModelDownloadDialog(context, modelPathOrUrl: modelPathOrUrl, modelName: modelName);
    if (!ok) return false;

    if (configs.artifactRemovalEnabled) {
      final artifactOk = await showModelDownloadDialog(
        context,
        modelPathOrUrl: configs.inpaintingModelPathEffective,
        modelName: 'Artifact cleanup',
      );
      if (!artifactOk) return false;
    }

    return true;
  }

  Future<void> _runEffect(ImageEffect effect) async {
    if (_isProcessing || _currentBytes.isEmpty) return;
    await runWithBusyAndError<void>(
      context: context,
      state: this,
      setBusy: () => setState(() => _isProcessing = true),
      clearBusy: () => setState(() => _isProcessing = false),
      errorMessageBuilder: (_, __) => 'Failed to apply "${effect.name}". Please try again.',
      onError: (error, stackTrace) => _log.warning('Enhancement effect "${effect.name}" failed', error, stackTrace),
      run: () async {
        ImageEffect effective = effect;
        var createdTemporaryEffect = false;

        // For super-resolution effects, show a small config dialog to let
        // the user choose output size and then construct a fresh effect
        // instance with those settings.
        if (effect is pe.SuperResolutionEffect) {
          final config = await _showSuperResolutionConfigDialog();
          if (config == null) return;

          effective = _service.createSuperResolutionEffect(
            modelPathOrUrl: config.modelPathOrUrl,
            maxOutputSide: config.maxOutputSide,
            maxInputSide: _fixedInputSizeForSuperResolutionModel(config.modelPathOrUrl) ??
                config.maxInputSide,
            fixedInputSize: _fixedInputSizeForSuperResolutionModel(config.modelPathOrUrl) ??
                config.fixedInputSize,
            enableArtifactPostprocess: config.enableArtifactPostprocess,
          );
          createdTemporaryEffect = true;
        }
        final allowed = await _ensureModelPermission(effective);
        if (!allowed) {
          return;
        }

        if (effect is pe.FastdvdnetDenoiseEnhancementEffect) {
          final config = await _showDenoiseConfigDialog();
          if (config == null) return;

          effective = _service.createDenoiseEffect(
            modelPathOrUrl: widget.initConfigs.fastdvdnetModelPathEffective,
            noiseSigma: config.sigma,
            modelSize: config.modelSize,
            enableArtifactPostprocess: config.enableArtifactPostprocess,
          );
          createdTemporaryEffect = true;
        }

        if (effect is pe.RelightEffect) {
          final config = await _showRelightConfigDialog();
          if (config == null) return;
          effective = _service.createRelightEffect(
            fcnModelPathOrUrl: widget.initConfigs.fcnSegmentationModelPathEffective,
            strength: config.strength,
            maskGamma: config.maskGamma,
            maskBlurRadius: config.maskBlurRadius,
            enableArtifactPostprocess: config.enableArtifactPostprocess,
          );
          createdTemporaryEffect = true;
        }

        try {
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
          _clearImageCaches();
        } finally {
          if (createdTemporaryEffect) {
            if (effective case pe.SuperResolutionEffect()) {
              await effective.dispose();
            } else if (effective case pe.FastdvdnetDenoiseEnhancementEffect()) {
              await effective.dispose();
            } else if (effective case pe.RelightEffect()) {
              await effective.dispose();
            }
          }
        }
      },
    );
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
    _clearImageCaches();
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _handleDone() {
    _clearImageCaches();
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(_currentBytes);
    }
  }

  void _clearImageCaches() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final displaySize = fitSizeWithinBounds(
            _sourceImageSize,
            Size(constraints.maxWidth, constraints.maxHeight),
          );
          final cacheWidth = (displaySize.width * MediaQuery.devicePixelRatioOf(context)).round();
          final cacheHeight = (displaySize.height * MediaQuery.devicePixelRatioOf(context)).round();
          return Center(
            child: SizedBox(
              width: displaySize.width,
              height: displaySize.height,
              child: _currentBytes.isEmpty
                  ? const SizedBox.shrink()
                  : Image.memory(
                      _currentBytes,
                      fit: BoxFit.cover,
                      cacheWidth: cacheWidth,
                      cacheHeight: cacheHeight,
                    ),
            ),
          );
        },
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
      child: SingleChildScrollView(
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
    );
  }
}

class _SuperResolutionConfigResult {
  const _SuperResolutionConfigResult({
    required this.modelPathOrUrl,
    required this.maxOutputSide,
    required this.maxInputSide,
    required this.fixedInputSize,
    required this.enableArtifactPostprocess,
  });

  final String modelPathOrUrl;
  final int maxOutputSide;
  final int maxInputSide;
  final int? fixedInputSize;
  final bool enableArtifactPostprocess;
}

class _SrModelOption {
  const _SrModelOption({
    required this.label,
    required this.modelPathOrUrl,
  });

  final String label;
  final String modelPathOrUrl;
}

class _DenoiseConfigResult {
  const _DenoiseConfigResult({
    required this.sigma,
    required this.modelSize,
    required this.enableArtifactPostprocess,
  });

  final double sigma;
  final int modelSize;
  final bool enableArtifactPostprocess;
}

enum _RelightPreset {
  subtle('Subtle'),
  natural('Natural light'),
  balanced('Balanced'),
  studio('Studio light'),
  portraitPop('Portrait pop'),
  softGlow('Soft glow'),
  strong('Strong'),
  dramatic('Dramatic'),
  goldenHour('Golden hour'),
  blueHour('Blue hour'),
  backlitFix('Backlit fix'),
  flatSceneBoost('Flat scene boost');

  const _RelightPreset(this.label);
  final String label;
}

class _RelightConfigResult {
  const _RelightConfigResult({
    required this.preset,
    required this.strength,
    required this.maskGamma,
    required this.maskBlurRadius,
    required this.enableArtifactPostprocess,
  });

  final _RelightPreset preset;
  final double strength;
  final double maskGamma;
  final double maskBlurRadius;
  final bool enableArtifactPostprocess;
}

