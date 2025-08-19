import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:comuna_servicios/models/button_model.dart';
import 'package:comuna_servicios/models/social_link_model.dart';

class FirebaseService {
  final _firestore = FirebaseFirestore.instance;

  Stream<List<ButtonModel>> getButtonsStream() {
    return _firestore.collection('buttons').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => ButtonModel.fromMap(doc.data())).toList();
    });
  }

  Stream<List<SocialLink>> getSocialLinksStream() {
    return _firestore.collection('social_links').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => SocialLink.fromMap(doc.data())).toList();
    });
  }
}
