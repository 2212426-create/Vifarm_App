import 'core/providers/firebase_providers.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'features/video_feed/providers/video_provider.dart';
import 'features/video_feed/services/recsys_service.dart';
import 'features/video_feed/repositories/video_repository.dart';
import 'features/video_upload/providers/upload_provider.dart';
import 'features/video_upload/repositories/upload_repository.dart';
import 'package:image_picker/image_picker.dart';
import 'main.dart' show runViFarm;

/// Local QA entrypoint; never initializes the production Firebase project.
Future<void> main() async {
  if (!kDebugMode) {
    throw StateError('Emulator entrypoint requires a debug build.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  const hostEnv = String.fromEnvironment('EMULATOR_HOST');
  String host = hostEnv.isNotEmpty ? hostEnv : '10.0.2.2';
  if (hostEnv.isEmpty && !kIsWeb && Platform.isAndroid) {
    try {
      final socket = await Socket.connect('127.0.0.1', 8089, timeout: const Duration(milliseconds: 300));
      socket.destroy();
      host = '127.0.0.1';
    } catch (_) {
      host = '10.0.2.2';
    }
  }
  try {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: 'fake-api-key',
        appId: '1:1234567890:android:0000000000000000000000',
        messagingSenderId: '1234567890',
        projectId: 'demo-vifarm-rules',
        databaseURL: 'http://$host:9000?ns=demo-vifarm-rules-default-rtdb',
        storageBucket: 'demo-vifarm-rules.appspot.com',
      ),
    );
  } catch (e) {
    debugPrint('[main_emulator] Firebase.initializeApp: $e');
  }

  try {
    FirebaseFirestore.instance.useFirestoreEmulator(
      host,
      8089,
      automaticHostMapping: false,
    );
  } catch (_) {}
  try {
    await FirebaseAuth.instance.useAuthEmulator(
      host,
      9099,
      automaticHostMapping: false,
    );
  } catch (_) {}
  final emulatorStorage = FirebaseStorage.instanceFor(
    bucket: 'demo-vifarm-rules.appspot.com',
  );
  try {
    await emulatorStorage.useStorageEmulator(
      host,
      9199,
      automaticHostMapping: false,
    );
  } catch (_) {}
  await runViFarm(
    overrides: [
      firebaseStorageProvider.overrideWithValue(emulatorStorage),
      firebaseStorageProvider.overrideWithValue(emulatorStorage),
      videoRepositoryProvider.overrideWithValue(_LocalVideoRepository()),
      uploadRepositoryProvider.overrideWithValue(_LocalUploadRepository()),
      recsysServiceProvider.overrideWithValue(
        RecSysService(
          database: FirebaseDatabase.instance,
          client: MockClient(
            (_) async => http.Response('Local QA: RecSys disabled', 503),
          ),
        ),
      ),
    ],
  );
}

class _LocalUploadRepository extends UploadRepository {
  _LocalUploadRepository() : super(firestore: FirebaseFirestore.instance);

  @override
  Future<String> uploadImageToCloudinary({required XFile file}) async {
    final storage = FirebaseStorage.instanceFor(bucket: 'demo-vifarm-rules.appspot.com');
    final extension = file.path.split('.').last.toLowerCase();
    final contentType = extension == 'png' ? 'image/png' : 'image/jpeg';
    final target = storage.ref(
      'qa-images/${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    await target.putFile(
      File(file.path),
      SettableMetadata(contentType: contentType),
    );
    return target.getDownloadURL();
  }

  @override
  Future<String> uploadVideoToCloudinary({
    required XFile file,
    required void Function(double progress) onProgress,
  }) async {
    final storage = FirebaseStorage.instanceFor(bucket: 'demo-vifarm-rules.appspot.com');
    final target = storage.ref(
      'qa-uploads/${DateTime.now().microsecondsSinceEpoch}.mp4',
    );
    final task = target.putFile(
      File(file.path),
      SettableMetadata(contentType: 'video/mp4'),
    );
    final subscription = task.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes > 0) {
        onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
      }
    });
    try {
      await task;
      return await target.getDownloadURL();
    } finally {
      await subscription.cancel();
    }
  }
}

class _LocalVideoRepository extends VideoRepository {
  _LocalVideoRepository()
    : super(
        firestore: FirebaseFirestore.instance,
        database: FirebaseDatabase.instance,
      );

  @override
  Future<void> deleteVideo({
    required String videoId,
    required String authorId,
  }) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('videos')
        .doc(videoId)
        .get();
    final url = Uri.tryParse(snapshot.data()?['videoUri'] as String? ?? '');
    await super.deleteVideo(videoId: videoId, authorId: authorId);
    // Only the debug entrypoint owns emulator blobs. Production Cloudinary
    // deletion requires a trusted server and must not expose its API secret.
    if (url != null &&
        const ['127.0.0.1', '10.0.2.2'].contains(url.host) &&
        url.port == 9199 &&
        url.pathSegments.length == 5 &&
        url.pathSegments[2] == 'demo-vifarm-rules.appspot.com' &&
        const [
          'qa-uploads',
          'qa-videos',
        ].contains(url.pathSegments[4].split('/').first)) {
      try {
        await FirebaseStorage.instance.ref(url.pathSegments[4]).delete();
        debugPrint(
          'LOCAL_QA_DELETE id=$videoId metadata=deleted media=deleted',
        );
      } catch (error) {
        debugPrint(
          'LOCAL_QA_DELETE id=$videoId metadata=deleted media_cleanup_failed=$error',
        );
      }
    }
  }
}
