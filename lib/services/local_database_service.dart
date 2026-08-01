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
      version: 1,
      onCreate: _onCreate,
    );
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
        fecha_aprobacion TEXT
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
      where: 'nombre LIKE ? OR apellido LIKE ? OR telefono LIKE ? OR ci LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%', '%$query%'],
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
}
