import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:comuna_servicios/models/button_model.dart';
import 'package:comuna_servicios/services/cache_service.dart';
import 'package:comuna_servicios/services/favorites_service.dart';
import 'package:comuna_servicios/services/firebase_service.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

/* =====================  Recientes (local)  ===================== */

const _kRecents = 'recent_items';

class RecentItem {
  final String id;
  final String name;
  final String? phone;
  final String? url;
  final int ts; // epoch ms

  RecentItem({
    required this.id,
    required this.name,
    this.phone,
    this.url,
    required this.ts,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'url': url,
        'ts': ts,
      };

  static RecentItem fromMap(Map<String, dynamic> m) => RecentItem(
        id: m['id'] ?? '',
        name: m['name'] ?? '',
        phone: m['phone'],
        url: m['url'],
        ts: m['ts'] ?? 0,
      );
}

class _CallScreenState extends State<CallScreen> {
  final _firebaseService = FirebaseService();
  final _cacheService = CacheService();
  final _favoritesService = FavoritesService();

  List<ButtonModel> _buttons = [];
  bool _isLoading = true;

  // UX
  Set<String> _favorites = <String>{};
  String _query = '';

  // Recientes + Filtros
  List<RecentItem> _recents = [];
  String? _activeFilter; // null=Todos | emerg | salud | serv | adm

  /* =====================  lifecycle  ===================== */

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _loadRecents();
    _loadCachedData();
    _checkConnectionAndFetchData();
  }

  /* =====================  favoritos  ===================== */

