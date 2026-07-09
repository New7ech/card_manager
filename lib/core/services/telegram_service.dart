import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class TelegramService {
  static final TelegramService instance = TelegramService._internal();
  TelegramService._internal();

  final _secureStorage = const FlutterSecureStorage();

  Future<void> saveConfig(String token, String chatId) async {
    await _secureStorage.write(key: 'telegram_bot_token', value: token.trim());
    await _secureStorage.write(key: 'telegram_chat_id', value: chatId.trim());
  }

  Future<Map<String, String?>> getConfig() async {
    final token = await _secureStorage.read(key: 'telegram_bot_token');
    final chatId = await _secureStorage.read(key: 'telegram_chat_id');
    return {
      'token': token,
      'chatId': chatId,
    };
  }

  Future<bool> isConfigured() async {
    final config = await getConfig();
    return config['token'] != null &&
        config['token']!.isNotEmpty &&
        config['chatId'] != null &&
        config['chatId']!.isNotEmpty;
  }

  /// Sends a text message silently to the configured chat.
  Future<bool> sendMessage(String text) async {
    try {
      final config = await getConfig();
      final token = config['token'];
      final chatId = config['chatId'];

      if (token == null || chatId == null || token.isEmpty || chatId.isEmpty) {
        return false;
      }

      final url = Uri.parse('https://api.telegram.org/bot$token/sendMessage');
      final response = await http.post(
        url,
        body: {
          'chat_id': chatId,
          'text': text,
          'disable_notification': 'true', // Silent send
        },
      );

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Sends a file (like PDF) silently to the configured chat.
  Future<bool> sendDocument(File file, String caption) async {
    try {
      final config = await getConfig();
      final token = config['token'];
      final chatId = config['chatId'];

      if (token == null || chatId == null || token.isEmpty || chatId.isEmpty) {
        return false;
      }

      if (!await file.exists()) {
        return false;
      }

      final url = Uri.parse('https://api.telegram.org/bot$token/sendDocument');
      final request = http.MultipartRequest('POST', url)
        ..fields['chat_id'] = chatId
        ..fields['caption'] = caption
        ..fields['disable_notification'] = 'true'
        ..files.add(await http.MultipartFile.fromPath('document', file.path));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Tests the Telegram bot token and chat ID configuration by sending a test message.
  Future<bool> testConnection(String token, String chatId) async {
    try {
      if (token.isEmpty || chatId.isEmpty) return false;

      final url = Uri.parse('https://api.telegram.org/bot$token/sendMessage');
      final response = await http.post(
        url,
        body: {
          'chat_id': chatId,
          'text': 'Connexion de test reussie depuis le Gestionnaire de Cartes ! 🛡️',
        },
      );

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
