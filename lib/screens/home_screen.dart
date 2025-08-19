import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:comuna_servicios/screens/call_screen.dart';
import 'package:comuna_servicios/screens/contact_screen.dart';
import 'package:comuna_servicios/services/cache_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _cacheService = CacheService();
  String _title = 'Comuna';

  @override
  void initState() {
    super.initState();
    _loadCachedTitle();
    _checkConnectionAndFetchData();
  }


  Future<void> _loadCachedTitle() async {
    String? cachedTitle = await _cacheService.loadTitle();
    if (cachedTitle != null) {
      setState(() {
        _title = cachedTitle;
      });
    }
  }


  Future<void> _checkConnectionAndFetchData() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (!connectivityResult.contains(ConnectivityResult.none)) {
      _listenToTitleChanges();
    } else {
      debugPrint('Sin conexión a Internet. Mostrando datos desde la caché.');
    }
  }

  
  void _listenToTitleChanges() {
    FirebaseFirestore.instance.collection('settings').doc('title').snapshots().listen((snapshot) {
      if (snapshot.exists) {
        String title = snapshot['title'] ?? 'Comuna';
        if (_title != title) {
          setState(() {
            _title = title;
          });
          _cacheService.saveTitle(title);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Center(
            child: Text(
          _title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        )),
      ),
      body: SafeArea(
        child: Column(
          children: const [
            Expanded(child: CallScreen()),
            ContactScreen(),
          ],
        ),
      ),
    );
  }
}
