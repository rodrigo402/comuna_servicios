import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  String? _mapUrl;
  String? _address;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchLocationData();
  }

  Future<void> _fetchLocationData() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('settings').doc('location').get();
      if (doc.exists) {
        if (!mounted) return;
        setState(() {
          _mapUrl = doc['url'];
          _address = doc['address'];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error al obtener los datos de ubicación: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ubicación de la Comuna'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_mapUrl == null || _address == null)
              ? const Center(child: Text('No se pudo cargar la ubicación.'))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Dirección:',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _address!,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final uri = Uri.parse(_mapUrl!);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          } else {
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(content: Text('No se pudo abrir el mapa.')),
                            );
                          }
                        },
                        icon: const Icon(Icons.map),
                        label: const Text('Cómo llegar'),
                      ),
                    ],
                  ),
                ),
    );
  }
}
