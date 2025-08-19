import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:comuna_servicios/models/social_link_model.dart';
import 'package:comuna_servicios/services/firebase_service.dart';
import 'package:comuna_servicios/services/cache_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'dart:typed_data';

class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  final _firebaseService = FirebaseService();
  final _cacheService = CacheService();
  List<SocialLink> _socialLinks = [];
  bool _isLoading = true;
  String _footerTitle = 'Redes Sociales';

  @override
  void initState() {
    super.initState();
    _loadCachedData();
    _loadCachedFooterTitle();
    _checkConnectionAndFetchData();
  }

  Future<void> _loadCachedData() async {
    try {
      final cachedLinks = await _cacheService.loadData('social_links', (data) {
        if (data is List) {
          return data.map((e) => SocialLink.fromMap(e)).toList();
        }
        return <SocialLink>[];
      });

      if (cachedLinks != null && cachedLinks.isNotEmpty) {
        setState(() {
          _socialLinks = cachedLinks;
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

  Future<void> _loadCachedFooterTitle() async {
    String? cachedTitleFooter = await _cacheService.loadTitleFooter();
    if (cachedTitleFooter != null) {
      setState(() {
        _footerTitle = cachedTitleFooter;
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
    FirebaseFirestore.instance.collection('settings').doc('footer_title').snapshots().listen((snapshot) {
      if (snapshot.exists) {
        String title = snapshot['title'] ?? 'Redes Sociales';
        if (_footerTitle != title) {
          setState(() {
            _footerTitle = title;
          });
          _cacheService.saveTitleFooter(title);
        }
      }
    });

    _firebaseService.getSocialLinksStream().listen((links) async {
      List<SocialLink> visibleLinks = links.where((link) => link.visible).toList();

      visibleLinks.sort((a, b) {
        final orderA = a.order ?? 999;
        final orderB = b.order ?? 999;
        return orderA.compareTo(orderB);
      });

      setState(() {
        _socialLinks = visibleLinks;
      });

      await _cacheService.saveData('social_links', _socialLinks.map((e) => e.toMap()).toList());
    });
  }

  void _openLink(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      debugPrint('No se pudo abrir el enlace: $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _socialLinks.isEmpty
            ? const SizedBox.shrink()
            : Container(
                color: Colors.grey[200],
                padding: const EdgeInsets.all(6.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Center(
                        child: Text(
                          _footerTitle,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: _socialLinks.map((link) {
                        return IconButton(
                          icon: Image.memory(
                            link.icon.isNotEmpty ? decodeBase64(link.icon) : Uint8List(0),
                            width: 60,
                            height: 60,
                          ),
                          onPressed: () => _openLink(link.url),
                          tooltip: link.platform,
                        );
                      }).toList(),
                    ),
                  ],
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
