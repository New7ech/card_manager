import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bcrypt/bcrypt.dart';
import 'database_service.dart';
import 'telegram_service.dart';

class AuthResult {
  final bool success;
  final String message;
  final User? user;

  AuthResult({required this.success, required this.message, this.user});
}

class AuthService {
  static final AuthService instance = AuthService._internal();
  AuthService._internal();

  User? _currentUser;
  User? get currentUser => _currentUser;

  final _secureStorage = const FlutterSecureStorage();

  Future<AuthResult> login(String username, String password) async {
    final db = DatabaseService.instance;
    final user = db.getUserByUsername(username);

    if (user == null) {
      return AuthResult(success: false, message: "Utilisateur introuvable.");
    }

    // Check if account is blocked
    if (user.status == 'blocked') {
      return AuthResult(
        success: false,
        message: "Votre compte a ete bloque. Veuillez contacter l'administrateur.",
      );
    }

    // Check if account is pending
    if (user.status == 'pending') {
      return AuthResult(
        success: false,
        message: "Votre compte est en attente d'approbation par l'administrateur.",
      );
    }

    // Check lockout delay
    if (user.lockoutUntil != null && user.lockoutUntil!.isAfter(DateTime.now())) {
      final secondsLeft = user.lockoutUntil!.difference(DateTime.now()).inSeconds;
      return AuthResult(
        success: false,
        message: "Trop de tentatives. Veuillez reessayer dans $secondsLeft secondes.",
      );
    }

    // Verify password
    final passwordMatches = BCrypt.checkpw(password, user.passwordHash);

    if (passwordMatches) {
      // Success
      final updatedUser = user.copyWith(
        failedAttempts: 0,
        lockoutUntil: null,
      );
      await db.updateUser(updatedUser);

      _currentUser = updatedUser;

      // Save session in secure storage (valid for 24h)
      await _secureStorage.write(key: 'session_username', value: username);
      await _secureStorage.write(
        key: 'session_expiry',
        value: DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
      );

      await db.logActivity(username, 'Connexion', 'Utilisateur connecte avec succes.');

      return AuthResult(success: true, message: "Connexion reussie.", user: updatedUser);
    } else {
      // Failure
      final newFailedAttempts = user.failedAttempts + 1;
      User updatedUser;

      if (newFailedAttempts >= 5) {
        // Block account
        updatedUser = user.copyWith(
          failedAttempts: newFailedAttempts,
          status: 'blocked',
          lockoutUntil: null,
        );
        await db.updateUser(updatedUser);
        await db.logActivity(username, 'Blocage', 'Compte bloque suite a 5 tentatives echouees.');
        return AuthResult(
          success: false,
          message: "Mot de passe incorrect. Compte bloque apres 5 tentatives. Contactez l'administrateur.",
        );
      } else {
        // Lock temporarily (progressive delay: attempts * 10 seconds)
        final cooldownSeconds = newFailedAttempts * 10;
        final lockoutUntil = DateTime.now().add(Duration(seconds: cooldownSeconds));

        updatedUser = user.copyWith(
          failedAttempts: newFailedAttempts,
          lockoutUntil: lockoutUntil,
        );
        await db.updateUser(updatedUser);
        await db.logActivity(username, 'Echec Connexion', 'Tentative de connexion echouee ($newFailedAttempts/5).');

        final remaining = 5 - newFailedAttempts;
        return AuthResult(
          success: false,
          message: "Mot de passe incorrect. Tentatives restantes : $remaining. Reessayez dans $cooldownSeconds secondes.",
        );
      }
    }
  }

