// Central export for global services.
// Prefer `core/services` implementations when available.

export 'package:taxi_app/core/services/notificacion_servicio.dart';
export 'package:taxi_app/core/services/tracking_service.dart';
export 'package:taxi_app/core/services/background_tracking_service.dart';
export 'package:taxi_app/core/services/auth_service.dart';

// Fallback exports (still located under lib/services until migrated)
export 'package:taxi_app/core/services/google_sign_in_service.dart';
export 'package:taxi_app/core/services/firebase_service.dart';
export 'package:taxi_app/core/services/solicitud_firestore_datasource.dart';
// chat and map shims intentionally not exported here to avoid symbol duplication
// with feature-local service implementations while migration is in progress.
export 'package:taxi_app/core/services/route_cache_service.dart';
export 'package:taxi_app/core/services/notification_service.dart';
export 'package:taxi_app/core/services/ride_service.dart';
