import 'dart:convert';
import 'dart:typed_data';

import 'package:comuna_servicios/models/button_model.dart';
import 'package:comuna_servicios/services/cache_service.dart';
import 'package:comuna_servicios/services/firebase_service.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _firebaseService = FirebaseService();
  final _cacheService = CacheService();
  List<ButtonModel> _buttons = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCachedData();
    _checkConnectionAndFetchData();
  }

  Future<void> _loadCachedData() async {
    try {
      final cachedButtons = await _cacheService.loadData('buttons', (data) {
        if (data is List) {
          return data.map((e) => ButtonModel.fromMap(e)).toList();
        }
        return <ButtonModel>[];
      });

      if (cachedButtons != null && cachedButtons.isNotEmpty) {
        setState(() {
          _buttons = cachedButtons;
        });
      }
    } catch (e) {
      debugPrint('Error al cargar datos desde la caché: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
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
      final visibleButtons = links.where((link) => link.visible).toList();

      visibleButtons.sort((a, b) => a.order.compareTo(b.order));

      setState(() {
        _buttons = visibleButtons;
      });

      await _cacheService.saveData('buttons', _buttons.map((e) => e.toMap()).toList());
    });
  }

  void _callNumber(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      debugPrint('No se pudo realizar la llamada.');
    }
  }

  void _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('No se pudo abrir la URL.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _buttons.isEmpty
            ? const Center(
                child: Text(
                  'No hay datos disponibles.\n Revisa tu conexión a Internet.',
                  style: TextStyle(fontSize: 16),
                ),
              )
            : ListView(
                children: _buttons.map((button) {
                  return button.subButtons != null && button.subButtons!.isNotEmpty
                      ? _buildExpandableTile(button) // Botones desplegables
                      : _buildListTile(button); // Botones normales
                }).toList(),
              );
  }

  Widget _buildListTile(ButtonModel button) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: ListTile(
        leading: button.icon != null && button.icon!.isNotEmpty
            ? Image.memory(
                decodeBase64(button.icon!),
                width: 40,
                height: 40,
              )
            : null, // Si no tiene icono, no mostramos nada.
        title: Text(
          button.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
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
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: ExpansionTile(
        title: Row(
          children: [
            if (button.icon != null && button.icon!.isNotEmpty)
              Image.memory(
                decodeBase64(button.icon!),
                width: 40,
                height: 40,
              ),
            const SizedBox(width: 15),
            Text(
              button.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        children: button.subButtons!.where((subButton) => subButton.visible).map((subButton) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 50),
            child: ListTile(
              leading: subButton.icon != null && subButton.icon!.isNotEmpty
                  ? Image.memory(
                      decodeBase64(subButton.icon!),
                      width: 40,
                      height: 40,
                    )
                  : null, // Si no hay icono, no se muestra nada.
              title: Text(
                subButton.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
              onTap: () {
                if (subButton.phone != null) {
                  _callNumber(subButton.phone!);
                } else if (subButton.url != null) {
                  _openUrl(subButton.url!);
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Uint8List decodeBase64(String base64String) {
    try {
      if (base64String.startsWith('data:image')) {
        final base64Data = base64String.split(',').last;
        base64String = base64Data;
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
}
