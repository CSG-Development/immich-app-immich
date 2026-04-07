import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/services/local_exif.service.dart';

final localExifServiceProvider = Provider<LocalExifService>((ref) => LocalExifService());
