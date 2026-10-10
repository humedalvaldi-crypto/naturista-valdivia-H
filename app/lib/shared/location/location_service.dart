import 'package:geolocator/geolocator.dart';

/// Posición obtenida del GPS (o de la ubicación del navegador en la web).
class GeoFix {
  const GeoFix({required this.latitude, required this.longitude, this.accuracyM});

  final double latitude;
  final double longitude;
  final double? accuracyM;
}

enum LocationProblem { serviceDisabled, denied, deniedForever, unavailable }

class LocationException implements Exception {
  const LocationException(this.problem);

  final LocationProblem problem;

  @override
  String toString() => 'LocationException($problem)';
}

/// Ubicación actual. `current` se puede reemplazar en pruebas.
abstract final class LocationService {
  static Future<GeoFix> Function() current = _fromDevice;

  static Future<GeoFix> _fromDevice() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(LocationProblem.serviceDisabled);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) throw const LocationException(LocationProblem.denied);
    if (permission == LocationPermission.deniedForever) throw const LocationException(LocationProblem.deniedForever);
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      return GeoFix(latitude: p.latitude, longitude: p.longitude, accuracyM: p.accuracy);
    } catch (_) {
      throw const LocationException(LocationProblem.unavailable);
    }
  }
}
