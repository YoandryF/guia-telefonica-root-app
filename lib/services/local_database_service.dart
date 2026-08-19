import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/contacto.dart';

class LocalDatabaseService {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'guia_telefonica.db');

    return await openDatabase(
      path,
      version: 7,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS recientes (
          contacto_id TEXT PRIMARY KEY,
          fecha_acceso TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS notas (
          contacto_id TEXT PRIMARY KEY,
          nota TEXT NOT NULL,
          fecha TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS categorias_local (
          id TEXT PRIMARY KEY,
          nombre TEXT NOT NULL,
          icono TEXT,
          color TEXT
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE contactos_aprobados ADD COLUMN tiene_reportes INTEGER DEFAULT 0');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE contactos_aprobados ADD COLUMN reporte_confirmado INTEGER DEFAULT 0');
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE contactos_aprobados ADD COLUMN pais TEXT');
      await db.execute('ALTER TABLE contactos_aprobados ADD COLUMN provincia TEXT');
      await db.execute('ALTER TABLE contactos_aprobados ADD COLUMN municipio TEXT');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_ca_provincia ON contactos_aprobados(provincia)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_ca_municipio ON contactos_aprobados(municipio)');
    }
    if (oldVersion < 7) {
      // FTS5 para búsqueda ultrarrápida — si falla, continuar sin FTS
      try {
        await db.execute('''
          CREATE VIRTUAL TABLE IF NOT EXISTS contactos_fts USING fts5(
            id UNINDEXED,
            nombre,
            apellido,
            telefono,
            ci,
            provincia,
            municipio,
            content=contactos_aprobados,
            content_rowid=rowid
          )
        ''');
        await db.execute('''
          INSERT INTO contactos_fts(rowid, id, nombre, apellido, telefono, ci, provincia, municipio)
          SELECT rowid, id, nombre, apellido, telefono, ci, provincia, municipio
          FROM contactos_aprobados
        ''');
        await db.execute('''
          CREATE TRIGGER IF NOT EXISTS ca_ai AFTER INSERT ON contactos_aprobados BEGIN
            INSERT INTO contactos_fts(rowid, id, nombre, apellido, telefono, ci, provincia, municipio)
            VALUES (new.rowid, new.id, new.nombre, new.apellido, new.telefono, new.ci, new.provincia, new.municipio);
          END
        ''');
        await db.execute('''
          CREATE TRIGGER IF NOT EXISTS ca_ad AFTER DELETE ON contactos_aprobados BEGIN
            INSERT INTO contactos_fts(contactos_fts, rowid, id, nombre, apellido, telefono, ci, provincia, municipio)
            VALUES ('delete', old.rowid, old.id, old.nombre, old.apellido, old.telefono, old.ci, old.provincia, old.municipio);
          END
        ''');
        await db.execute('''
          CREATE TRIGGER IF NOT EXISTS ca_au AFTER UPDATE ON contactos_aprobados BEGIN
            INSERT INTO contactos_fts(contactos_fts, rowid, id, nombre, apellido, telefono, ci, provincia, municipio)
            VALUES ('delete', old.rowid, old.id, old.nombre, old.apellido, old.telefono, old.ci, old.provincia, old.municipio);
            INSERT INTO contactos_fts(rowid, id, nombre, apellido, telefono, ci, provincia, municipio)
            VALUES (new.rowid, new.id, new.nombre, new.apellido, new.telefono, new.ci, new.provincia, new.municipio);
          END
        ''');
      } catch (e) {
        debugPrint('FTS5 migration failed (non-critical): $e');
      }
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE contactos_aprobados (
        id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        apellido TEXT NOT NULL,
        telefono TEXT NOT NULL,
        direccion TEXT,
        ci TEXT,
        categoria_id TEXT,
        categoria_nombre TEXT,
        categoria_icono TEXT,
        fecha_creacion TEXT,
        fecha_aprobacion TEXT,
        tiene_reportes INTEGER DEFAULT 0,
        reporte_confirmado INTEGER DEFAULT 0,
        pais TEXT,
        provincia TEXT,
        municipio TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE metadatos_sincronizacion (
        clave TEXT PRIMARY KEY,
        valor TEXT,
        ultima_actualizacion TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE favoritos (
        contacto_id TEXT PRIMARY KEY,
        fecha_agregado TEXT NOT NULL,
        orden INTEGER DEFAULT 0
      )
    ''');

    await db.execute('CREATE INDEX idx_ca_nombre ON contactos_aprobados(nombre)');
    await db.execute('CREATE INDEX idx_ca_telefono ON contactos_aprobados(telefono)');
    await db.execute('CREATE INDEX idx_ca_ci ON contactos_aprobados(ci)');
    await db.execute('CREATE INDEX idx_ca_provincia ON contactos_aprobados(provincia)');
    await db.execute('CREATE INDEX idx_ca_municipio ON contactos_aprobados(municipio)');

    // FTS5 para búsqueda ultrarrápida
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS contactos_fts USING fts5(
        id UNINDEXED, nombre, apellido, telefono, ci, provincia, municipio,
        content=contactos_aprobados, content_rowid=rowid
      )
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS ca_ai AFTER INSERT ON contactos_aprobados BEGIN
        INSERT INTO contactos_fts(rowid, id, nombre, apellido, telefono, ci, provincia, municipio)
        VALUES (new.rowid, new.id, new.nombre, new.apellido, new.telefono, new.ci, new.provincia, new.municipio);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS ca_ad AFTER DELETE ON contactos_aprobados BEGIN
        INSERT INTO contactos_fts(contactos_fts, rowid, id, nombre, apellido, telefono, ci, provincia, municipio)
        VALUES ('delete', old.rowid, old.id, old.nombre, old.apellido, old.telefono, old.ci, old.provincia, old.municipio);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS ca_au AFTER UPDATE ON contactos_aprobados BEGIN
        INSERT INTO contactos_fts(contactos_fts, rowid, id, nombre, apellido, telefono, ci, provincia, municipio)
        VALUES ('delete', old.rowid, old.id, old.nombre, old.apellido, old.telefono, old.ci, old.provincia, old.municipio);
        INSERT INTO contactos_fts(rowid, id, nombre, apellido, telefono, ci, provincia, municipio)
        VALUES (new.rowid, new.id, new.nombre, new.apellido, new.telefono, new.ci, new.provincia, new.municipio);
      END
    ''');

    await db.execute('''
      CREATE TABLE recientes (
        contacto_id TEXT PRIMARY KEY,
        fecha_acceso TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE notas (
        contacto_id TEXT PRIMARY KEY,
        nota TEXT NOT NULL,
        fecha TEXT NOT NULL
      )
    ''');
  }

  // === CONTACTOS ===

  /// Carga todos los contactos — usar solo cuando realmente se necesitan todos
  /// (sync, escanear agenda, etc). Para la UI usar getContactosPaginados.
  Future<List<Contacto>> getAllContactos() async {
    final db = await database;
    final maps = await db.query('contactos_aprobados', orderBy: 'nombre ASC');
    return maps.map((m) => Contacto.fromJson(m)).toList();
  }

  /// Buscar un contacto por teléfono exacto en SQLite local (O(log n) con índice)
  Future<Contacto?> buscarPorTelefono(String telefono) async {
    final db = await database;
    final norm = telefono.replaceAll(RegExp(r'[^0-9]'), '');
    final maps = await db.query(
      'contactos_aprobados',
      where: 'telefono = ? OR REPLACE(REPLACE(telefono,"-","")," ","") = ?',
      whereArgs: [telefono, norm],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Contacto.fromJson(maps.first);
  }

  /// Paginación SQL — no carga 25k en memoria, solo la página solicitada
  Future<List<Contacto>> getContactosPaginados({
    int offset = 0,
    int limit = 50,
    String? categoriaId,
    String? provincia,
    String? municipio,
    bool soloReportados = false,
  }) async {
    try {
      final db = await database;
      final where = <String>[];
      final args = <dynamic>[];
      if (categoriaId != null) { where.add('categoria_id = ?'); args.add(categoriaId); }
      if (provincia != null) { where.add('provincia = ?'); args.add(provincia); }
      if (municipio != null) { where.add('municipio = ?'); args.add(municipio); }
      if (soloReportados) { where.add('tiene_reportes = 1'); }
      args.addAll([limit, offset]);
      final maps = await db.rawQuery(
        'SELECT * FROM contactos_aprobados${where.isNotEmpty ? ' WHERE ${where.join(' AND ')}' : ''} ORDER BY nombre ASC LIMIT ? OFFSET ?',
        args,
      );
      return maps.map((m) => Contacto.fromJson(m)).toList();
    } catch (e) {
      debugPrint('getContactosPaginados error: $e');
      return [];
    }
  }

  /// Cuenta total de contactos sin cargarlos en memoria
  Future<int> countContactos({String? categoriaId, String? provincia, String? municipio, bool soloReportados = false}) async {
    try {
      final db = await database;
      final where = <String>[];
      final args = <dynamic>[];
      if (categoriaId != null) { where.add('categoria_id = ?'); args.add(categoriaId); }
      if (provincia != null) { where.add('provincia = ?'); args.add(provincia); }
      if (municipio != null) { where.add('municipio = ?'); args.add(municipio); }
      if (soloReportados) { where.add('tiene_reportes = 1'); }
      final result = await db.rawQuery(
        'SELECT COUNT(*) as c FROM contactos_aprobados${where.isNotEmpty ? ' WHERE ${where.join(' AND ')}' : ''}',
        args,
      );
      return (result.first['c'] as int?) ?? 0;
    } catch (e) {
      debugPrint('countContactos error: $e');
      return 0;
    }
  }

  /// Búsqueda paginada — usa FTS5 si disponible, fallback LIKE
  Future<List<Contacto>> buscarContactosPaginados(String query, {int offset = 0, int limit = 50}) async {
    final db = await database;
    // Intentar FTS5 primero
    try {
      final maps = await db.rawQuery(
        '''SELECT ca.* FROM contactos_aprobados ca
           JOIN contactos_fts fts ON ca.id = fts.id
           WHERE contactos_fts MATCH ?
           ORDER BY rank LIMIT ? OFFSET ?''',
        ['$query*', limit, offset],
      );
      if (maps.isNotEmpty) return maps.map((m) => Contacto.fromJson(m)).toList();
    } catch (_) {}

    // Fallback LIKE
    final maps = await db.rawQuery(
      '''SELECT * FROM contactos_aprobados
         WHERE nombre LIKE ? OR apellido LIKE ? OR telefono LIKE ? OR ci LIKE ?
         ORDER BY nombre ASC LIMIT ? OFFSET ?''',
      ['%$query%', '%$query%', '%$query%', '%$query%', limit, offset],
    );
    return maps.map((m) => Contacto.fromJson(m)).toList();
  }

  Future<List<Contacto>> buscarContactos(String query) async {
    final db = await database;
    final maps = await db.query(
      'contactos_aprobados',
      where: 'nombre LIKE ? OR apellido LIKE ? OR telefono LIKE ? OR ci LIKE ? OR provincia LIKE ? OR municipio LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%', '%$query%', '%$query%', '%$query%'],
      orderBy: 'nombre ASC',
    );
    return maps.map((m) => Contacto.fromJson(m)).toList();
  }

  Future<List<Contacto>> filtrarPorProvincia(String provincia) async {
    final db = await database;
    final maps = await db.query(
      'contactos_aprobados',
      where: 'provincia = ?',
      whereArgs: [provincia],
      orderBy: 'nombre ASC',
    );
    return maps.map((m) => Contacto.fromJson(m)).toList();
  }

  Future<List<Contacto>> filtrarPorMunicipio(String municipio) async {
    final db = await database;
    final maps = await db.query(
      'contactos_aprobados',
      where: 'municipio = ?',
      whereArgs: [municipio],
      orderBy: 'nombre ASC',
    );
    return maps.map((m) => Contacto.fromJson(m)).toList();
  }

  Future<void> insertarContacto(Contacto contacto) async {
    final db = await database;
    await db.insert(
      'contactos_aprobados',
      {
        'id': contacto.id,
        'nombre': contacto.nombre,
        'apellido': contacto.apellido,
        'telefono': contacto.telefono,
        'direccion': contacto.direccion,
        'ci': contacto.ci,
        'categoria_id': contacto.categoriaId,
        'categoria_nombre': contacto.categoriaNombre,
        'categoria_icono': contacto.categoriaIcono,
        'fecha_creacion': contacto.fechaCreacion?.toIso8601String(),
        'fecha_aprobacion': contacto.fechaAprobacion?.toIso8601String(),
        'pais': contacto.pais,
        'provincia': contacto.provincia,
        'municipio': contacto.municipio,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> sincronizarBatch(List<Contacto> contactos) async {
    final db = await database;
    const chunkSize = 500;
    // Procesar en chunks para no saturar memoria en gama baja
    for (var i = 0; i < contactos.length; i += chunkSize) {
      final chunk = contactos.sublist(i, i + chunkSize > contactos.length ? contactos.length : i + chunkSize);
      final batch = db.batch();
      for (final contacto in chunk) {
        batch.insert(
          'contactos_aprobados',
          {
            'id': contacto.id,
            'nombre': contacto.nombre,
            'apellido': contacto.apellido,
            'telefono': contacto.telefono,
            'direccion': contacto.direccion,
            'ci': contacto.ci,
            'categoria_id': contacto.categoriaId,
            'categoria_nombre': contacto.categoriaNombre,
            'categoria_icono': contacto.categoriaIcono,
            'fecha_creacion': contacto.fechaCreacion?.toIso8601String(),
            'fecha_aprobacion': contacto.fechaAprobacion?.toIso8601String(),
            'pais': contacto.pais,
            'provincia': contacto.provincia,
            'municipio': contacto.municipio,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    }
  }

  Future<void> eliminarContacto(String id) async {
    final db = await database;
    await db.delete('contactos_aprobados', where: 'id = ?', whereArgs: [id]);
  }

  // === SINCRONIZACIÓN ===

  Future<DateTime?> getUltimaSincronizacion() async {
    final db = await database;
    final result = await db.query(
      'metadatos_sincronizacion',
      where: 'clave = ?',
      whereArgs: ['ultima_sincronizacion'],
    );
    if (result.isEmpty) return null;
    final valor = result.first['valor'] as String?;
    return valor != null ? DateTime.tryParse(valor) : null;
  }

  Future<void> guardarUltimaSincronizacion(DateTime fecha) async {
    final db = await database;
    await db.insert(
      'metadatos_sincronizacion',
      {
        'clave': 'ultima_sincronizacion',
        'valor': fecha.toIso8601String(),
        'ultima_actualizacion': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // === FAVORITOS ===

  Future<List<String>> getFavoritosIds() async {
    final db = await database;
    final maps = await db.query('favoritos', orderBy: 'orden ASC');
    return maps.map((m) => m['contacto_id'] as String).toList();
  }

  Future<List<Contacto>> getContactosPorIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    try {
      final db = await database;
      final placeholders = ids.map((_) => '?').join(',');
      final maps = await db.rawQuery(
        'SELECT * FROM contactos_aprobados WHERE id IN ($placeholders)',
        ids,
      );
      return maps.map((m) => Contacto.fromJson(m)).toList();
    } catch (e) {
      debugPrint('getContactosPorIds error: $e');
      return [];
    }
  }

  Future<void> agregarFavorito(String contactoId) async {
    final db = await database;
    await db.insert(
      'favoritos',
      {
        'contacto_id': contactoId,
        'fecha_agregado': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> eliminarFavorito(String contactoId) async {
    final db = await database;
    await db.delete('favoritos', where: 'contacto_id = ?', whereArgs: [contactoId]);
  }

  Future<bool> esFavorito(String contactoId) async {
    final db = await database;
    final result = await db.query(
      'favoritos',
      where: 'contacto_id = ?',
      whereArgs: [contactoId],
    );
    return result.isNotEmpty;
  }

  // === RECIENTES ===

  Future<void> registrarAcceso(String contactoId) async {
    final db = await database;
    await db.insert(
      'recientes',
      {
        'contacto_id': contactoId,
        'fecha_acceso': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Mantener solo los últimos 10
    await db.execute('''
      DELETE FROM recientes WHERE contacto_id NOT IN (
        SELECT contacto_id FROM recientes ORDER BY fecha_acceso DESC LIMIT 10
      )
    ''');
  }

  Future<List<String>> getRecientesIds() async {
    final db = await database;
    final maps = await db.query('recientes', orderBy: 'fecha_acceso DESC', limit: 5);
    return maps.map((m) => m['contacto_id'] as String).toList();
  }

  // === NOTAS PRIVADAS ===

  Future<String?> getNota(String contactoId) async {
    final db = await database;
    final result = await db.query('notas', where: 'contacto_id = ?', whereArgs: [contactoId]);
    if (result.isEmpty) return null;
    return result.first['nota'] as String;
  }

  Future<void> guardarNota(String contactoId, String nota) async {
    final db = await database;
    if (nota.trim().isEmpty) {
      await db.delete('notas', where: 'contacto_id = ?', whereArgs: [contactoId]);
    } else {
      await db.insert('notas', {
        'contacto_id': contactoId,
        'nota': nota.trim(),
        'fecha': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // === REPORTES LOCAL ===

  Future<void> actualizarReportes(Map<String, bool> reportes) async {
    final db = await database;
    final batch = db.batch();
    for (final entry in reportes.entries) {
      batch.update('contactos_aprobados', {'tiene_reportes': entry.value ? 1 : 0},
          where: 'id = ?', whereArgs: [entry.key]);
    }
    await batch.commit(noResult: true);
  }

  /// Versión eficiente para 900k+ contactos:
  /// Recibe solo los IDs que TIENEN reportes (conjunto pequeño).
  /// Primero limpia todos los flags, luego activa solo los reportados.
  Future<void> actualizarReportesEficiente(Set<String> idsConReportes) async {
    final db = await database;
    // 1. Limpiar todos los flags (UPDATE masivo en SQLite es rápido)
    await db.update('contactos_aprobados', {'tiene_reportes': 0});
    if (idsConReportes.isEmpty) return;
    // 2. Activar solo los que tienen reportes (normalmente pocos)
    final batch = db.batch();
    for (final id in idsConReportes) {
      batch.update('contactos_aprobados', {'tiene_reportes': 1},
          where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  Future<List<String>> getTelefonosReportados() async {
    final db = await database;
    final result = await db.query('contactos_aprobados', where: 'tiene_reportes = 1', columns: ['telefono']);
    return result.map((r) => r['telefono'] as String).toList();
  }

  // === BACKUP / RESTORE ===

  Future<String> getDbPath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'guia_telefonica.db');
  }

  Future<void> closeDb() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }


  // === CATEGORÍAS LOCAL ===

  Future<void> guardarCategorias(List<Map<String, dynamic>> categorias) async {
    final db = await database;
    final batch = db.batch();
    batch.delete('categorias_local');
    for (final cat in categorias) {
      batch.insert('categorias_local', {
        'id': cat['id'],
        'nombre': cat['nombre'],
        'icono': cat['icono'],
        'color': cat['color'],
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCategoriasLocal() async {
    final db = await database;
    return await db.query('categorias_local', orderBy: 'nombre ASC');
  }
}
