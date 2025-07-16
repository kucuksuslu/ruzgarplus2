import 'package:cloud_firestore/cloud_firestore.dart';

String liveUserDocId(String userId, String filter) => "${userId}_$filter";

Future<bool?> getLiveReadyStatus(String userId, String filter) async {
  final docId = liveUserDocId(userId, filter);
  final docRef = FirebaseFirestore.instance.collection('live_users').doc(docId);
  final docSnap = await docRef.get();

  if (docSnap.exists) {
    final data = docSnap.data();
    return data?['isReady'] as bool?;
  }
  return null;
}