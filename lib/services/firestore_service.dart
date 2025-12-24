import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> saveStrategyState(String userId, Map<String, dynamic> state) async {
    try {
      await _db.collection('users').doc(userId).collection('strategy').doc('current').set(
        {
          ...state,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      debugPrint('Strategy state synced to Firestore for $userId');
    } catch (e) {
      debugPrint('Error syncing to Firestore: $e');
    }
  }

  Future<Map<String, dynamic>?> getStrategyState(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).collection('strategy').doc('current').get();
      if (doc.exists) {
        return doc.data();
      }
    } catch (e) {
      debugPrint('Error fetching from Firestore: $e');
    }
    return null;
  }

  Stream<Map<String, dynamic>?> streamStrategyState(String userId) {
    return _db.collection('users').doc(userId).collection('strategy').doc('current').snapshots().map((doc) {
      if (doc.exists) {
        return doc.data();
      }
      return null;
    });
  }

  Future<void> clearStrategyState(String userId) async {
    try {
      await _db.collection('users').doc(userId).collection('strategy').doc('current').update({
        'selectedStrikes': null,
        'status': 'Idle',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error clearing Firestore strategy: $e');
    }
  }
}
