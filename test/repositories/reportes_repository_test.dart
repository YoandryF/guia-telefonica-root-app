import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:guia_telefonica/repositories/reportes_repository.dart';
import 'package:guia_telefonica/services/supabase_service.dart';

class MockSupabaseService extends Mock implements SupabaseService {}

void main() {
  late ReportesRepository repo;
  late MockSupabaseService mockRemote;

  setUp(() {
    mockRemote = MockSupabaseService();
    repo = ReportesRepository(remote: mockRemote);
  });

  // ─── getPendientes ────────────────────────────────────────
  group('getPendientes', () {
    test('retorna lista de reportes pendientes', () async {
      final reportes = [
        {'id': 'r1', 'estado': 'pendiente', 'motivo': 'spam'},
        {'id': 'r2', 'estado': 'pendiente', 'motivo': 'no_existe'},
      ];
      when(() => mockRemote.getReportesPendientes())
          .thenAnswer((_) async => reportes);

      final result = await repo.getPendientes();

      expect(result, hasLength(2));
      expect(result.first['id'], 'r1');
    });

    test('retorna lista vacía si no hay pendientes', () async {
      when(() => mockRemote.getReportesPendientes())
          .thenAnswer((_) async => []);

      final result = await repo.getPendientes();
      expect(result, isEmpty);
    });
  });

  // ─── aprobar ──────────────────────────────────────────────
  group('aprobar', () {
    test('llama aprobarReporte con el id', () async {
      when(() => mockRemote.aprobarReporte(any(), notaAdmin: any(named: 'notaAdmin')))
          .thenAnswer((_) async {});

      await repo.aprobar('reporte-1');

      verify(() => mockRemote.aprobarReporte('reporte-1', notaAdmin: null)).called(1);
    });

    test('pasa notaAdmin correctamente', () async {
      when(() => mockRemote.aprobarReporte(any(), notaAdmin: any(named: 'notaAdmin')))
          .thenAnswer((_) async {});

      await repo.aprobar('reporte-1', notaAdmin: 'Verificado');

      verify(() => mockRemote.aprobarReporte('reporte-1', notaAdmin: 'Verificado')).called(1);
    });
  });

  // ─── desestimar ───────────────────────────────────────────
  group('desestimar', () {
    test('llama desestimarReporte con el id', () async {
      when(() => mockRemote.desestimarReporte(any(), notaAdmin: any(named: 'notaAdmin')))
          .thenAnswer((_) async {});

      await repo.desestimar('reporte-1');

      verify(() => mockRemote.desestimarReporte('reporte-1', notaAdmin: null)).called(1);
    });
  });

  // ─── aprobarBulk ──────────────────────────────────────────
  group('aprobarBulk', () {
    test('llama aprobarReportesBulk con la lista', () async {
      when(() => mockRemote.aprobarReportesBulk(any()))
          .thenAnswer((_) async {});

      await repo.aprobarBulk(['r1', 'r2', 'r3']);

      verify(() => mockRemote.aprobarReportesBulk(['r1', 'r2', 'r3'])).called(1);
    });
  });

  // ─── contarPendientes ─────────────────────────────────────
  group('contarPendientes', () {
    test('retorna la cantidad de pendientes', () async {
      when(() => mockRemote.getReportesPendientes())
          .thenAnswer((_) async => [
                {'id': 'r1'},
                {'id': 'r2'},
                {'id': 'r3'},
              ]);

      final result = await repo.contarPendientes();
      expect(result, 3);
    });
  });
}
