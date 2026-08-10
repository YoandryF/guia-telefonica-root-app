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
      version: 6,
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

  Future<List<Contacto>> getAllContactos() async {
    final db = await database;
    final maps = await db.query('contactos_aprobados', orderBy: 'nombre ASC');
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
    final batch = db.batch();
    for (final contacto in contactos) {
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
