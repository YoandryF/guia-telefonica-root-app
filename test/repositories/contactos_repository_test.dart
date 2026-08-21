import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:guia_telefonica/models/contacto.dart';
import 'package:guia_telefonica/repositories/contactos_repository.dart';
import 'package:guia_telefonica/services/local_database_service.dart';
import 'package:guia_telefonica/services/supabase_service.dart';

// ─── Mocks ───────────────────────────────────────────────────
class MockLocalDatabaseService extends Mock implements LocalDatabaseService {}
class MockSupabaseService extends Mock implements SupabaseService {}

// ─── Fixtures ────────────────────────────────────────────────
Contacto contactoFake({
  String id = 'test-id-1',
  String nombre = 'JUAN',
  String apellido = 'PEREZ',
  String telefono = '55551234',
  bool tieneReportes = false,
}) =>
    Contacto(
      id: id,
      nombre: nombre,
      apellido: apellido,
      telefono: telefono,
      tieneReportes: tieneReportes,
    );

void main() {
  late ContactosRepository repo;
  late MockLocalDatabaseService mockLocal;
  late MockSupabaseService mockRemote;

  setUp(() {
    mockLocal  = MockLocalDatabaseService();
    mockRemote = MockSupabaseService();
    repo = ContactosRepository(local: mockLocal, remote: mockRemote);
  });

  // ─── getPaginado ──────────────────────────────────────────
  group('getPaginado', () {
    test('retorna lista de contactos desde SQLite local', () async {
      final contactos = [contactoFake(), contactoFake(id: 'test-id-2', nombre: 'MARIA')];
      when(() => mockLocal.getContactosPaginados(
        offset: any(named: 'offset'),
        limit: any(named: 'limit'),
      )).thenAnswer((_) async => contactos);

      final result = await repo.getPaginado();

      expect(result, hasLength(2));
      expect(result.first.nombre, 'JUAN');
      verify(() => mockLocal.getContactosPaginados(offset: 0, limit: 50)).called(1);
    });

    test('pasa filtros correctamente', () async {
      when(() => mockLocal.getContactosPaginados(
        offset: any(named: 'offset'),
        limit: any(named: 'limit'),
        categoriaId: any(named: 'categoriaId'),
        soloReportados: any(named: 'soloReportados'),
      )).thenAnswer((_) async => []);

      await repo.getPaginado(categoriaId: 'cat-1', soloReportados: true, offset: 10, limit: 20);

      verify(() => mockLocal.getContactosPaginados(
        offset: 10,
        limit: 20,
        categoriaId: 'cat-1',
        soloReportados: true,
      )).called(1);
    });
  });

  // ─── count ────────────────────────────────────────────────
  group('count', () {
    test('retorna total de contactos', () async {
      when(() => mockLocal.countContactos()).thenAnswer((_) async => 42);

      final result = await repo.count();

      expect(result, 42);
    });
  });

  // ─── buscar ───────────────────────────────────────────────
  group('buscar', () {
    test('llama buscarContactosPaginados con la query', () async {
      final contactos = [contactoFake()];
      when(() => mockLocal.buscarContactosPaginados(
        any(),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      )).thenAnswer((_) async => contactos);

      final result = await repo.buscar('juan');

      expect(result, hasLength(1));
      verify(() => mockLocal.buscarContactosPaginados('juan', limit: 50, offset: 0)).called(1);
    });

    test('retorna lista vacía si query está vacía', () async {
      final result = await repo.buscar('');
      expect(result, isEmpty);
      verifyNever(() => mockLocal.buscarContactosPaginados(any()));
    });
  });

  // ─── guardarBatch ─────────────────────────────────────────
  group('guardarBatch', () {
    test('delega a sincronizarBatch del localDb', () async {
      final contactos = [contactoFake()];
      when(() => mockLocal.sincronizarBatch(any())).thenAnswer((_) async {});

      await repo.guardarBatch(contactos);

      verify(() => mockLocal.sincronizarBatch(contactos)).called(1);
    });
  });

  // ─── eliminarLocal ────────────────────────────────────────
  group('eliminarLocal', () {
    test('llama eliminarContacto con el id', () async {
      when(() => mockLocal.eliminarContacto(any())).thenAnswer((_) async {});

      await repo.eliminarLocal('test-id-1');

      verify(() => mockLocal.eliminarContacto('test-id-1')).called(1);
    });
  });
}
