import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/constants/app_constants.dart';
import '../models/profile_model.dart';
import '../models/user_model.dart';

/// Repository xử lý logic xác thực và quản lý user/profile ViFarm
class AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthRepository({
    required this._auth,
    required this._firestore,
  });

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<User> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      throw Exception('Lỗi xác thực người dùng mới.');
    }

    String username = email.split('@')[0];
    username = username.replaceAll(RegExp(r'[^a-zA-Z0-9_.]'), '');
    if (username.isEmpty) {
      username = 'user_${user.uid.substring(0, 5)}';
    }

    final userModel = UserModel(
      userId: user.uid,
      username: username,
      email: email,
    );

    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .set(userModel.toMap());

    final profileModel = ProfileModel(
      userId: user.uid,
      username: username,
      fullname: username,
      bio: 'Thành viên ViFarm',
    );

    await _firestore
        .collection(AppConstants.profilesCollection)
        .doc(user.uid)
        .set(profileModel.toMap());

    return user;
  }

  Future<User> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      throw Exception('Đăng nhập thất bại.');
    }

    return user;
  }

  Future<User?> signInWithGoogle() async {
    late User user;
    late String displayName;
    late String email;
    late String photoUrl;

    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      final credential = await _auth.signInWithPopup(provider);
      user = credential.user!;
      displayName = user.displayName ?? '';
      email = user.email ?? '';
      photoUrl = user.photoURL ?? '';
    } else {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      final signedInUser = userCredential.user;
      if (signedInUser == null) {
        throw Exception('Đăng nhập bằng tài khoản Google thất bại.');
      }
      user = signedInUser;
      displayName = googleUser.displayName ?? '';
      email = googleUser.email;
      photoUrl = googleUser.photoUrl ?? '';
    }

    final userDocRef = _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid);
    final userDoc = await userDocRef.get();

    String username = displayName;
    if (username.isEmpty) {
      username = 'user_${user.uid.substring(0, 5)}';
    }
    username = username.replaceAll(RegExp(r'[^a-zA-Z0-9_.]'), '');

    if (!userDoc.exists) {
      final userData = {
        'userId': user.uid,
        'username': username,
        'birthdate': '',
        'avatarUrl': photoUrl,
        'email': email,
        'isPrivate': false,
        'phone': '',
        'status': 'active',
        'role': 'user',
      };
      await userDocRef.set(userData);
    } else {
      final status = userDoc.data()?['status'] as String?;
      if (status == 'banned') {
        await signOut();
        throw Exception(
          'Tài khoản của bạn đã bị khóa do vi phạm tiêu chuẩn cộng đồng.',
        );
      }
    }

    final profileDocRef = _firestore
        .collection(AppConstants.profilesCollection)
        .doc(user.uid);
    final profileDoc = await profileDocRef.get();

    if (!profileDoc.exists) {
      final profileData = {
        'userId': user.uid,
        'email': email,
        'username': username,
        'fullname': displayName.isNotEmpty ? displayName : username,
        'avatar': photoUrl,
        'bio': 'Thành viên ViFarm',
        'followers': 0,
        'following': 0,
        'likes': 0,
        'isPrivate': false,
      };
      await profileDocRef.set(profileData);
    }

    return user;
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user != null) {
      await _firestore.collection(AppConstants.usersCollection).doc(user.uid).delete();
      await _firestore.collection(AppConstants.profilesCollection).doc(user.uid).delete();
      await user.delete();
    }
  }

  Future<UserModel?> getUserData(String uid) async {
    final doc = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .get();

    if (!doc.exists || doc.data() == null) return null;
    return UserModel.fromMap(doc.data()!);
  }

  Future<ProfileModel?> getProfile(String uid) async {
    final doc = await _firestore
        .collection(AppConstants.profilesCollection)
        .doc(uid)
        .get();

    if (!doc.exists || doc.data() == null) return null;
    return ProfileModel.fromMap(doc.data()!);
  }

  Stream<UserModel?> watchUserStatus(String uid) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .snapshots()
        .map((doc) {
          if (!doc.exists || doc.data() == null) return null;
          return UserModel.fromMap(doc.data()!);
        });
  }
}
