import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/services/database_service.dart';
import '../core/services/telegram_service.dart';
import '../core/services/auth_service.dart';

class _DashboardUserStats {
  final int activeUsers;
  final int classifiedCards;
  final int duplicatedCards;
  final int ocrCards;
  final List<MapEntry<String, int>> topClassifiers;

  const _DashboardUserStats({
    required this.activeUsers,
    required this.classifiedCards,
    required this.duplicatedCards,
    required this.ocrCards,
    required this.topClassifiers,
  });
}

class _RecentActivityEntry {
  final String username;
  final String action;
  final int count;
  final DateTime timestamp;

  const _RecentActivityEntry({
    required this.username,
    required this.action,
    required this.count,
    required this.timestamp,
  });
}

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _telegramFormKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();
  final _chatIdController = TextEditingController();

  bool _isTestingConnection = false;
  bool _isLoadingConfig = true;

  @override
  void initState() {
    super.initState();
    _loadTelegramConfig();
  }

  Future<void> _loadTelegramConfig() async {
    final config = await TelegramService.instance.getConfig();
    if (mounted) {
      setState(() {
        _tokenController.text = config['token'] ?? '';
        _chatIdController.text = config['chatId'] ?? '';
        _isLoadingConfig = false;
      });
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _chatIdController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade800 : Colors.green.shade800,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // --- ACTIONS UTILISATEUR ---

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      FirebaseFirestore.instance.collection('users');

  Future<void> _handleUnblockUser(User user) async {
    try {
      await _usersCollection.doc(user.id).update({'status': 'active'});
      await DatabaseService.instance.logActivity(
        AuthService.instance.currentUser?.username ?? 'admin',
        'Deblocage',
        'Deblocage de l\'utilisateur : ${user.username}',
      );
      _showSnackBar("Utilisateur '${user.username}' debloque.");
    } catch (_) {
      _showSnackBar(
        "Impossible de mettre a jour '${user.username}'.",
        isError: true,
      );
    }
  }

  Future<void> _handleBlockUser(User user) async {
    if (user.id == AuthService.instance.currentUser?.id) {
      _showSnackBar(
        "Vous ne pouvez pas vous bloquer vous-meme !",
        isError: true,
      );
      return;
    }
    try {
      await _usersCollection.doc(user.id).update({'status': 'blocked'});
      await DatabaseService.instance.logActivity(
        AuthService.instance.currentUser?.username ?? 'admin',
        'Blocage',
        'Blocage de l\'utilisateur : ${user.username}',
      );
      _showSnackBar("Utilisateur '${user.username}' bloque.");
    } catch (_) {
      _showSnackBar("Impossible de bloquer '${user.username}'.", isError: true);
    }
  }

  Future<void> _handleToggleRole(User user) async {
    if (user.id == AuthService.instance.currentUser?.id) {
      _showSnackBar(
        "Vous ne pouvez pas modifier votre propre role !",
        isError: true,
      );
      return;
    }
    final newRole = user.role == 'admin' ? 'user' : 'admin';
    try {
      await _usersCollection.doc(user.id).update({'role': newRole});
      await DatabaseService.instance.logActivity(
        AuthService.instance.currentUser?.username ?? 'admin',
        'Modif Role',
        'Role de ${user.username} change en : $newRole',
      );
      _showSnackBar("Role de '${user.username}' mis a jour : $newRole.");
    } catch (_) {
      _showSnackBar(
        "Impossible de modifier le role de '${user.username}'.",
        isError: true,
      );
    }
  }

  Future<void> _handleDeleteUser(User user) async {
    if (user.id == AuthService.instance.currentUser?.id) {
      _showSnackBar(
        "Vous ne pouvez pas supprimer votre propre compte !",
        isError: true,
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer la suppression'),
        content: Text(
          "Voulez-vous vraiment supprimer l'utilisateur '${user.username}' ?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _usersCollection.doc(user.id).delete();
        await DatabaseService.instance.logActivity(
          AuthService.instance.currentUser?.username ?? 'admin',
          'Suppression',
          'Suppression de l\'utilisateur : ${user.username}',
        );
        _showSnackBar("Utilisateur '${user.username}' supprime.");
      } catch (_) {
        _showSnackBar(
          "Impossible de supprimer '${user.username}'.",
          isError: true,
        );
      }
    }
  }

  // --- ACTIONS TELEGRAM ---

  Future<void> _handleSaveTelegram() async {
    if (!_telegramFormKey.currentState!.validate()) return;
    final token = _tokenController.text.trim();
    final chatId = _chatIdController.text.trim();

    await TelegramService.instance.saveConfig(token, chatId);
    await DatabaseService.instance.logActivity(
      AuthService.instance.currentUser?.username ?? 'admin',
      'Config Telegram',
      'Sauvegarde de la configuration Telegram.',
    );
    _showSnackBar('Configuration Telegram sauvegardee avec succes !');
  }

  Future<void> _handleTestTelegram() async {
    if (!_telegramFormKey.currentState!.validate()) return;
    setState(() {
      _isTestingConnection = true;
    });

    final token = _tokenController.text.trim();
    final chatId = _chatIdController.text.trim();

    final ok = await TelegramService.instance.testConnection(token, chatId);

    setState(() {
      _isTestingConnection = false;
    });

    if (ok) {
      _showSnackBar('Connexion reussie ! Verifiez votre canal/chat Telegram.');
    } else {
      _showSnackBar(
        'Echec de la connexion. Verifiez le Token et le Chat ID.',
        isError: true,
      );
    }
  }

  // --- UI BUILDERS ---

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Panneau d\'Administration'),
          backgroundColor: primary,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.dashboard_rounded), text: 'Tableau de bord'),
              Tab(icon: Icon(Icons.people), text: 'Utilisateurs'),
              Tab(icon: Icon(Icons.telegram), text: 'Telegram'),
              Tab(icon: Icon(Icons.history), text: 'Journal'),
            ],
          ),
        ),
        body: Container(
          color: const Color(0xFFF1F5F9), // Light slate gray background
          child: TabBarView(
            children: [
              _buildDashboardTab(),
              _buildUsersTab(),
              _buildTelegramTab(),
              _buildLogsTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardTab() {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final secondaryColor = Theme.of(context).colorScheme.secondary;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _usersCollection.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Impossible de charger les utilisateurs : ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final dashboardStats = _dashboardStatsFromUsers(snapshot.data!.docs);
        final activeUsers = dashboardStats.activeUsers;
        final classifiedCards = dashboardStats.classifiedCards;
        final duplicatedCards = dashboardStats.duplicatedCards;
        final ocrCards = dashboardStats.ocrCards;
        final topClassifiers = dashboardStats.topClassifiers;
        final activeSubtitle = activeUsers > 1
            ? '$activeUsers utilisateurs actifs'
            : '$activeUsers utilisateur actif';

        return RefreshIndicator(
          onRefresh: () async {
            if (mounted) {
              setState(() {});
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      primaryColor.withValues(alpha: 0.9),
                      primaryColor.withValues(alpha: 0.7),
                      const Color(0xFF0F172A), // Sleek slate dark blue
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                      child: const Icon(
                        Icons.dashboard_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tableau de bord',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            activeSubtitle,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildKpiGrid(
                      activeUsers: activeUsers,
                      classifiedCards: classifiedCards,
                      ocrCards: ocrCards,
                      duplicatedCards: duplicatedCards,
                      primary: primaryColor,
                      secondary: secondaryColor,
                    ),
                    const SizedBox(height: 24),
                    _buildDashboardSectionTitle('🏆 Top classeurs'),
                    const SizedBox(height: 12),
                    if (topClassifiers.isEmpty)
                      _buildEmptyDashboardState(
                        Icons.leaderboard_outlined,
                        'Aucune carte classee pour le moment.',
                      )
                    else
                      ...topClassifiers
                          .take(5)
                          .toList()
                          .asMap()
                          .entries
                          .map(
                            (entry) =>
                                _buildTopClassifierTile(entry.key, entry.value),
                          ),
                    const SizedBox(height: 24),
                    _buildDashboardSectionTitle('Activité récente'),
                    const SizedBox(height: 12),
                    _buildRecentActivitiesSection(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  _DashboardUserStats _dashboardStatsFromUsers(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var activeUsers = 0;
    var classifiedCards = 0;
    var duplicatedCards = 0;
    var ocrCards = 0;
    final topClassifiers = <MapEntry<String, int>>[];

    for (final doc in docs) {
      final data = doc.data();
      if (data['status']?.toString() == 'active') {
        activeUsers++;
      }

      final classement = _readUserStat(data, 'classement');
      classifiedCards += classement;
      duplicatedCards += _readUserStat(data, 'duplication');
      ocrCards += _readUserStat(data, 'ocr');

      if (classement > 0) {
        topClassifiers.add(
          MapEntry(data['username']?.toString() ?? 'Utilisateur', classement),
        );
      }
    }

    topClassifiers.sort((a, b) => b.value.compareTo(a.value));

    return _DashboardUserStats(
      activeUsers: activeUsers,
      classifiedCards: classifiedCards,
      duplicatedCards: duplicatedCards,
      ocrCards: ocrCards,
      topClassifiers: topClassifiers.take(5).toList(),
    );
  }

  int _readUserStat(Map<String, dynamic> data, String key) {
    final rawStats = data['stats'];
    if (rawStats is Map) {
      return _readInt(rawStats[key]);
    }
    return 0;
  }

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Widget _buildRecentActivitiesSection() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('activity_feed')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildEmptyDashboardState(
            Icons.error_outline,
            'Impossible de charger l\'activite recente.',
          );
        }

        if (!snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final activities = snapshot.data!.docs
            .map(_recentActivityFromFirestoreDoc)
            .toList();

        if (activities.isEmpty) {
          return _buildEmptyDashboardState(
            Icons.history,
            'Aucune activite recente.',
          );
        }

        return Column(
          children: activities.map(_buildRecentActivityCard).toList(),
        );
      },
    );
  }

  _RecentActivityEntry _recentActivityFromFirestoreDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();

    return _RecentActivityEntry(
      username: data['username']?.toString() ?? 'Utilisateur',
      action: data['action']?.toString() ?? 'Activite',
      count: _readInt(data['count']),
      timestamp: _readFirestoreDate(data['timestamp']),
    );
  }

  Widget _buildKpiGrid({
    required int activeUsers,
    required int classifiedCards,
    required int ocrCards,
    required int duplicatedCards,
    required Color primary,
    required Color secondary,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        const spacing = 12.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        final cards = [
          _buildKpiCard(
            icon: Icons.people_alt_rounded,
            value: activeUsers.toString(),
            label: 'Utilisateurs actifs',
            color: primary,
          ),
          _buildKpiCard(
            icon: Icons.grid_view_rounded,
            value: classifiedCards.toString(),
            label: 'Cartes classées',
            color: secondary,
          ),
          _buildKpiCard(
            icon: Icons.document_scanner_rounded,
            value: ocrCards.toString(),
            label: 'Cartes scannées (OCR)',
            color: Colors.teal.shade700,
          ),
          _buildKpiCard(
            icon: Icons.copy_all_rounded,
            value: duplicatedCards.toString(),
            label: 'Copies generees',
            color: Colors.orange.shade700,
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards) SizedBox(width: itemWidth, child: card),
          ],
        );
      },
    );
  }

  Widget _buildKpiCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF0F172A),
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildEmptyDashboardState(IconData icon, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey.shade500),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopClassifierTile(int index, MapEntry<String, int> entry) {
    final rank = index + 1;
    String medal;
    if (rank == 1) {
      medal = '🥇';
    } else if (rank == 2) {
      medal = '🥈';
    } else if (rank == 3) {
      medal = '🥉';
    } else {
      medal = '#$rank';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Center(
              child: Text(
                medal,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.key,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                entry.value.toString(),
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                entry.value > 1 ? 'cartes' : 'carte',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivityCard(_RecentActivityEntry activity) {
    final color = _activityColor(activity.action);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(_activityIcon(activity.action), color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        activity.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatLogTimestamp(activity.timestamp),
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _activityDetails(activity),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    activity.action,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _activityDetails(_RecentActivityEntry activity) {
    final count = activity.count;
    switch (activity.action) {
      case 'Classement':
        return count > 1 ? '$count cartes classees.' : '$count carte classee.';
      case 'Duplication':
        return count > 1 ? '$count copies generees.' : '$count copie generee.';
      case 'OCR':
        return count > 1 ? '$count cartes scannees.' : '$count carte scannee.';
      default:
        return count > 0 ? '$count element(s) traites.' : 'Activite traitee.';
    }
  }

  IconData _activityIcon(String action) {
    switch (action) {
      case 'Classement':
        return Icons.grid_view_rounded;
      case 'Duplication':
        return Icons.copy_all_rounded;
      case 'OCR':
        return Icons.document_scanner_rounded;
      case 'Connexion':
        return Icons.login_rounded;
      case 'Deconnexion':
        return Icons.logout_rounded;
      case 'Blocage':
        return Icons.block_rounded;
      case 'Inscription':
        return Icons.person_add_alt_1_rounded;
      case 'Deblocage':
      case 'Approbation':
        return Icons.check_circle_rounded;
      default:
        return Icons.history_rounded;
    }
  }

  Color _activityColor(String action) {
    final scheme = Theme.of(context).colorScheme;
    switch (action) {
      case 'Classement':
        return scheme.primary;
      case 'OCR':
        return scheme.secondary;
      case 'Duplication':
        return Colors.orange.shade700;
      case 'Blocage':
        return Colors.red.shade700;
      case 'Inscription':
      case 'Deblocage':
      case 'Approbation':
        return Colors.teal.shade700;
      default:
        return Colors.blueGrey.shade700;
    }
  }

  String _formatLogTimestamp(DateTime timestamp) {
    return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')} '
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  User _userFromFirestoreDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    return User(
      id: doc.id,
      username: data['username']?.toString() ?? 'Utilisateur',
      passwordHash: '',
      role: data['role']?.toString() ?? 'user',
      status: data['status']?.toString() ?? 'active',
      createdAt: _readFirestoreDate(data['createdAt']),
    );
  }

  DateTime _readFirestoreDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  Widget _buildUsersTab() {
    final currentUser = AuthService.instance.currentUser;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _usersCollection.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Impossible de charger les utilisateurs : ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allUsers = snapshot.data!.docs.map(_userFromFirestoreDoc).toList()
          ..sort(
            (a, b) =>
                a.username.toLowerCase().compareTo(b.username.toLowerCase()),
          );

        if (allUsers.isEmpty) {
          return const Center(child: Text('Aucun utilisateur disponible.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: allUsers.length,
          itemBuilder: (context, index) {
            final user = allUsers[index];
            final isSelf = user.id == currentUser?.id;

            Color statusColor;
            IconData statusIcon;
            switch (user.status) {
              case 'active':
                statusColor = Colors.green;
                statusIcon = Icons.check_circle_outline;
                break;
              case 'blocked':
                statusColor = Colors.red;
                statusIcon = Icons.block_outlined;
                break;
              default:
                statusColor = Colors.orange;
                statusIcon = Icons.hourglass_empty_outlined;
                break;
            }

            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: user.role == 'admin'
                                    ? Colors.purple.shade100
                                    : Colors.blue.shade100,
                                child: Icon(
                                  user.role == 'admin'
                                      ? Icons.security
                                      : Icons.person,
                                  color: user.role == 'admin'
                                      ? Colors.purple.shade900
                                      : Colors.blue.shade900,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            user.username,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                        if (isSelf) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade800,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'Vous',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    Text(
                                      'Role: ${user.role.toUpperCase()}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(statusIcon, color: statusColor, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                user.status.toUpperCase(),
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Cree le : ${user.createdAt.day.toString().padLeft(2, '0')}/${user.createdAt.month.toString().padLeft(2, '0')}/${user.createdAt.year}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          children: [
                            if (user.status == 'blocked')
                              IconButton(
                                icon: const Icon(
                                  Icons.check,
                                  color: Colors.green,
                                ),
                                tooltip: 'Debloquer',
                                onPressed: () => _handleUnblockUser(user),
                              ),
                            if (user.status == 'active' && !isSelf)
                              IconButton(
                                icon: const Icon(
                                  Icons.block,
                                  color: Colors.orange,
                                ),
                                tooltip: 'Bloquer',
                                onPressed: () => _handleBlockUser(user),
                              ),
                            if (!isSelf) ...[
                              IconButton(
                                icon: const Icon(
                                  Icons.admin_panel_settings,
                                  color: Colors.purple,
                                ),
                                tooltip: 'Changer le role',
                                onPressed: () => _handleToggleRole(user),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                tooltip: 'Supprimer',
                                onPressed: () => _handleDeleteUser(user),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTelegramTab() {
    if (_isLoadingConfig) {
      return const Center(child: CircularProgressIndicator());
    }

    final primary = Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _telegramFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.telegram, color: Colors.blue, size: 28),
                        SizedBox(width: 8),
                        Text(
                          'Configuration Bot Telegram',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Renseignez ici le Token et le Chat ID du bot Telegram pour l\'envoi automatique et silencieux des rapports. Les donnees sont chiffrees sur votre appareil.',
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _tokenController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Bot Token',
                        hintText: 'Ex: 123456789:ABCdefGhIJKlmNoPQ...',
                        prefixIcon: const Icon(Icons.vpn_key_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (v) =>
                          v!.isEmpty ? 'Veuillez renseigner le token' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _chatIdController,
                      decoration: InputDecoration(
                        labelText: 'Chat ID / Canal ID',
                        hintText: 'Ex: -100123456789 ou 987654321',
                        prefixIcon: const Icon(Icons.chat_bubble_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (v) =>
                          v!.isEmpty ? 'Veuillez renseigner le chat ID' : null,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: _isTestingConnection
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.bolt),
                            label: const Text('Tester la connexion'),
                            onPressed: _isTestingConnection
                                ? null
                                : _handleTestTelegram,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.save),
                            label: const Text('Sauvegarder'),
                            onPressed: _handleSaveTelegram,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Note : Le Bot Telegram doit etre ajoute prealablement comme administrateur du canal ou membre du chat pour que les messages soient distribues.',
                    style: TextStyle(fontSize: 12, color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsTab() {
    final logs = DatabaseService.instance.logs;

    if (logs.isEmpty) {
      return const Center(child: Text('Aucun log d\'activite disponible.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        final timeStr =
            '${log.timestamp.day.toString().padLeft(2, '0')}/${log.timestamp.month.toString().padLeft(2, '0')} '
            '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}';

        return Card(
          elevation: 1,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            dense: true,
            leading: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  timeStr,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            title: Row(
              children: [
                Text(
                  log.username,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    log.action,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(log.details),
            ),
          ),
        );
      },
    );
  }
}
