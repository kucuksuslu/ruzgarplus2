import 'package:cloud_firestore/cloud_firestore.dart';

class Signaling {
  final String roomId;
  final _calls = FirebaseFirestore.instance.collection('calls');

  Signaling(this.roomId);

  Future<void> setOffer(Map<String, dynamic> offer) async {
    await _calls.doc(roomId).set({'offer': offer}, SetOptions(merge: true));
  }

  Future<void> setAnswer(Map<String, dynamic> answer) async {
    await _calls.doc(roomId).set({'answer': answer}, SetOptions(merge: true));
  }

  Stream<DocumentSnapshot> getCallStream() {
    return _calls.doc(roomId).snapshots();
  }

  Future<void> clearRoom() async {
    await _calls.doc(roomId).delete();
  }
}