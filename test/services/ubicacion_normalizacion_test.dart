import 'package:flutter_test/flutter_test.dart';
import 'package:guia_telefonica/services/local_database_service.dart';

// Acceso al método estático privado via función wrapper (testeando comportamiento)
String? normUbicacion(String? raw) => LocalDatabaseService.normUbicacionTest(raw);

void main() {
  group('LocalDatabaseService.normUbicacion', () {
    test('null retorna null', () {
      expect(normUbicacion(null), isNull);
    });

    test('string vacío retorna null', () {
      expect(normUbicacion(''), isNull);
      expect(normUbicacion('   '), isNull);
    });

    test('MAYÚSCULAS → Title Case (caso real Supabase)', () {
      expect(normUbicacion('CALIMETE'), equals('Calimete'));
      expect(normUbicacion('MADRUGA'), equals('Madruga'));
      expect(normUbicacion('PLAYA'), equals('Playa'));
    });

    test('palabras múltiples en mayúsculas', () {
      expect(normUbicacion('PLAZA DE LA REVOLUCION'), equals('Plaza de la Revolucion'));
      expect(normUbicacion('DIEZ DE OCTUBRE'), equals('Diez de Octubre'));
      expect(normUbicacion('SAN JOSE DE LAS LAJAS'), equals('San Jose de las Lajas'));
    });

    test('ya en Title Case no cambia', () {
      expect(normUbicacion('Matanzas'), equals('Matanzas'));
      expect(normUbicacion('La Habana'), equals('La Habana'));
      expect(normUbicacion('Calimete'), equals('Calimete'));
    });

    test('minúsculas → Title Case', () {
      expect(normUbicacion('matanzas'), equals('Matanzas'));
      expect(normUbicacion('calimete'), equals('Calimete'));
    });

    test('trim de espacios', () {
      expect(normUbicacion('  CALIMETE  '), equals('Calimete'));
    });

    test('primer palabra siempre capitalizada aunque sea preposición', () {
      // Esto no debería pasar con nombres reales de Cuba, pero igual verificar
      expect(normUbicacion('LA HABANA'), equals('La Habana'));
    });
  });
}
