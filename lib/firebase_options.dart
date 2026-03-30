import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions are not supported for this platform.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAR_ilDZbo9hPR0JJ2Wtal555N8VVWvqEQ',
    appId: '1:549455573441:web:a198bb1adb5f3b35c4ff40',
    messagingSenderId: '549455573441',
    projectId: 'aksab-erp',
    authDomain: 'aksab-erp.firebaseapp.com',
    databaseURL: 'https://aksab-erp-default-rtdb.firebaseio.com',
    storageBucket: 'aksab-erp.firebasestorage.app',
    measurementId: 'G-7GGD70EHNC',
  );
}