  Future<void> _loadFavorites() async {
    _favorites = await _favoritesService.load();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _toggleFavoriteId(String id) async {
    if (_favorites.contains(id)) {
      _favorites.remove(id);
    } else {
      _favorites.add(id);
    }
    await _favoritesService.save(_favorites);
    if (!mounted) return;
    setState(() {});
  }

  String _buttonId(ButtonModel b) => b.name.trim().toLowerCase();
  String _subButtonId(ButtonModel parent, ButtonModel sub) => '${_buttonId(parent)}__${sub.name.trim().toLowerCase()}';

  /* =====================  recientes  ===================== */

  Future<void> _loadRecents() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kRecents);
    if (s == null) return;
    final List data = jsonDecode(s);
    _recents = data.map((e) => RecentItem.fromMap(Map<String, dynamic>.from(e))).toList()..sort((a, b) => b.ts.compareTo(a.ts));
    if (mounted) setState(() {});
  }

  Future<void> _saveRecents() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kRecents,
      jsonEncode(_recents.map((e) => e.toMap()).toList()),
    );
  }

  Future<void> _trackUse({
    required String id,
    required String name,
    String? phone,
    String? url,
  }) async {
    _recents.removeWhere((r) => r.id == id);
    _recents.insert(
      0,
      RecentItem(
        id: id,
        name: name,
        phone: phone,
        url: url,
        ts: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (_recents.length > 12) {
      _recents = _recents.take(12).toList();
    }
    await _saveRecents();
    if (mounted) setState(() {});
  }

  /* =====================  cache / firestore  ===================== */

  Future<void> _loadCachedData() async {
    try {
      final cachedButtons = await _cacheService.loadData('buttons', (data) {
        if (data is List) {
          return data.map((e) => ButtonModel.fromMap(e)).toList();
        }
        return <ButtonModel>[];
      });

      if (cachedButtons != null && cachedButtons.isNotEmpty) {
        setState(() => _buttons = cachedButtons);
      }
    } catch (e) {
      debugPrint('Error al cargar datos desde la caché: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkConnectionAndFetchData() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (!connectivity.contains(ConnectivityResult.none)) {
      _listenToFirestoreChanges();
    }
  }

  void _listenToFirestoreChanges() {
    _firebaseService.getButtonsStream().listen((items) async {
      final list = items.where((it) => it.visible).toList()..sort((a, b) => a.order.compareTo(b.order));

      setState(() => _buttons = list);
      await _cacheService.saveData('buttons', list.map((e) => e.toMap()).toList());
    });
  }

  /* =====================  acciones base  ===================== */

  Future<void> _callNumber(String number) async {
    final telUri = Uri(scheme: 'tel', path: number);
    final ftAudioUri = Uri.parse('facetime-audio:$number');

    try {
      if (await canLaunchUrl(telUri)) {
        await launchUrl(telUri, mode: LaunchMode.externalApplication);
        return;
      }
      if (await canLaunchUrl(ftAudioUri)) {
        await launchUrl(ftAudioUri, mode: LaunchMode.externalApplication);
        return;
      }
      _showCantCallDialog(number);
    } catch (e) {
      debugPrint('Error al intentar llamar: $e');
      _showCantCallDialog(number);
    }
  }

  void _showCantCallDialog(String number) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No se puede realizar la llamada'),
        content: Text(
          'Este dispositivo no puede hacer llamadas telefónicas.\n'
          'Número: $number',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(ctx);
              await Clipboard.setData(ClipboardData(text: number));
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              messenger.showSnackBar(
                const SnackBar(content: Text('Número copiado')),
              );
            },
            child: const Text('Copiar número'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareAsVCard(String name, String number) async {
    final origin = _shareOriginRect(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final vcard = _buildVCard(name, number);

      final dir = await getTemporaryDirectory();
      final safe = name.replaceAll(RegExp(r'[^\w\d]+'), '_');
      final file = File('${dir.path}/$safe.vcf');
      await file.writeAsString(vcard, flush: true);

      final params = ShareParams(
        text: 'Contacto: $name',
        files: [XFile(file.path, mimeType: 'text/vcard')],
        sharePositionOrigin: origin,
      );
      await SharePlus.instance.share(params);
    } catch (e) {
      debugPrint('Error al generar/compartir vCard: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo crear el contacto')),
      );
    }
  }

  String _buildVCard(String name, String number) {
    final safeName = name.replaceAll('\n', ' ').trim();
    final safeNumber = number.replaceAll(' ', '');
    return '''
BEGIN:VCARD
VERSION:3.0
FN:$safeName
N:$safeName;;;;
TEL;TYPE=CELL,VOICE:$safeNumber
END:VCARD
''';
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('No se pudo abrir la URL: $url');
    }
  }

  /* =====================  búsqueda + filtros  ===================== */

  bool _matchesQuery(ButtonModel b) {
    if (_query.isEmpty) return true;
    final q = _normalize(_query);
    final hitTitle = _normalize(b.name).contains(q);
    final hitSub = (b.subButtons ?? const []).where((s) => s.visible).any((s) => _normalize(s.name).contains(q));
    return hitTitle || hitSub;
  }

  bool _passesFilter(ButtonModel b) {
    if (_activeFilter == null) return true;
    final n = _normalize(b.name);
    switch (_activeFilter) {
      case 'emerg':
        return n.contains('bombero') || n.contains('polic') || n.contains('ambul') || n.contains('emergen') || n.contains('guardia');
      case 'salud':
        return n.contains('salud') || n.contains('hospital') || n.contains('clinica') || n.contains('médic') || n.contains('medic') || n.contains('vacun');
      case 'serv':
        return n.contains('luz') || n.contains('energia') || n.contains('energía') || n.contains('gas') || n.contains('agua') || n.contains('cloaca') || n.contains('residu') || n.contains('basura');
      case 'adm':
        return n.contains('comuna') || n.contains('municip') || n.contains('impuesto') || n.contains('tramite') || n.contains('trámite') || n.contains('rentas') || n.contains('patente');
    }
    return true;
  }

  String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[áàä]'), 'a')
      .replaceAll(RegExp(r'[éèë]'), 'e')
      .replaceAll(RegExp(r'[íìï]'), 'i')
      .replaceAll(RegExp(r'[óòö]'), 'o')
      .replaceAll(RegExp(r'[úùü]'), 'u')
      .replaceAll('ñ', 'n');

  /* =====================  hint dinámico del buscador  ===================== */

  String _searchHintExamples() {
    final Map<String, int> nameToOrder = {};

    for (final b in _buttons) {
      if (b.visible) {
        nameToOrder[b.name] = b.order;
        for (final s in (b.subButtons ?? const [])) {
          if (s.visible) {
            final ord = s.order ?? 999;
            nameToOrder.update(
              s.name,
              (old) => old < ord ? old : ord,
              ifAbsent: () => ord,
            );
          }
        }
      }
    }

    if (nameToOrder.isEmpty) return '';

    final ordered = nameToOrder.entries.toList()
      ..sort((a, b) {
        final byOrder = a.value.compareTo(b.value);
        return byOrder != 0 ? byOrder : a.key.length.compareTo(b.key.length);
      });

    final top = ordered.take(3).map((e) => e.key).toList();
    final hasMore = ordered.length > 3;

    return hasMore ? '${top.join(', ')}...' : top.join(', ');
  }

  /* =====================  UI  ===================== */

  @override
  Widget build(BuildContext context) {
    final hint = _searchHintExamples();
    final hintText = hint.isEmpty ? 'Buscar' : 'Buscar ($hint)';

    final filtered = _buttons.where(_matchesQuery).where(_passesFilter).toList()
      ..sort((a, b) {
        final af = _favorites.contains(_buttonId(a));
        final bf = _favorites.contains(_buttonId(b));
        if (af != bf) return af ? -1 : 1;
        return a.order.compareTo(b.order);
      });

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // buscador
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: hintText,
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),

        // filtros por categoría
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(null, 'Todos'),
                const SizedBox(width: 8),
                _buildFilterChip('emerg', 'Emergencias'),
                const SizedBox(width: 8),
                _buildFilterChip('adm', 'Administración'),
                const SizedBox(width: 8),
                _buildFilterChip('serv', 'Servicios'),
                const SizedBox(width: 8),
                _buildFilterChip('salud', 'Salud'),
              ],
            ),
          ),
        ),

        // recientes (carrusel horizontal con eliminar)
        if (_recents.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('Recientes:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
                // Hace scroll horizontal y evita overflow
                Expanded(
                  child: SizedBox(
                    height: 36, // alto cómodo para chips
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.zero,
                      itemBuilder: (context, index) {
                        final r = _recents[index];
                        return InputChip(
                          label: Text(r.name, overflow: TextOverflow.ellipsis),
                          onPressed: () {
                            if (r.phone != null && r.phone!.isNotEmpty) {
                              _callNumber(r.phone!);
                            } else if (r.url != null && r.url!.isNotEmpty) {
                              _openUrl(r.url!);
                            }
                          },
                          onDeleted: () => _removeRecent(r.id), // ❌ para borrar
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemCount: _recents.length.clamp(0, 20), // muestra hasta 20
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        // lista
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('Sin resultados'))
              : ListView(
                  children: filtered.map((btn) {
                    final hasSubs = btn.subButtons != null && btn.subButtons!.isNotEmpty;
                    return hasSubs ? _buildExpandableTile(btn) : _buildListTile(btn);
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String? key, String label) {
    final selected = _activeFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _activeFilter = key),
    );
  }

  Widget _buildListTile(ButtonModel button) {
    final id = _buttonId(button);
    final fav = _favorites.contains(id);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: ListTile(
        leading: (button.icon != null && button.icon!.isNotEmpty) ? Image.memory(decodeBase64(button.icon!), width: 40, height: 40) : null,
        title: Text(button.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? Colors.amber : null),
              tooltip: fav ? 'Quitar de favoritos' : 'Agregar a favoritos',
              onPressed: () => _toggleFavoriteId(id),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Más acciones',
              onPressed: () => _openActionsSheetFor(
                name: button.name,
                phone: button.phone,
                url: button.url,
              ),
            ),
          ],
        ),
        onTap: () async {
          if (button.phone != null && button.phone!.isNotEmpty) {
            await _trackUse(id: id, name: button.name, phone: button.phone);
            _callNumber(button.phone!);
          } else if (button.url != null && button.url!.isNotEmpty) {
            await _trackUse(id: id, name: button.name, url: button.url);
            _openUrl(button.url!);
          }
        },
      ),
    );
  }

  void _removeRecent(String id) async {
    setState(() {
      _recents.removeWhere((r) => r.id == id);
    });
    await _saveRecents();
  }

  Widget _buildExpandableTile(ButtonModel parent) {
    final parentId = _buttonId(parent);
    final parentFav = _favorites.contains(parentId);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: ExpansionTile(
        title: Row(
          children: [
            if (parent.icon != null && parent.icon!.isNotEmpty) Image.memory(decodeBase64(parent.icon!), width: 40, height: 40),
            const SizedBox(width: 15),
            Expanded(
              child: Text(parent.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            ),
            IconButton(
              icon: Icon(parentFav ? Icons.star : Icons.star_border, color: parentFav ? Colors.amber : null),
              tooltip: parentFav ? 'Quitar de favoritos' : 'Agregar a favoritos',
              onPressed: () => _toggleFavoriteId(parentId),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Más acciones',
              onPressed: () => _openActionsSheetFor(
                name: parent.name,
                phone: parent.phone,
                url: parent.url,
              ),
            ),
          ],
        ),
        children: (parent.subButtons ?? const []).where((s) => s.visible).map((sub) {
          final subId = _subButtonId(parent, sub);
          final fav = _favorites.contains(subId);

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 50),
            child: ListTile(
              leading: (sub.icon != null && sub.icon!.isNotEmpty) ? Image.memory(decodeBase64(sub.icon!), width: 40, height: 40) : null,
              title: Text(sub.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? Colors.amber : null),
                    tooltip: fav ? 'Quitar de favoritos' : 'Agregar a favoritos',
                    onPressed: () => _toggleFavoriteId(subId),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'Más acciones',
                    onPressed: () => _openActionsSheetFor(
                      name: sub.name,
                      phone: sub.phone,
                      url: sub.url,
                    ),
                  ),
                ],
              ),
              onTap: () async {
                if (sub.phone != null && sub.phone!.isNotEmpty) {
                  await _trackUse(id: subId, name: sub.name, phone: sub.phone);
                  _callNumber(sub.phone!);
                } else if (sub.url != null && sub.url!.isNotEmpty) {
                  await _trackUse(id: subId, name: sub.name, url: sub.url);
                  _openUrl(sub.url!);
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  /* =====================  hoja de acciones  ===================== */

  void _openActionsSheetFor({
    required String name,
    String? phone,
    String? url,
  }) {
    final rootMessenger = ScaffoldMessenger.of(context);

    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Wrap(
          children: [
            if (phone != null && phone.isNotEmpty) ...[
              ListTile(
                leading: const Icon(Icons.call),
                title: const Text('Llamar'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _callNumber(phone);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copiar número'),
                onTap: () async {
                  Navigator.pop(sheetCtx); // cerrar antes del await
                  await Clipboard.setData(ClipboardData(text: phone));
                  rootMessenger.showSnackBar(
                    const SnackBar(content: Text('Número copiado')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_add),
                title: const Text('Agregar a Contactos'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await _shareAsVCard(name, phone);
                },
              ),
            ],
            if (url != null && url.isNotEmpty) ...[
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Abrir enlace'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _openUrl(url);
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Compartir'),
              onTap: () async {
                Navigator.pop(sheetCtx);

                final text = (phone != null && phone.isNotEmpty)
                    ? '$name - $phone'
                    : (url != null && url.isNotEmpty)
                        ? '$name - $url'
                        : name;

                final origin = _shareOriginRect(context); // capturado antes del await

                await SharePlus.instance.share(
                  ShareParams(text: text, sharePositionOrigin: origin),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /* =====================  utils  ===================== */

  Uint8List decodeBase64(String base64String) {
    try {
      var s = base64String;
      if (s.startsWith('data:image')) {
        s = s.split(',').last;
      }
      if (s.length % 4 != 0) {
        s = s.padRight(s.length + (4 - s.length % 4), '=');
      }
      return base64Decode(s);
    } catch (e) {
      debugPrint('Error al decodificar Base64: $e');
      return Uint8List(0);
    }
  }

  Rect _shareOriginRect(BuildContext ctx) {
    final overlay = Overlay.maybeOf(ctx);
    final box = overlay?.context.findRenderObject() as RenderBox?;
    if (box == null) return const Rect.fromLTWH(0, 0, 0, 0);
    final topLeft = box.localToGlobal(Offset.zero);
    return topLeft & box.size;
  }
}
