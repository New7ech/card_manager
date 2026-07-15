import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:bcrypt/bcrypt.dart';

class User {
  final String id;
  final String username;
  final String passwordHash;
  final String role; // 'admin' | 'user'
  final String status; // 'active' | 'blocked'
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
    status: json['status'] ?? 'active',
    createdAt: DateTime.parse(json['createdAt']),
    failedAttempts: json['failedAttempts'] ?? 0,
    lockoutUntil: json['lockoutUntil'] != null
        ? DateTime.parse(json['lockoutUntil'])
        : null,
    mustChangePassword: json['mustChangePassword'] ?? false,
  );
}

class ActivityLog {
  final DateTime timestamp;
  final String username;
  final String action;
  final String details;
  final int? count;

  ActivityLog({
    required this.timestamp,
    required this.username,
    required this.action,
    required this.details,
    this.count,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'username': username,
    'action': action,
    'details': details,
    'count': count,
  };

  factory ActivityLog.fromJson(Map<String, dynamic> json) => ActivityLog(
    timestamp: DateTime.parse(json['timestamp']),
    username: json['username'],
    action: json['action'],
    details: json['details'],
    count: json['count'] is int ? json['count'] as int : null,
  );
}

class ActivityStats {
  int totalClassement;
  int totalDuplication;
  int totalOcr;
  Map<String, int> classementParUtilisateur;

  ActivityStats({
    this.totalClassement = 0,
    this.totalDuplication = 0,
    this.totalOcr = 0,
    Map<String, int>? classementParUtilisateur,
  }) : classementParUtilisateur = classementParUtilisateur ?? {};

  void record(String username, String action, int count) {
    switch (action) {
      case 'Classement':
        totalClassement += count;
        classementParUtilisateur.update(
          username,
          (value) => value + count,
          ifAbsent: () => count,
        );
        break;
      case 'Duplication':
        totalDuplication += count;
        break;
      case 'OCR':
        totalOcr += count;
        break;
    }
  }

  Map<String, dynamic> toJson() => {
    'totalClassement': totalClassement,
    'totalDuplication': totalDuplication,
    'totalOcr': totalOcr,
    'classementParUtilisateur': classementParUtilisateur,
  };

  factory ActivityStats.fromJson(Map<String, dynamic> json) {
    final rawClassementParUtilisateur = json['classementParUtilisateur'];
    final classementParUtilisateur = <String, int>{};

    if (rawClassementParUtilisateur is Map) {
      rawClassementParUtilisateur.forEach((key, value) {
        classementParUtilisateur[key.toString()] = _readInt(value);
      });
    }

    return ActivityStats(
      totalClassement: _readInt(json['totalClassement']),
      totalDuplication: _readInt(json['totalDuplication']),
      totalOcr: _readInt(json['totalOcr']),
      classementParUtilisateur: classementParUtilisateur,
    );
  }

  factory ActivityStats.fromLogs(Iterable<ActivityLog> logs) {
    final stats = ActivityStats();
    for (final log in logs) {
      final count = log.count;
      if (count != null) {
        stats.record(log.username, log.action, count);
      }
    }
    return stats;
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  List<User> _users = [];
  List<ActivityLog> _logs = [];
  ActivityStats stats = ActivityStats();
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
          _users = (data['users'] as List)
              .map((x) => User.fromJson(x))
              .toList();
        }
        if (data['logs'] != null) {
          _logs = (data['logs'] as List)
              .map((x) => ActivityLog.fromJson(x))
              .toList();
        }
        if (data['stats'] is Map) {
          stats = ActivityStats.fromJson(
            Map<String, dynamic>.from(data['stats'] as Map),
          );
        } else {
          stats = ActivityStats.fromLogs(_logs);
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
      'stats': stats.toJson(),
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

    await logActivity(
      'system',
      'Initialisation',
      'Compte administrateur cree par l\'utilisateur.',
    );
  }

  Future<void> logActivity(
    String username,
    String action,
    String details, {
    int? count,
  }) async {
    final log = ActivityLog(
      timestamp: DateTime.now(),
      username: username,
      action: action,
      details: details,
      count: count,
    );
    _logs.insert(0, log);

    if (count != null) {
      stats.record(username, action, count);
    }

    if (_logs.length > 2000) {
      _logs = _logs.sublist(0, 2000);
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
      return _users.firstWhere(
        (u) => u.username.toLowerCase() == username.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }
}
