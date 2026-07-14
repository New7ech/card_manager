import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'database_service.dart';
import 'telegram_service.dart';

String _usernameToEmail(String username) =>
    '${username.trim().toLowerCase()}@cardmanager.internal';

final RegExp _usernameRegExp = RegExp(r'^[a-zA-Z0-9._-]+$');

bool _isUsernameValid(String username) =>
    _usernameRegExp.hasMatch(username.trim());

String _usernameValidationError() =>
    "Le nom d'utilisateur ne peut contenir que des lettres, chiffres, '.', '_' ou '-'.";

const _googleServerClientId =
    '989817367971-s74c0ocl93qssguq25hhgtv2gu9flibh.apps.googleusercontent.com';

class AuthResult {
  final bool success;
  final String message;
  final User? user;

  AuthResult({required this.success, required this.message, this.user});
}

class _ProfileException implements Exception {
  final String message;

  const _ProfileException(this.message);
}

class AuthService {
  static final AuthService instance = AuthService._internal();
  AuthService._internal();

  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
    serverClientId: _googleServerClientId,
  );

  User? _currentUser;
  User? get currentUser => _currentUser;

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  Future<AuthResult> login(String username, String password) async {
    final trimmedUsername = username.trim();
    if (trimmedUsername.isEmpty) {
      return AuthResult(
        success: false,
        message: "Le nom d'utilisateur ne peut pas etre vide.",
      );
    }

    if (!_isUsernameValid(trimmedUsername)) {
      return AuthResult(success: false, message: _usernameValidationError());
    }

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: _usernameToEmail(username),
        password: password,
      );
      final firebaseUser = credential.user;

      if (firebaseUser == null) {
        return AuthResult(
          success: false,
          message: 'Connexion impossible. Veuillez reessayer.',
        );
      }

      final profileResult = await _loadOrCreateUserProfile(
        firebaseUser,
        username: trimmedUsername,
      );
      final user = profileResult.user;

      if (user.status == 'blocked') {
        await _auth.signOut();
        _currentUser = null;
        return AuthResult(success: false, message: _blockedAccountMessage);
      }

      _currentUser = user;
      await DatabaseService.instance.logActivity(
        user.username,
        'Connexion',
        'Utilisateur connecte avec succes.',
      );

      return AuthResult(
        success: true,
        message: 'Connexion reussie.',
        user: user,
      );
    } on firebase_auth.FirebaseAuthException catch (e) {
      return AuthResult(success: false, message: _loginErrorMessage(e));
    } on _ProfileException catch (e) {
      await _auth.signOut().catchError((_) {});
      _currentUser = null;
      return AuthResult(success: false, message: e.message);
    } catch (_) {
      return AuthResult(
        success: false,
        message: 'Connexion impossible. Veuillez reessayer.',
      );
    }
  }

  Future<AuthResult> register(String username, String password) async {
    final trimmedUsername = username.trim();
    if (trimmedUsername.isEmpty) {
      return AuthResult(
        success: false,
        message: "Le nom d'utilisateur ne peut pas etre vide.",
      );
    }

    if (!_isUsernameValid(trimmedUsername)) {
      return AuthResult(success: false, message: _usernameValidationError());
    }

    final passwordRegex = RegExp(r'^(?=.*[A-Z])(?=.*\d).{8,}$');
    if (!passwordRegex.hasMatch(password)) {
      return AuthResult(
        success: false,
        message:
            'Le mot de passe doit faire au moins 8 caracteres et contenir au moins 1 majuscule et 1 chiffre.',
      );
    }

    firebase_auth.User? firebaseUser;
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: _usernameToEmail(trimmedUsername),
        password: password,
      );
      firebaseUser = credential.user;

      if (firebaseUser == null) {
        return AuthResult(
          success: false,
          message: 'Creation du compte impossible. Veuillez reessayer.',
        );
      }

      await firebaseUser.updateDisplayName(trimmedUsername);
      await _usersCollection.doc(firebaseUser.uid).set({
        'username': trimmedUsername,
        'role': 'user',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });

      final now = DateTime.now();
      final user = User(
        id: firebaseUser.uid,
        username: trimmedUsername,
        passwordHash: '',
        role: 'user',
        status: 'active',
        createdAt: now,
      );

      _currentUser = user;
      await DatabaseService.instance.logActivity(
        user.username,
        'Inscription',
        'Nouveau compte cree et active.',
      );

      TelegramService.instance.isConfigured().then((isConfig) {
        if (isConfig) {
          TelegramService.instance.sendMessage(
            "**Nouvelle inscription d'utilisateur**\n"
            "- Nom d'utilisateur : ${user.username}\n"
            "- Statut : Actif\n"
            "- Date : ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}",
          );
        }
      });

      return AuthResult(
        success: true,
        message: 'Compte cree avec succes.',
        user: user,
      );
    } on firebase_auth.FirebaseAuthException catch (e) {
      return AuthResult(success: false, message: _registerErrorMessage(e));
    } catch (e) {
      if (firebaseUser != null) {
        await firebaseUser.delete().catchError((_) {});
        await _auth.signOut().catchError((_) {});
      }
      return AuthResult(success: false, message: _profileWriteErrorMessage(e));
    }
  }

  Future<AuthResult> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return AuthResult(success: false, message: 'Connexion Google annulee.');
      }

      final googleAuth = await googleUser.authentication;
      final credential = firebase_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      final firebaseUser = userCredential.user;

      if (firebaseUser == null) {
        return AuthResult(
          success: false,
          message: 'Connexion Google impossible. Veuillez reessayer.',
        );
      }

      final profileResult = await _loadOrCreateUserProfile(
        firebaseUser,
        username: _googleUsername(firebaseUser, googleUser),
        provider: 'google.com',
      );
      final user = profileResult.user;

      if (user.status == 'blocked') {
        await _auth.signOut();
        await _googleSignIn.signOut();
        _currentUser = null;
        return AuthResult(success: false, message: _blockedAccountMessage);
      }

      _currentUser = user;
      await DatabaseService.instance.logActivity(
        user.username,
        profileResult.created ? 'Inscription' : 'Connexion',
        profileResult.created
            ? 'Nouveau compte Google cree et active.'
            : 'Utilisateur connecte avec Google.',
      );

      if (profileResult.created) {
        final now = DateTime.now();
        TelegramService.instance.isConfigured().then((isConfig) {
          if (isConfig) {
            TelegramService.instance.sendMessage(
              "**Nouvelle inscription Google**\n"
              "- Nom d'utilisateur : ${user.username}\n"
              "- Statut : Actif\n"
              "- Date : ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}",
            );
          }
        });
      }

      return AuthResult(
        success: true,
        message: 'Connexion Google reussie.',
        user: user,
      );
    } on firebase_auth.FirebaseAuthException catch (e) {
      return AuthResult(success: false, message: _googleErrorMessage(e));
    } on _ProfileException catch (e) {
      await _auth.signOut().catchError((_) {});
      await _googleSignIn.signOut().catchError((_) => null);
      _currentUser = null;
      return AuthResult(success: false, message: e.message);
    } on PlatformException catch (e) {
      return AuthResult(
        success: false,
        message: _googlePlatformErrorMessage(e),
      );
    } catch (_) {
      return AuthResult(
        success: false,
        message: 'Connexion Google impossible. Veuillez reessayer.',
      );
    }
  }

  Future<AuthResult> changePassword(
    String username,
    String oldPassword,
    String newPassword,
  ) async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) {
      return AuthResult(success: false, message: 'Aucune session active.');
    }

    final passwordRegex = RegExp(r'^(?=.*[A-Z])(?=.*\d).{8,}$');
    if (!passwordRegex.hasMatch(newPassword)) {
      return AuthResult(
        success: false,
        message:
            'Le nouveau mot de passe doit faire au moins 8 caracteres et contenir au moins 1 majuscule et 1 chiffre.',
      );
    }

    try {
      final credential = firebase_auth.EmailAuthProvider.credential(
        email: _usernameToEmail(username),
        password: oldPassword,
      );
      await firebaseUser.reauthenticateWithCredential(credential);
      await firebaseUser.updatePassword(newPassword);

      await DatabaseService.instance.logActivity(
        username,
        'Changement MDP',
        'Mot de passe modifie avec succes.',
      );

      return AuthResult(
        success: true,
        message: 'Mot de passe modifie avec succes.',
        user: _currentUser,
      );
    } on firebase_auth.FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        return AuthResult(
          success: false,
          message: 'Ancien mot de passe incorrect.',
        );
      }
      return AuthResult(
        success: false,
        message: 'Modification du mot de passe impossible.',
      );
    } catch (_) {
      return AuthResult(
        success: false,
        message: 'Modification du mot de passe impossible.',
      );
    }
  }

  Future<void> logout() async {
    final user = _currentUser;
    if (user != null) {
      await DatabaseService.instance.logActivity(
        user.username,
        'Deconnexion',
        'Utilisateur deconnecte.',
      );
    }
    _currentUser = null;
    await _auth.signOut();
    await _googleSignIn.signOut();
  }

  Future<User?> checkSession() async {
    final firebaseUser =
        _auth.currentUser ?? await _auth.authStateChanges().first;

    if (firebaseUser == null) {
      _currentUser = null;
      return null;
    }

    final profileResult = await _loadOrCreateUserProfile(firebaseUser);
    final user = profileResult.user;
    if (user.status == 'blocked') {
      await _auth.signOut();
      _currentUser = null;
      return null;
    }

    _currentUser = user;
    return user;
  }

  Future<_ProfileLoadResult> _loadOrCreateUserProfile(
    firebase_auth.User firebaseUser, {
    String? username,
    String? provider,
  }) async {
    final doc = _usersCollection.doc(firebaseUser.uid);
    try {
      final snapshot = await doc.get();

      if (snapshot.exists) {
        return _ProfileLoadResult(
          user: _userFromFirestore(
            firebaseUser.uid,
            snapshot.data() ?? {},
            displayName: firebaseUser.displayName,
            email: firebaseUser.email,
          ),
          created: false,
        );
      }

      final profileUsername = _profileUsername(
        firebaseUser,
        fallbackUsername: username,
      );
      final profileData = <String, dynamic>{
        'username': profileUsername,
        if (firebaseUser.email != null) 'email': firebaseUser.email,
        'role': 'user',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      };
      if (provider != null) {
        profileData['provider'] = provider;
      }
      await doc.set(profileData);

      return _ProfileLoadResult(
        user: User(
          id: firebaseUser.uid,
          username: profileUsername,
          passwordHash: '',
          role: 'user',
          status: 'active',
          createdAt: DateTime.now(),
        ),
        created: true,
      );
    } on FirebaseException catch (e) {
      throw _ProfileException(_profileReadWriteErrorMessage(e));
    }
  }

  String _googleUsername(
    firebase_auth.User firebaseUser,
    GoogleSignInAccount googleUser,
  ) {
    final displayName = firebaseUser.displayName ?? googleUser.displayName;
    if (displayName != null && displayName.trim().isNotEmpty) {
      return displayName.trim();
    }

    final email = firebaseUser.email ?? googleUser.email;
    return email.split('@').first;
  }

  String _profileUsername(
    firebase_auth.User firebaseUser, {
    String? fallbackUsername,
  }) {
    final candidates = [
      fallbackUsername,
      firebaseUser.displayName,
      firebaseUser.email?.split('@').first,
    ];

    for (final candidate in candidates) {
      final value = candidate?.trim();
      if (value != null && value.isNotEmpty) return value;
    }

    return 'Utilisateur';
  }

  User _userFromFirestore(
    String uid,
    Map<String, dynamic> data, {
    String? displayName,
    String? email,
  }) {
    final username =
        (data['username'] as String?) ??
        displayName ??
        (email == null ? 'Utilisateur' : email.split('@').first);

    return User(
      id: uid,
      username: username,
      passwordHash: '',
      role: (data['role'] as String?) ?? 'user',
      status: (data['status'] as String?) ?? 'active',
      createdAt: _readCreatedAt(data['createdAt']),
    );
  }

  DateTime _readCreatedAt(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  String _loginErrorMessage(firebase_auth.FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'Utilisateur introuvable.';
      case 'wrong-password':
      case 'invalid-credential':
        return "Nom d'utilisateur ou mot de passe incorrect.";
      case 'too-many-requests':
        return 'Trop de tentatives. Veuillez reessayer plus tard.';
      case 'invalid-email':
        return "Nom d'utilisateur invalide.";
      case 'operation-not-allowed':
        return "L'authentification par email/mot de passe n'est pas active dans Firebase.";
      case 'user-disabled':
        return 'Ce compte a ete desactive.';
      case 'network-request-failed':
        return 'Connexion internet requise. Verifiez le reseau et reessayez.';
      default:
        return 'Connexion impossible. Veuillez reessayer.';
    }
  }

  String _registerErrorMessage(firebase_auth.FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return "Nom d'utilisateur deja pris.";
      case 'invalid-email':
        return "Nom d'utilisateur invalide.";
      case 'weak-password':
        return 'Le mot de passe est trop faible.';
      case 'network-request-failed':
        return 'Connexion internet requise. Verifiez le reseau et reessayez.';
      default:
        return 'Creation du compte impossible. Veuillez reessayer.';
    }
  }

  String _googleErrorMessage(firebase_auth.FirebaseAuthException e) {
    switch (e.code) {
      case 'account-exists-with-different-credential':
        return 'Un compte existe deja avec cette adresse email.';
      case 'network-request-failed':
        return 'Connexion internet requise. Verifiez le reseau et reessayez.';
      case 'popup-closed-by-user':
      case 'canceled':
        return 'Connexion Google annulee.';
      default:
        return 'Connexion Google impossible. Veuillez reessayer.';
    }
  }

  String _profileWriteErrorMessage(Object error) {
    if (error is FirebaseException) {
      return _profileReadWriteErrorMessage(error);
    }

    return 'Creation du compte impossible. Veuillez reessayer.';
  }

  String _profileReadWriteErrorMessage(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return "Acces Firestore refuse. Publiez les regles Firestore du projet et verifiez que le document users/{uid} est lisible par son proprietaire.";
      case 'unavailable':
        return 'Firestore est indisponible. Verifiez la connexion internet et reessayez.';
      case 'not-found':
        return 'La base Firestore du projet Firebase est introuvable ou non initialisee.';
      default:
        return 'Profil Firebase impossible a charger. Verifiez la configuration Firestore.';
    }
  }

  String _googlePlatformErrorMessage(PlatformException e) {
    final rawMessage = '${e.code} ${e.message ?? ''} ${e.details ?? ''}';
    if (rawMessage.contains('10') || e.code == 'sign_in_failed') {
      return "Connexion Google non configuree pour Android. Ajoutez les empreintes SHA-1/SHA-256 dans Firebase, regenerez google-services.json, puis reinstallez l'app.";
    }
    if (e.code == 'sign_in_canceled') {
      return 'Connexion Google annulee.';
    }

    return 'Connexion Google impossible. Verifiez la configuration Google Sign-In.';
  }

  static const _blockedAccountMessage =
      "Votre compte a ete bloque. Veuillez contacter l'administrateur.";
}

class _ProfileLoadResult {
  final User user;
  final bool created;

  const _ProfileLoadResult({required this.user, required this.created});
}
