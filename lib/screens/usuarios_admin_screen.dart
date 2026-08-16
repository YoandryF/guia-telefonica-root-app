import 'dart:async';
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'usuario_detalle_screen.dart';

class UsuariosAdminScreen extends StatefulWidget {
  const UsuariosAdminScreen({super.key});

  @override
  State<UsuariosAdminScreen> createState() => _UsuariosAdminScreenState();
}

class _UsuariosAdminScreenState extends State<UsuariosAdminScreen> {
  final _supabase = SupabaseService();
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<dynamic> _usuarios = [];
  int _total = 0;
  bool _cargando = true;
  bool _cargandoMas = false;
  String _query = '';
  int _offset = 0;
  static const _limit = 20;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() {
        _query = value.trim();
        _offset = 0;
        _usuarios = [];
      });
      _cargar();
    });
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final result = await _supabase.getUsuariosAdmin(
      query: _query,
      offset: 0,
      limit: _limit,
    );
    setState(() {
      _usuarios = List.from(result['usuarios'] ?? []);
      _total = (result['total'] as num?)?.toInt() ?? 0;
      _offset = _usuarios.length;
      _cargando = false;
    });
  }

  Future<void> _cargarMas() async {
    if (_cargandoMas || _usuarios.length >= _total) return;
    setState(() => _cargandoMas = true);
    final result = await _supabase.getUsuariosAdmin(
      query: _query,
      offset: _offset,
      limit: _limit,
    );
    final nuevos = List.from(result['usuarios'] ?? []);
    setState(() {
      _usuarios.addAll(nuevos);
      _offset += nuevos.length;
      _cargandoMas = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('👥 Usuarios'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar),
        ],
      ),
      body: Column(
        children: [
          // SearchBar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, @username o ID...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (!_cargando)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('$_total usuarios encontrados',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            ),
          // Lista
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _usuarios.isEmpty
                    ? const Center(child: Text('Sin resultados', style: TextStyle(color: Colors.grey)))
                    : RefreshIndicator(
                        onRefresh: _cargar,
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: _usuarios.length + (_usuarios.length < _total ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            if (i == _usuarios.length) {
                              return _botonCargarMas();
                            }
                            return _usuarioCard(ctx, _usuarios[i]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _botonCargarMas() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: _cargandoMas
            ? const CircularProgressIndicator()
            : OutlinedButton.icon(
                onPressed: _cargarMas,
                icon: const Icon(Icons.expand_more),
                label: Text('Cargar más (${_usuarios.length}/$_total)'),
              ),
      ),
    );
  }

  Widget _usuarioCard(BuildContext ctx, dynamic item) {
    final user = item is Map ? item : <String, dynamic>{};

    // La RPC get_usuarios_admin devuelve: chat_id, primer_nombre, ultimo_nombre, nombre_usuario
    final chatId = user['chat_id']?.toString() ?? '';
    final primerNombre = user['primer_nombre']?.toString() ?? '';
    final ultimoNombre = user['ultimo_nombre']?.toString() ?? '';
    final username = user['nombre_usuario']?.toString() ?? '';
    final nombreCompleto = '${primerNombre} ${ultimoNombre}'.trim();

    final reportes = (user['total_reportes'] as num?)?.toInt() ?? 0;
    final avales = (user['total_avales'] as num?)?.toInt() ?? 0;
    final contactos = (user['total_contactos'] as num?)?.toInt() ?? 0;
    final trustPct = (user['trust_pct'] as num?)?.toDouble();
    final restricciones = (user['restricciones_activas'] as num?)?.toInt() ?? 0;
    final baneado = user['baneado'] == true;

    final displayName = nombreCompleto.isNotEmpty
        ? nombreCompleto
        : (username.isNotEmpty ? '@$username' : chatId);
    final inicial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final tieneRestriccion = restricciones > 0 || baneado;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: tieneRestriccion ? Colors.red.shade100 : Colors.teal.shade100,
          child: Text(inicial, style: TextStyle(
            color: tieneRestriccion ? Colors.red : Colors.teal,
            fontWeight: FontWeight.bold,
          )),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
            if (baneado)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: const Text('🚫 Baneado', style: TextStyle(fontSize: 10, color: Colors.red)),
              )
            else if (tieneRestriccion)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Text('⚠️ $restricciones restricc.', style: const TextStyle(fontSize: 10, color: Colors.orange)),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (username.isNotEmpty && nombreCompleto.isNotEmpty)
              Text('@$username  •  ID: $chatId',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            if (username.isEmpty && nombreCompleto.isNotEmpty)
              Text('ID: $chatId', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 4),
            Row(
              children: [
                _miniStat('📣', reportes, tooltip: 'Reportes'),
                const SizedBox(width: 12),
                _miniStat('👍', avales, tooltip: 'Avales'),
                const SizedBox(width: 12),
                _miniStat('📇', contactos, tooltip: 'Contactos'),
                if (trustPct != null) ...[
                  const SizedBox(width: 12),
                  Text('⭐ ${trustPct.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 11,
                        color: trustPct >= 70 ? Colors.green : trustPct >= 40 ? Colors.orange : Colors.red,
                      )),
                ],
              ],
            ),
          ],
        ),
        onTap: () => Navigator.push(
          ctx,
          MaterialPageRoute(builder: (_) => UsuarioDetalleScreen(telegramUserId: chatId)),
        ).then((_) => _cargar()),
      ),
    );
  }

  Widget _miniStat(String emoji, int valor, {String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 2),
          Text('$valor', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}
