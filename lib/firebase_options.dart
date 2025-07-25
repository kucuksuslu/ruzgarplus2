// File generated by FlutterFire CLI.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD49lz-iCazCw7Sa7ShnWeWoYjK1MDgqXo',
    appId: '1:216918004194:web:ab749bba50a1e6872da9bb',
    messagingSenderId: '216918004194',
    projectId: 'ruzgarplus-2a597',
    authDomain: 'ruzgarplus-2a597.firebaseapp.com',
    storageBucket: 'ruzgarplus-2a597.firebasestorage.app',
    measurementId: 'G-NP972P90EY',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB7oTftHAdQRLad9XuV0dnWgCG5-bPp6o0',
    appId: '1:216918004194:android:bea630e64e4b96792da9bb',
    messagingSenderId: '216918004194',
    projectId: 'ruzgarplus-2a597',
    storageBucket: 'ruzgarplus-2a597.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBKhE2gvzFWHEaJTvzdXVxLPbZjHK48RRk',
    appId: '1:216918004194:ios:f222df2e9dcde2ec2da9bb',
    messagingSenderId: '216918004194',
    projectId: 'ruzgarplus-2a597',
    storageBucket: 'ruzgarplus-2a597.firebasestorage.app',
    iosBundleId: 'com.example.ruzgarplus',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBKhE2gvzFWHEaJTvzdXVxLPbZjHK48RRk',
    appId: '1:216918004194:ios:f222df2e9dcde2ec2da9bb',
    messagingSenderId: '216918004194',
    projectId: 'ruzgarplus-2a597',
    storageBucket: 'ruzgarplus-2a597.firebasestorage.app',
    iosBundleId: 'com.example.ruzgarplus',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyD49lz-iCazCw7Sa7ShnWeWoYjK1MDgqXo',
    appId: '1:216918004194:web:66fc80325236c6c62da9bb',
    messagingSenderId: '216918004194',
    projectId: 'ruzgarplus-2a597',
    authDomain: 'ruzgarplus-2a597.firebaseapp.com',
    storageBucket: 'ruzgarplus-2a597.firebasestorage.app',
    measurementId: 'G-TQBBR83F2N',
  );
}
