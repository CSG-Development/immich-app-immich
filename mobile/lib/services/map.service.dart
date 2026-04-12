import 'package:collection/collection.dart';
import 'package:immich_mobile/mixins/error_logger.mixin.dart';
import 'package:immich_mobile/models/map/map_marker.model.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:logging/logging.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:immich_mobile/utils/user_agent.dart';

class ReverseGeocodeLocation {
  final String? city;
  final String? state;
  final String? country;

  const ReverseGeocodeLocation({this.city, this.state, this.country});
}

class MapService with ErrorLoggerMixin {
  final ApiService _apiService;
  @override
  final logger = Logger("MapService");

  MapService(this._apiService) {
    _setMapUserAgentHeader();
  }

  Future<void> _setMapUserAgentHeader() async {
    final userAgent = await getUserAgentString();
    setHttpHeaders({'User-Agent': userAgent});
  }

  Future<Iterable<MapMarker>> getMapMarkers({
    bool? isFavorite,
    bool? withArchived,
    bool? withPartners,
    DateTime? fileCreatedAfter,
    DateTime? fileCreatedBefore,
  }) async {
    return logError(
      () async {
        final markers = await _apiService.mapApi.getMapMarkers(
          isFavorite: isFavorite,
          isArchived: withArchived,
          withPartners: withPartners,
          fileCreatedAfter: fileCreatedAfter,
          fileCreatedBefore: fileCreatedBefore,
        );

        return markers?.map(MapMarker.fromDto) ?? [];
      },
      defaultValue: [],
      errorMessage: "Failed to get map markers",
    );
  }

  Future<ReverseGeocodeLocation?> reverseGeocode({
    required double latitude,
    required double longitude,
  }) {
    return logError(
      () async {
        final results = await _apiService.mapApi.reverseGeocode(latitude, longitude);
        final location = results?.firstOrNull;
        if (location == null) {
          return null;
        }

        return ReverseGeocodeLocation(
          city: location.city,
          state: location.state,
          country: location.country,
        );
      },
      defaultValue: null,
      errorMessage: "Failed to reverse geocode location",
    );
  }
}
