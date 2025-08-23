import 'dart:convert';
import 'dart:io';

import 'package:comuna_servicios/models/button_model.dart';
import 'package:comuna_servicios/services/cache_service.dart';
import 'package:comuna_servicios/services/firebase_service.dart';
import 'package:comuna_servicios/services/favorites_service.dart';

import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _firebaseService = FirebaseService();
  final _cacheService = CacheService();
  final _favoritesService = FavoritesService();

  List<ButtonModel> _buttons = [];
  bool _isLoading = true;

  Set<String> _favorites = <String>{};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _loadCachedData();
    _checkConnectionAndFetchData();
  }

  Future<void> _loadFavorites() async {
    _favorites = await _favoritesService.load();
    if (mounted) setState(() {});
  }

  Future<void> _toggleFavorite(ButtonModel b) async {
    final id = _buttonId(b);
    if (_favorites.contains(id)) {
      _favorites.remove(id);
    } else {
      _favorites.add(id);
    }
    await _favoritesService.save(_favorites);
    if (mounted) setState(() {});
  }

  String _buttonId(ButtonModel b) => b.name.trim().toLowerCase();

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
    final connectivityResult = await Connectivity().checkConnectivity();
    if (!connectivityResult.contains(ConnectivityResult.none)) {
      _listenToFirestoreChanges();
    } else {
      debugPrint('Sin conexión a Internet. Mostrando datos desde la caché.');
    }
  }

  void _listenToFirestoreChanges() {
    _firebaseService.getButtonsStream().listen((links) async {
      final visibleButtons = links.where((link) => link.visible).toList()..sort((a, b) => a.order.compareTo(b.order));

      setState(() => _buttons = visibleButtons);

      await _cacheService.saveData('buttons', _buttons.map((e) => e.toMap()).toList());
    });
  }

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
        content: Text('Este dispositivo no puede hacer llamadas telefónicas.\nNúmero: $number'),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: number));
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Número copiado')),
              );
            },
            child: const Text('Copiar número'),
          ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Future<void> _shareAsVCard(String name, String number) async {
    try {
      final vcard = _buildVCard(name, number);
      final dir = await getTemporaryDirectory();
      final safe = name.replaceAll(RegExp(r'[^\w\d]+'), '_');
      final file = File('${dir.path}/$safe.vcf');
      await file.writeAsString(vcard, flush: true);

      if (!mounted) return;

      final params = ShareParams(
        text: 'Contacto: $name',
        files: [XFile(file.path, mimeType: 'text/vcard')],
        sharePositionOrigin: _shareOriginRect(context),
      );

      await SharePlus.instance.share(params);
    } catch (e) {
      debugPrint('Error al generar/compartir vCard: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
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

  void _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('No se pudo abrir la URL.');
    }
  }

  bool _matchesQuery(ButtonModel b) {
    if (_query.isEmpty) return true;
    final q = _normalize(_query);
    final hitTitle = _normalize(b.name).contains(q);
    final hitSub = (b.subButtons ?? const []).where((s) => s.visible).any((s) => _normalize(s.name).contains(q));
    return hitTitle || hitSub;
  }

  String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[áàä]'), 'a')
      .replaceAll(RegExp(r'[éèë]'), 'e')
      .replaceAll(RegExp(r'[íìï]'), 'i')
      .replaceAll(RegExp(r'[óòö]'), 'o')
      .replaceAll(RegExp(r'[úùü]'), 'u')
      .replaceAll('ñ', 'n');

  @override
  Widget build(BuildContext context) {
    final filtered = _buttons.where(_matchesQuery).toList()
      ..sort((a, b) {
        final af = _favorites.contains(_buttonId(a));
        final bf = _favorites.contains(_buttonId(b));
        if (af != bf) return af ? -1 : 1;
        return a.order.compareTo(b.order);
      });

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('Sin resultados'))
                    : ListView(
                        children: filtered.map((button) {
                          final hasSubs = button.subButtons != null && button.subButtons!.isNotEmpty;
                          return hasSubs ? _buildExpandableTile(button) : _buildListTile(button);
                        }).toList(),
                      ),
              ),
            ],
          );
  }

  Widget _buildListTile(ButtonModel button) {
    final fav = _favorites.contains(_buttonId(button));
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: ListTile(
        leading: button.icon != null && button.icon!.isNotEmpty ? Image.memory(decodeBase64(button.icon!), width: 40, height: 40) : null,
        title: Text(button.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        trailing: Wrap(spacing: 4, children: [
          IconButton(
            icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? Colors.amber : null),
            tooltip: fav ? 'Quitar de favoritos' : 'Agregar a favoritos',
            onPressed: () => _toggleFavorite(button),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Más acciones',
            onPressed: () => _openActionsSheet(button),
          ),
        ]),
        onTap: () {
          if (button.phone != null) {
            _callNumber(button.phone!);
          } else if (button.url != null) {
            _openUrl(button.url!);
          }
        },
      ),
    );
  }

  Widget _buildExpandableTile(ButtonModel button) {
    final fav = _favorites.contains(_buttonId(button));
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: ExpansionTile(
        title: Row(
          children: [
            if (button.icon != null && button.icon!.isNotEmpty) Image.memory(decodeBase64(button.icon!), width: 40, height: 40),
            const SizedBox(width: 15),
            Expanded(
              child: Text(button.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            ),
            IconButton(
              icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? Colors.amber : null),
              tooltip: fav ? 'Quitar de favoritos' : 'Agregar a favoritos',
              onPressed: () => _toggleFavorite(button),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Más acciones',
              onPressed: () => _openActionsSheet(button),
            ),
          ],
        ),
        children: button.subButtons!
            .where((s) => s.visible)
            .map((sub) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 50),
                  child: ListTile(
                    leading: sub.icon != null && sub.icon!.isNotEmpty ? Image.memory(decodeBase64(sub.icon!), width: 40, height: 40) : null,
                    title: Text(sub.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                    onTap: () {
                      if (sub.phone != null) {
                        _callNumber(sub.phone!);
                      } else if (sub.url != null) {
                        _openUrl(sub.url!);
                      }
                    },
                  ),
                ))
            .toList(),
      ),
    );
  }

  void _openActionsSheet(ButtonModel b) {
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.call),
              title: const Text('Llamar'),
              onTap: () {
                Navigator.pop(sheetCtx);
                final number = b.phone ?? '';
                if (number.isNotEmpty) _callNumber(number);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copiar número'),
              onTap: () async {
                final number = b.phone ?? '';
                final messenger = ScaffoldMessenger.of(context);

                await Clipboard.setData(ClipboardData(text: number));

                if (!mounted) return;
                if (!sheetCtx.mounted) return;
                Navigator.of(sheetCtx).pop();

                messenger.showSnackBar(
                  const SnackBar(content: Text('Número copiado')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Compartir contacto'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                if (!mounted) return;
                await SharePlus.instance.share(
                  ShareParams(
                    text: '${b.name}${(b.phone ?? '').isNotEmpty ? ' - ${b.phone}' : ''}',
                    sharePositionOrigin: _shareOriginRect(context),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('Agregar a Contactos (.vcf)'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                if (!mounted) return;
                await _shareAsVCard(b.name, b.phone ?? '');
              },
            ),
          ],
        ),
      ),
    );
  }

  Uint8List decodeBase64(String base64String) {
    try {
      if (base64String.startsWith('data:image')) {
        base64String = base64String.split(',').last;
      }
      if (base64String.length % 4 != 0) {
        base64String = base64String.padRight(base64String.length + (4 - base64String.length % 4), '=');
      }
      return base64Decode(base64String);
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
