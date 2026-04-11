import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;

// ========== ФОНОВЫЙ ОБРАБОТЧИК ==========
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  _handleSilentPush(message.data);
}

void _handleSilentPush(Map<String, dynamic> data) async {
  final storage = FlutterSecureStorage();
  
  // Получение ключа от собеседника
  if (data['type'] == 'chat_key') {
    String? keysJson = await storage.read(key: 'ntpr_chat_keys');
    Map<String, dynamic> keys = keysJson != null ? jsonDecode(keysJson) : {};
    
    keys[data['dialog_id']] = data['key'];
    await storage.write(key: 'ntpr_chat_keys', value: jsonEncode(keys));
  }
  
  // Запрос на создание ключа от веба
  if (data['type'] == 'request_vault_key') {
    final key = _generateKey(30);
    
    String? keysJson = await storage.read(key: 'ntpr_chat_keys');
    Map<String, dynamic> keys = keysJson != null ? jsonDecode(keysJson) : {};
    
    keys[data['dialog_id']] = key;
    await storage.write(key: 'ntpr_chat_keys', value: jsonEncode(keys));
    
    // Отправляем ключ собеседнику
    await _sendKeyToReceiver(data['dialog_id'], data['receiver_id'], key);
  }
}

String _generateKey(int length) {
  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%^&*()_+-=[]{}|;:,.<>?';
  final random = Random.secure();
  return String.fromCharCodes(
    List.generate(length, (_) => chars.codeUnitAt(random.nextInt(chars.length)))
  );
}

Future<void> _sendKeyToReceiver(String dialogId, String receiverId, String key) async {
  try {
    final storage = FlutterSecureStorage();
    String? userId = await storage.read(key: 'ntpr_user_id');
    
    await http.post(
      Uri.parse('https://ntpr-backend2.vercel.app/api?action=send-chat-key'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'dialog_id': dialogId,
        'sender_id': userId,
        'receiver_id': receiverId,
        'chat_key': key
      })
    );
  } catch (e) {
    print('Failed to send key: $e');
  }
}

// ========== ГЛАВНЫЙ ЭКРАН ==========
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(NtprVault());
}

class NtprVault extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ntpr Vault',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blue,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final storage = FlutterSecureStorage();
  String? _fcmToken;
  
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isActivated = false;
  String? _userId;
  
  Map<String, String> _chatKeys = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _setupFCM();
    _loadChatKeys();
    _checkActivation();
  }

  Future<void> _setupFCM() async {
    await FirebaseMessaging.instance.requestPermission();
    String? token = await FirebaseMessaging.instance.getToken();
    setState(() => _fcmToken = token);
    
    // Обработка входящих сообщений когда приложение открыто
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.data['type'] == 'chat_key') {
        _saveReceivedKey(message.data['dialog_id'], message.data['key']);
      }
      if (message.data['type'] == 'request_vault_key') {
        _handleCreateKeyRequest(message.data['dialog_id'], message.data['receiver_id']);
      }
    });
    
    // Обработка при открытии из уведомления
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (message.data['type'] == 'chat_key') {
        _saveReceivedKey(message.data['dialog_id'], message.data['key']);
      }
    });
  }
  
  Future<void> _handleCreateKeyRequest(String dialogId, String receiverId) async {
    final key = _generateKey(30);
    
    setState(() {
      _chatKeys[dialogId] = key;
    });
    await storage.write(key: 'ntpr_chat_keys', value: jsonEncode(_chatKeys));
    
    await _sendKeyToReceiver(dialogId, receiverId, key);
  }
  
  String _generateKey(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%^&*()_+-=[]{}|;:,.<>?';
    final random = Random.secure();
    return String.fromCharCodes(
      List.generate(length, (_) => chars.codeUnitAt(random.nextInt(chars.length)))
    );
  }
  
  Future<void> _sendKeyToReceiver(String dialogId, String receiverId, String key) async {
    try {
      await http.post(
        Uri.parse('https://ntpr-backend2.vercel.app/api?action=send-chat-key'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'dialog_id': dialogId,
          'sender_id': _userId,
          'receiver_id': receiverId,
          'chat_key': key
        })
      );
    } catch (e) {
      print('Failed to send key: $e');
    }
  }
  
  Future<void> _saveReceivedKey(String dialogId, String key) async {
    setState(() {
      _chatKeys[dialogId] = key;
    });
    await storage.write(key: 'ntpr_chat_keys', value: jsonEncode(_chatKeys));
  }

  Future<void> _loadChatKeys() async {
    String? keysJson = await storage.read(key: 'ntpr_chat_keys');
    if (keysJson != null) {
      setState(() {
        _chatKeys = Map<String, String>.from(jsonDecode(keysJson));
      });
    }
    setState(() => _isLoading = false);
  }
  
  Future<void> _checkActivation() async {
    String? userId = await storage.read(key: 'ntpr_user_id');
    if (userId != null) {
      setState(() {
        _isActivated = true;
        _userId = userId;
      });
    }
  }

  Future<void> _activate() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    
    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Введите логин и пароль'))
      );
      return;
    }
    
    try {
      final response = await http.post(
        Uri.parse('https://ntpr-backend2.vercel.app/api?action=login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password})
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final userId = data['user']['id'].toString();
        
        await storage.write(key: 'ntpr_user_id', value: userId);
        await storage.write(key: 'ntpr_username', value: username);
        
        if (_fcmToken != null) {
          await http.post(
            Uri.parse('https://ntpr-backend2.vercel.app/api?action=save-fcm-token'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': userId, 'token': _fcmToken, 'client_type': 'vault'})
          );
        }
        
        setState(() {
          _isActivated = true;
          _userId = userId;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Активировано!'))
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Неверный логин или пароль'))
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка соединения'))
      );
    }
  }
  
  Future<void> _deactivate() async {
    await storage.delete(key: 'ntpr_user_id');
    await storage.delete(key: 'ntpr_username');
    setState(() {
      _isActivated = false;
      _userId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Ntpr Vault'),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isActivated ? Icons.check_circle : Icons.lock_outline,
              size: 80,
              color: _isActivated ? Colors.green : Colors.blue,
            ),
            SizedBox(height: 20),
            Text(
              _isActivated ? 'Vault активирован' : 'Vault не активирован',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            if (_isActivated && _userId != null)
              Text('ID: $_userId', style: TextStyle(color: Colors.grey)),
            if (_chatKeys.isNotEmpty)
              Text('Ключей: ${_chatKeys.length}', style: TextStyle(color: Colors.green)),
            SizedBox(height: 30),
            
            if (!_isActivated) ...[
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Логин',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Пароль',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              SizedBox(height: 24),
              ElevatedButton(
                onPressed: _activate,
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 50),
                  backgroundColor: Colors.blue,
                ),
                child: Text('Активировать', style: TextStyle(fontSize: 18)),
              ),
            ] else ...[
              ElevatedButton(
                onPressed: _deactivate,
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 50),
                  backgroundColor: Colors.red,
                ),
                child: Text('Деактивировать', style: TextStyle(fontSize: 18)),
              ),
            ],
            
            SizedBox(height: 20),
            if (_fcmToken != null) ...[
              Text('Статус: ${_isActivated ? "Активен" : "Не активен"}', 
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }
}