  Future<AuthResult> register(String username, String password) async {
    if (username.trim().isEmpty) {
      return AuthResult(success: false, message: "Le nom d'utilisateur ne peut pas etre vide.");
    }

    final db = DatabaseService.instance;
    final existingUser = db.getUserByUsername(username);

    if (existingUser != null) {
      return AuthResult(success: false, message: "Nom d'utilisateur deja pris.");
    }

    // Validate password rules (min 8 chars, 1 uppercase, 1 digit)
    final passwordRegex = RegExp(r'^(?=.*[A-Z])(?=.*\d).{8,}$');
    if (!passwordRegex.hasMatch(password)) {
      return AuthResult(
        success: false,
        message: "Le mot de passe doit faire au moins 8 caracteres et contenir au moins 1 majuscule et 1 chiffre.",
      );
    }

    // Hash password
    final hashedPassword = BCrypt.hashpw(password, BCrypt.gensalt());

    final newUser = User(
      id: 'user_id_${DateTime.now().millisecondsSinceEpoch}',
      username: username.trim(),
      passwordHash: hashedPassword,
      role: 'user',
      status: 'pending',
      createdAt: DateTime.now(),
      mustChangePassword: false,
    );

    await db.addUser(newUser);
    await db.logActivity(username, 'Inscription', 'Nouveau compte cree (en attente).');

    // Async send to Telegram
    TelegramService.instance.isConfigured().then((isConfig) {
      if (isConfig) {
        TelegramService.instance.sendMessage(
          "🔔 **Nouvelle inscription d'utilisateur**\n"
          "- Nom d'utilisateur : ${username.trim()}\n"
          "- Statut : En attente de validation ⏳\n"
          "- Date : ${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}\n\n"
          "Veuillez vous connecter au Panneau d'Administration pour valider cet acces."
        );
      }
    });

    return AuthResult(
      success: true,
      message: "Compte cree avec succes. En attente d'approbation par l'administrateur.",
    );
  }

  Future<AuthResult> changePassword(String username, String oldPassword, String newPassword) async {
    final db = DatabaseService.instance;
    final user = db.getUserByUsername(username);

    if (user == null) {
      return AuthResult(success: false, message: "Utilisateur introuvable.");
    }

    // Verify old password
    if (!BCrypt.checkpw(oldPassword, user.passwordHash)) {
      return AuthResult(success: false, message: "Ancien mot de passe incorrect.");
    }

    // Validate new password rules
    final passwordRegex = RegExp(r'^(?=.*[A-Z])(?=.*\d).{8,}$');
    if (!passwordRegex.hasMatch(newPassword)) {
      return AuthResult(
        success: false,
        message: "Le nouveau mot de passe doit faire au moins 8 caracteres et contenir au moins 1 majuscule et 1 chiffre.",
      );
    }

    // Hash new password
    final hashedNewPassword = BCrypt.hashpw(newPassword, BCrypt.gensalt());

    final updatedUser = user.copyWith(
      passwordHash: hashedNewPassword,
      mustChangePassword: false,
    );

    await db.updateUser(updatedUser);
    
    // Clear temp password if it's the admin
    if (username == 'admin') {
      await _secureStorage.delete(key: 'temp_admin_password');
    }

    await db.logActivity(username, 'Changement MDP', 'Mot de passe modifie avec succes.');

    // Update in-memory session if the logged-in user changed their password
    if (_currentUser?.username.toLowerCase() == username.toLowerCase()) {
      _currentUser = updatedUser;
    }

    return AuthResult(success: true, message: "Mot de passe modifie avec succes.");
  }

  Future<void> logout() async {
    if (_currentUser != null) {
      await DatabaseService.instance.logActivity(_currentUser!.username, 'Deconnexion', 'Utilisateur deconnecte.');
    }
    _currentUser = null;
    await _secureStorage.delete(key: 'session_username');
    await _secureStorage.delete(key: 'session_expiry');
  }

  Future<User?> checkSession() async {
    final username = await _secureStorage.read(key: 'session_username');
    final expiryStr = await _secureStorage.read(key: 'session_expiry');

    if (username == null || expiryStr == null) {
      return null;
    }

    final expiry = DateTime.parse(expiryStr);
    if (expiry.isBefore(DateTime.now())) {
      await logout();
      return null;
    }

    // Load user from database
    final db = DatabaseService.instance;
    await db.init();
    final user = db.getUserByUsername(username);

    if (user != null && user.status == 'active') {
      _currentUser = user;
      return user;
    } else {
      await logout();
      return null;
    }
  }
}
