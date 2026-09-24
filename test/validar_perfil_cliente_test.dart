import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/validar_perfil_cliente.dart';

PerfilFormulario f({
  String nombre = 'Laura',
  String apellido = 'Gómez',
  String telefono = '3001234567',
  bool tieneFoto = true,
}) => PerfilFormulario(
  nombre: nombre,
  apellido: apellido,
  telefono: telefono,
  tieneFoto: tieneFoto,
);

void main() {
  test('formulario completo no tiene errores', () {
    expect(validarPerfilCliente(f()), isEmpty);
    expect(mensajeResumenPerfil(validarPerfilCliente(f())), isNull);
  });

  test('todo vacío: lista lo que falta en orden de pantalla', () {
    final e = validarPerfilCliente(
      f(nombre: ' ', apellido: '', telefono: '', tieneFoto: false),
    );
    expect(e.keys, containsAll(CampoPerfil.values));
    expect(
      mensajeResumenPerfil(e),
      'Falta completar tu foto de perfil, tu nombre, tu apellido y tu '
      'teléfono para poder registrarte.',
    );
  });

  test('falta un campo y otro es inválido', () {
    final e = validarPerfilCliente(f(nombre: '', telefono: '300123'));
    expect(e[CampoPerfil.nombre]!.vacio, isTrue);
    expect(e[CampoPerfil.telefono]!.vacio, isFalse);
    expect(e[CampoPerfil.telefono]!.mensaje, contains('faltan 4'));
    expect(
      mensajeResumenPerfil(e),
      'Falta completar tu nombre y revisa tu teléfono para poder registrarte.',
    );
  });

  test('solo inválidos empieza con "Revisa"', () {
    final e = validarPerfilCliente(f(apellido: 'G0mez'));
    expect(
      mensajeResumenPerfil(e),
      'Revisa tu apellido para poder registrarte.',
    );
  });

  test('nombre de una letra es muy corto; acentos y ñ son válidos', () {
    expect(validarPerfilCliente(f(nombre: 'A'))[CampoPerfil.nombre], isNotNull);
    expect(validarPerfilCliente(f(nombre: 'Íñigo José')), isEmpty);
  });

  test('normaliza el teléfono a los últimos 10 dígitos', () {
    expect(normalizarTelefono10('+57 300-123-4567'), '3001234567');
    expect(validarPerfilCliente(f(telefono: '+57 300 123 4567')), isEmpty);
  });
}
