import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/client_user_entity.dart';

enum AuthFlowDestination { completeProfile, clientHome }

class AuthFlowResult {
  const AuthFlowResult({required this.destination, required this.user});

  final AuthFlowDestination destination;
  final ClientUserEntity user;
}
