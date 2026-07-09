import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:bcrypt/bcrypt.dart';

class User {
  final String id;
  final String username;
  final String passwordHash;
  final String role; // 'admin' | 'user'
  final String status; // 'pending' | 'active' | 'blocked'
  final DateTime createdAt;
  final int failedAttempts;
  final DateTime? lockoutUntil;
  final bool mustChangePassword;

  User({
    required this.id,
    required this.username,
    required this.passwordHash,
    required this.role,
    required this.status,
    required this.createdAt,
    this.failedAttempts = 0,
    this.lockoutUntil,
    this.mustChangePassword = false,
  });

  User copyWith({
    String? passwordHash,
    String? role,
    String? status,
    int? failedAttempts,
    DateTime? lockoutUntil,
    bool? mustChangePassword,
  }) {
    return User(
      id: id,
      username: username,
      passwordHash: passwordHash ?? this.passwordHash,
      role: role ?? this.role,
      status: status ?? this.status,
      createdAt: createdAt,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockoutUntil: lockoutUntil ?? this.lockoutUntil,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'passwordHash': passwordHash,
    'role': role,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
    'failedAttempts': failedAttempts,
    'lockoutUntil': lockoutUntil?.toIso8601String(),
    'mustChangePassword': mustChangePassword,
  };

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'],
    username: json['username'],
    passwordHash: json['passwordHash'],
    role: json['role'] ?? 'user',
    status: json['status'] ?? 'pending',
    createdAt: DateTime.parse(json['createdAt']),
    failedAttempts: json['failedAttempts'] ?? 0,
    lockoutUntil: json['lockoutUntil'] != null ? DateTime.parse(json['lockoutUntil']) : null,
    mustChangePassword: json['mustChangePassword'] ?? false,
  );
}

class ActivityLog {
  final DateTime timestamp;
  final String username;
  final String action;
  final String details;

  ActivityLog({
    required this.timestamp,
    required this.username,
    required this.action,
    required this.details,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'username': username,
    'action': action,
    'details': details,
  };

  factory ActivityLog.fromJson(Map<String, dynamic> json) => ActivityLog(
    timestamp: DateTime.parse(json['timestamp']),
    username: json['username'],
    action: json['action'],
    details: json['details'],
  );
}

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  List<User> _users = [];
  List<ActivityLog> _logs = [];
  bool _isInitialized = false;

  List<User> get users => List.unmodifiable(_users);
  List<ActivityLog> get logs => List.unmodifiable(_logs);

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final file = await _getDbFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = json.decode(content);
        if (data['users'] != null) {
          _users = (data['users'] as List).map((x) => User.fromJson(x)).toList();
        }
        if (data['logs'] != null) {
          _logs = (data['logs'] as List).map((x) => ActivityLog.fromJson(x)).toList();
        }
      }
      _isInitialized = true;
    } catch (e) {
      _isInitialized = true;
    }
  }

  Future<File> _getDbFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/app_db.json');
  }

  Future<void> save() async {
    final file = await _getDbFile();
    final data = {
      'users': _users.map((u) => u.toJson()).toList(),
      'logs': _logs.map((l) => l.toJson()).toList(),
    };
    await file.writeAsString(json.encode(data));
  }

  bool hasUsers() {
    return _users.isNotEmpty;
  }

  Future<void> createInitialAdmin(String password) async {
    final hashedPassword = BCrypt.hashpw(password, BCrypt.gensalt());
    final adminUser = User(
      id: 'admin_id_${DateTime.now().millisecondsSinceEpoch}',
      username: 'admin',
      passwordHash: hashedPassword,
      role: 'admin',
      status: 'active',
      createdAt: DateTime.now(),
      mustChangePassword: false,
    );

    _users.add(adminUser);
    await save();
    
    await logActivity('system', 'Initialisation', 'Compte administrateur cree par l\'utilisateur.');
  }

  Future<void> logActivity(String username, String action, String details) async {
    final log = ActivityLog(
      timestamp: DateTime.now(),
      username: username,
      action: action,
      details: details,
    );
    _logs.insert(0, log);
    if (_logs.length > 500) {
      _logs = _logs.sublist(0, 500);
    }
    await save();
  }

  Future<void> addUser(User user) async {
    _users.add(user);
    await save();
  }

  Future<void> updateUser(User updatedUser) async {
    final index = _users.indexWhere((u) => u.id == updatedUser.id);
    if (index != -1) {
      _users[index] = updatedUser;
      await save();
    }
  }

  Future<void> deleteUser(String id) async {
    _users.removeWhere((u) => u.id == id);
    await save();
  }

  User? getUserByUsername(String username) {
    try {
      return _users.firstWhere((u) => u.username.toLowerCase() == username.toLowerCase());
    } catch (_) {
      return null;
    }
  }
}
