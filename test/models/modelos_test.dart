import 'package:flutter_test/flutter_test.dart';
import 'package:guia_telefonica/models/contacto.dart';
import 'package:guia_telefonica/providers/sync_provider.dart';

void main() {
  // ─── Modelo Contacto ──────────────────────────────────────
  group('Contacto.nivelRiesgo', () {
    test('limpio cuando no tiene reportes', () {
      final c = Contacto(
        id: '1', nombre: 'Juan', apellido: 'Perez', telefono: '55551234',
        tieneReportes: false, reporteConfirmado: false,
      );
      expect(c.nivelRiesgo, NivelRiesgo.limpio);
      expect(c.esRiesgoso, false);
    });

    test('sospechoso cuando tiene reportes pendientes', () {
      final c = Contacto(
        id: '1', nombre: 'Juan', apellido: 'Perez', telefono: '55551234',
        tieneReportes: true, reporteConfirmado: false,
      );
      expect(c.nivelRiesgo, NivelRiesgo.sospechoso);
      expect(c.esRiesgoso, true);
    });

    test('confirmado cuando reporte fue aprobado', () {
      final c = Contacto(
        id: '1', nombre: 'Juan', apellido: 'Perez', telefono: '55551234',
        tieneReportes: true, reporteConfirmado: true,
      );
      expect(c.nivelRiesgo, NivelRiesgo.confirmado);
      expect(c.esRiesgoso, true);
    });
  });

  group('Contacto.nombreCompleto', () {
    test('concatena nombre y apellido', () {
      final c = Contacto(id: '1', nombre: 'Juan', apellido: 'Perez', telefono: '55551234');
      expect(c.nombreCompleto, 'Juan Perez');
    });
  });

  group('Contacto.estadoLabel', () {
    test('aprobado label', () {
      final c = Contacto(id: '1', nombre: 'A', apellido: 'B', telefono: '123', estado: 'aprobado');
      expect(c.estadoLabel, 'Aprobado');
    });
    test('pendiente label', () {
      final c = Contacto(id: '1', nombre: 'A', apellido: 'B', telefono: '123', estado: 'pendiente');
      expect(c.estadoLabel, 'Pendiente');
    });
  });

  group('Contacto.puedeReportarse', () {
    test('true cuando estado es aprobado', () {
      final c = Contacto(id: '1', nombre: 'A', apellido: 'B', telefono: '123', estado: 'aprobado');
      expect(c.puedeReportarse, true);
    });
    test('false cuando estado es pendiente', () {
      final c = Contacto(id: '1', nombre: 'A', apellido: 'B', telefono: '123', estado: 'pendiente');
      expect(c.puedeReportarse, false);
    });
  });

  group('Contacto.fromJson', () {
    test('parsea correctamente desde SQLite (tiene_reportes como int)', () {
      final json = {
        'id': 'abc', 'nombre': 'TEST', 'apellido': 'USER',
        'telefono': '55551234', 'estado': 'aprobado',
        'tiene_reportes': 1, 'reporte_confirmado': 0,
      };
      final c = Contacto.fromJson(json);
      expect(c.tieneReportes, true);
      expect(c.reporteConfirmado, false);
      expect(c.nombre, 'TEST');
    });

    test('parsea correctamente desde Supabase (tiene_reportes como bool)', () {
      final json = {
        'id': 'abc', 'nombre': 'TEST', 'apellido': 'USER',
        'telefono': '55551234', 'estado': 'aprobado',
        'tiene_reportes': true, 'reporte_confirmado': false,
      };
      final c = Contacto.fromJson(json);
      expect(c.tieneReportes, true);
      expect(c.reporteConfirmado, false);
    });
  });

  // ─── SyncState ────────────────────────────────────────────
  group('SyncState', () {
    test('enProgreso es true durante descarga', () {
      const state = SyncState(estado: SyncEstado.descargando, descargados: 100, total: 1000);
      expect(state.enProgreso, true);
      expect(state.progreso, closeTo(0.1, 0.001));
    });

    test('puedeContinuar cuando hay error con cursor', () {
      const state = SyncState(
        estado: SyncEstado.error,
        cursorNombre: 'JUAN',
        cursorId: 'some-uuid',
      );
      expect(state.puedeContinuar, true);
    });

    test('no puedeContinuar cuando hay error sin cursor', () {
      const state = SyncState(estado: SyncEstado.error);
      expect(state.puedeContinuar, false);
    });

    test('progreso es 0 cuando total es 0', () {
      const state = SyncState(estado: SyncEstado.descargando, descargados: 0, total: 0);
      expect(state.progreso, 0.0);
    });

    test('progreso es 1.0 cuando completado', () {
      const state = SyncState(estado: SyncEstado.completado, descargados: 500, total: 500);
      expect(state.progreso, 1.0);
    });

    test('mensajeProgreso incluye contadores durante descarga', () {
      const state = SyncState(estado: SyncEstado.descargando, descargados: 250, total: 1000);
      expect(state.mensajeProgreso, contains('250'));
      expect(state.mensajeProgreso, contains('1000'));
    });

    test('mensajeProgreso de error menciona Continuar cuando hay cursor', () {
      const state = SyncState(
        estado: SyncEstado.error,
        descargados: 500,
        cursorNombre: 'JUAN',
        cursorId: 'uid',
      );
      expect(state.mensajeProgreso.toLowerCase(), contains('continuar'));
    });
  });

  // ─── SyncNotifier ─────────────────────────────────────────
  group('SyncNotifier', () {
    test('estado inicial es idle', () {
      final notifier = SyncNotifier();
      expect(notifier.state.estado, SyncEstado.idle);
    });

    test('setPreparando preserva cursor anterior', () {
      final notifier = SyncNotifier();
      // Simular que viene de un error con cursor
      notifier.setError('error', cursorNombre: 'ABC', cursorId: 'xyz');
      expect(notifier.state.cursorNombre, 'ABC');

      // Al preparar de nuevo, el cursor debe preservarse
      notifier.setPreparando();
      expect(notifier.state.cursorNombre, 'ABC');
      expect(notifier.state.estado, SyncEstado.preparando);
    });

    test('setDescargando actualiza contadores', () {
      final notifier = SyncNotifier();
      notifier.setDescargando(500, 1000);
      expect(notifier.state.descargados, 500);
      expect(notifier.state.total, 1000);
      expect(notifier.state.estado, SyncEstado.descargando);
    });

    test('setCompletado resetea cursor', () {
      final notifier = SyncNotifier();
      notifier.setError('err', cursorNombre: 'X', cursorId: 'y');
      notifier.setCompletado(1000);
      expect(notifier.state.estado, SyncEstado.completado);
      expect(notifier.state.cursorNombre, isNull);
    });

    test('reset vuelve a idle', () {
      final notifier = SyncNotifier();
      notifier.setDescargando(100, 500);
      notifier.reset();
      expect(notifier.state.estado, SyncEstado.idle);
      expect(notifier.state.descargados, 0);
    });
  });
}
