import 'package:flutter/material.dart';
import '../core/services/database_service.dart';
import '../core/services/telegram_service.dart';
import '../core/services/auth_service.dart';

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

  Future<void> _handleApproveUser(User user) async {
    final db = DatabaseService.instance;
    final updated = user.copyWith(
      status: 'active',
      failedAttempts: 0,
      lockoutUntil: null,
    );
    await db.updateUser(updated);
    await db.logActivity(
      AuthService.instance.currentUser?.username ?? 'admin',
      'Approbation',
      'Approbation de l\'utilisateur : ${user.username}',
    );
    setState(() {});
    _showSnackBar("Utilisateur '${user.username}' approuve.");
  }

  Future<void> _handleBlockUser(User user) async {
    if (user.username == AuthService.instance.currentUser?.username) {
      _showSnackBar("Vous ne pouvez pas vous bloquer vous-meme !", isError: true);
      return;
    }
    final db = DatabaseService.instance;
    final updated = user.copyWith(status: 'blocked');
    await db.updateUser(updated);
    await db.logActivity(
      AuthService.instance.currentUser?.username ?? 'admin',
      'Blocage',
      'Blocage de l\'utilisateur : ${user.username}',
    );
    setState(() {});
    _showSnackBar("Utilisateur '${user.username}' bloque.");
  }

  Future<void> _handleToggleRole(User user) async {
    if (user.username == AuthService.instance.currentUser?.username) {
      _showSnackBar("Vous ne pouvez pas modifier votre propre role !", isError: true);
      return;
    }
    final db = DatabaseService.instance;
    final newRole = user.role == 'admin' ? 'user' : 'admin';
    final updated = user.copyWith(role: newRole);
    await db.updateUser(updated);
    await db.logActivity(
      AuthService.instance.currentUser?.username ?? 'admin',
      'Modif Role',
      'Role de ${user.username} change en : $newRole',
    );
    setState(() {});
    _showSnackBar("Role de '${user.username}' mis a jour : $newRole.");
  }

  Future<void> _handleDeleteUser(User user) async {
    if (user.username == AuthService.instance.currentUser?.username) {
      _showSnackBar("Vous ne pouvez pas supprimer votre propre compte !", isError: true);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer la suppression'),
        content: Text("Voulez-vous vraiment supprimer l'utilisateur '${user.username}' ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = DatabaseService.instance;
      await db.deleteUser(user.id);
      await db.logActivity(
        AuthService.instance.currentUser?.username ?? 'admin',
        'Suppression',
        'Suppression de l\'utilisateur : ${user.username}',
      );
      setState(() {});
      _showSnackBar("Utilisateur '${user.username}' supprime.");
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
      _showSnackBar('Echec de la connexion. Verifiez le Token et le Chat ID.', isError: true);
    }
  }

  // --- UI BUILDERS ---

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Panneau d\'Administration'),
          backgroundColor: primary,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.white,
            tabs: [
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
              _buildUsersTab(),
              _buildTelegramTab(),
              _buildLogsTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUsersTab() {
    final currentUser = AuthService.instance.currentUser;
    final allUsers = DatabaseService.instance.users;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: allUsers.length,
      itemBuilder: (context, index) {
        final user = allUsers[index];
        final isSelf = user.username == currentUser?.username;

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
          case 'pending':
          default:
            statusColor = Colors.orange;
            statusIcon = Icons.hourglass_empty_outlined;
            break;
        }

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: user.role == 'admin' ? Colors.purple.shade100 : Colors.blue.shade100,
                          child: Icon(
                            user.role == 'admin' ? Icons.security : Icons.person,
                            color: user.role == 'admin' ? Colors.purple.shade900 : Colors.blue.shade900,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  user.username,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                if (isSelf) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade800,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'Vous',
                                      style: TextStyle(color: Colors.white, fontSize: 10),
                                    ),
                                  ),
                                ]
                              ],
                            ),
                            Text(
                              'Role: ${user.role.toUpperCase()}',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(statusIcon, color: statusColor, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            user.status.toUpperCase(),
                            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
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
                    Text(
                      'Cree le : ${user.createdAt.day.toString().padLeft(2, '0')}/${user.createdAt.month.toString().padLeft(2, '0')}/${user.createdAt.year}',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    ),
                    Row(
                      children: [
                        if (user.status == 'pending' || user.status == 'blocked')
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.green),
                            tooltip: 'Approuver / Debloquer',
                            onPressed: () => _handleApproveUser(user),
                          ),
                        if (user.status == 'active' && !isSelf)
                          IconButton(
                            icon: const Icon(Icons.block, color: Colors.orange),
                            tooltip: 'Bloquer',
                            onPressed: () => _handleBlockUser(user),
                          ),
                        if (!isSelf) ...[
                          IconButton(
                            icon: const Icon(Icons.admin_panel_settings, color: Colors.purple),
                            tooltip: 'Changer le role',
                            onPressed: () => _handleToggleRole(user),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            tooltip: 'Supprimer',
                            onPressed: () => _handleDeleteUser(user),
                          ),
                        ]
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (v) => v!.isEmpty ? 'Veuillez renseigner le token' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _chatIdController,
                      decoration: InputDecoration(
                        labelText: 'Chat ID / Canal ID',
                        hintText: 'Ex: -100123456789 ou 987654321',
                        prefixIcon: const Icon(Icons.chat_bubble_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (v) => v!.isEmpty ? 'Veuillez renseigner le chat ID' : null,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: _isTestingConnection
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.bolt),
                            label: const Text('Tester la connexion'),
                            onPressed: _isTestingConnection ? null : _handleTestTelegram,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      return const Center(
        child: Text('Aucun log d\'activite disponible.'),
      );
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    log.action,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
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
