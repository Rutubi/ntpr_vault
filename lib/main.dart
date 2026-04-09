import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  _handleSilentPush(message.data);
}

void _handleSilentPush(Map<String, dynamic> data) async {
  if (data['type'] == 'chat_key') {
    final storage = FlutterSecureStorage();
    String? keysJson = await storage.read(key: 'ntpr_chat_keys');
    Map<String, dynamic> keys = keysJson != null ? jsonDecode(keysJson) : {};
    
    keys[data['dialog_id']] = data['key'];
    await storage.write(key: 'ntpr_chat_keys', value: jsonEncode(keys));
  }
}

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
      theme: ThemeData.dark(),
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
  
  // Логин
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isActivated = false;
  String? _userId;
  
  // Ключи чатов
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
    
    // Обработка silent push в foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.data['type'] == 'chat_key') {
        _saveReceivedKey(message.data['dialog_id'], message.data['key']);
      }
    });
    
    // Обработка при открытии приложения
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (message.data['type'] == 'chat_key') {
        _saveReceivedKey(message.data['dialog_id'], message.data['key']);
      }
    });
  }
  
  Future<void> _saveReceivedKey(String dialogId, String key) async {
    setState(() {
      _chatKeys[dialogId] = key;
    });
    await storage.write(key: 'ntpr_chat_keys', value: jsonEncode(_chatKeys));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ключ для чата $dialogId сохранён'))
    );
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
        
        // Отправляем FCM токен на сервер
        if (_fcmToken != null) {
          await http.post(
            Uri.parse('https://ntpr-backend2.vercel.app/api?action=save-fcm-token'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': userId, 'token': _fcmToken})
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

  String _generateKey(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%^&*()_+-=[]{}|;:,.<>?';
    final random = Random.secure();
    return String.fromCharCodes(
      List.generate(length, (_) => chars.codeUnitAt(random.nextInt(chars.length)))
    );
  }

  void _createChatKey() {
    showDialog(
      context: context,
      builder: (context) {
        String chatId = '';
        return AlertDialog(
          title: Text('Создать ключ чата'),
          content: TextField(
            decoration: InputDecoration(labelText: 'ID чата'),
            onChanged: (value) => chatId = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Отмена')
            ),
            ElevatedButton(
              onPressed: () {
                if (chatId.isNotEmpty) {
                  final key = _generateKey(30);
                  setState(() {
                    _chatKeys[chatId] = key;
                  });
                  storage.write(key: 'ntpr_chat_keys', value: jsonEncode(_chatKeys));
                  Navigator.pop(context);
                }
              },
              child: Text('Создать')
            ),
          ],
        );
      },
    );
  }

  void _deleteChatKey(String chatId) {
    setState(() {
      _chatKeys.remove(chatId);
    });
    storage.write(key: 'ntpr_chat_keys', value: jsonEncode(_chatKeys));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Ntpr Vault'),
          bottom: TabBar(tabs: [
            Tab(text: 'Уведомления'),
            Tab(text: 'Шифрование'),
          ]),
        ),
        body: TabBarView(
          children: [
            // Вкладка Уведомления (Активация)
            Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isActivated ? Icons.check_circle : Icons.notifications_off,
                    size: 80,
                    color: _isActivated ? Colors.green : Colors.grey,
                  ),
                  SizedBox(height: 20),
                  Text(
                    _isActivated ? 'Уведомления активированы' : 'Уведомления не активированы',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 10),
                  if (_isActivated && _userId != null)
                    Text('ID: $_userId', style: TextStyle(color: Colors.grey)),
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
                    Text('FCM токен:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    SizedBox(height: 5),
                    SelectableText(
                      _fcmToken!,
                      style: TextStyle(fontSize: 10, fontFamily: 'monospace'),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
            
            // Вкладка Шифрование (Ключи чатов)
            Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  ElevatedButton.icon(
                    onPressed: _createChatKey,
                    icon: Icon(Icons.add),
                    label: Text('Создать ключ чата'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size(double.infinity, 50),
                    ),
                  ),
                  SizedBox(height: 20),
                  Expanded(
                    child: _chatKeys.isEmpty
                      ? Center(child: Text('Нет ключей чатов'))
                      : ListView.builder(
                          itemCount: _chatKeys.length,
                          itemBuilder: (context, index) {
                            String chatId = _chatKeys.keys.elementAt(index);
                            String key = _chatKeys[chatId]!;
                            return Card(
                              child: ListTile(
                                title: Text('Чат: $chatId'),
                                subtitle: Text(
                                  key.length > 20 ? '${key.substring(0, 20)}...' : key,
                                  style: TextStyle(fontFamily: 'monospace', fontSize: 10),
                                ),
                                trailing: IconButton(
                                  icon: Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _deleteChatKey(chatId),
                                ),
                              ),
                            );
                          },
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
