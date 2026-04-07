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
  String? _masterKey;
  bool _isVisible = false;
  
  // FCM
  String? _fcmToken;
  String _userId = '';
  final TextEditingController _userIdController = TextEditingController();
  
  // Хранилище ключей для чатов
  Map<String, String> _chatKeys = {};
  String? _selectedChat;
  String _newChatId = '';
  String _textToEncrypt = '';
  String _encryptedResult = '';
  String _textToDecrypt = '';
  String _decryptedResult = '';

  @override
  void initState() {
    super.initState();
    _loadMasterKey();
    _loadChatKeys();
    _setupFCM();
  }

  Future<void> _setupFCM() async {
    // Запрашиваем разрешение
    NotificationSettings settings = await FirebaseMessaging.instance.requestPermission();
    
    // Получаем токен
    String? token = await FirebaseMessaging.instance.getToken();
    setState(() => _fcmToken = token);
    
    // Слушаем уведомления
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Уведомление: ${message.notification?.title} - ${message.notification?.body}');
    });
    
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _openChat(message.data['dialog_id']);
    });
  }
  
  Future<void> _sendTokenToServer() async {
    if (_userId.isEmpty || _fcmToken == null) return;
    
    try {
      final response = await http.post(
        Uri.parse('https://ntpr-backend2.vercel.app/api?action=save-fcm-token'),
        body: {
          'userId': _userId,
          'token': _fcmToken!,
        },
      );
      if (response.statusCode == 200) {
        print('Токен отправлен на сервер');
      } else {
        print('Ошибка отправки токена: ${response.body}');
      }
    } catch (e) {
      print('Ошибка отправки токена: $e');
    }
  }
  
  void _openChat(String? dialogId) {
    // Открываем браузер с чатом
    if (dialogId != null) {
      // можно открыть URL: https://ntpr-gilt.vercel.app/chat?dialog_id=$dialogId
    }
  }

  Future<void> _loadMasterKey() async {
    String? key = await storage.read(key: 'ntpr_master_key');
    if (key == null) {
      key = _generateKey(30);
      await storage.write(key: 'ntpr_master_key', value: key);
    }
    setState(() => _masterKey = key);
  }

  Future<void> _loadChatKeys() async {
    String? keysJson = await storage.read(key: 'ntpr_chat_keys');
    if (keysJson != null) {
      setState(() {
        _chatKeys = Map<String, String>.from(jsonDecode(keysJson));
      });
    }
  }

  Future<void> _saveChatKeys() async {
    await storage.write(key: 'ntpr_chat_keys', value: jsonEncode(_chatKeys));
  }

  String _generateKey(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%^&*()_+-=[]{}|;:,.<>?';
    final random = Random.secure();
    return String.fromCharCodes(
      List.generate(length, (_) => chars.codeUnitAt(random.nextInt(chars.length)))
    );
  }

  void _createChatKey() {
    if (_newChatId.isEmpty) return;
    final key = _generateKey(30);
    setState(() {
      _chatKeys[_newChatId] = key;
      _newChatId = '';
    });
    _saveChatKeys();
  }

  void _deleteChatKey(String chatId) {
    setState(() {
      _chatKeys.remove(chatId);
      if (_selectedChat == chatId) _selectedChat = null;
    });
    _saveChatKeys();
  }

  String _encrypt(String text, String key) {
    List<int> textBytes = utf8.encode(text);
    List<int> keyBytes = utf8.encode(key);
    List<int> encrypted = [];
    
    for (int i = 0; i < textBytes.length; i++) {
      encrypted.add(textBytes[i] ^ keyBytes[i % keyBytes.length]);
    }
    
    return base64.encode(encrypted);
  }

  String _decrypt(String encrypted, String key) {
    List<int> encryptedBytes = base64.decode(encrypted);
    List<int> keyBytes = utf8.encode(key);
    List<int> decrypted = [];
    
    for (int i = 0; i < encryptedBytes.length; i++) {
      decrypted.add(encryptedBytes[i] ^ keyBytes[i % keyBytes.length]);
    }
    
    return utf8.decode(decrypted);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Ntpr Vault'),
          bottom: TabBar(tabs: [
            Tab(text: 'Ключи'),
            Tab(text: 'Шифр'),
            Tab(text: 'Дешифр'),
            Tab(text: 'FCM'),
          ]),
        ),
        body: TabBarView(
          children: [
            // Вкладка управления ключами (без изменений)
            Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text('Мастер-ключ:', style: TextStyle(fontSize: 18)),
                          SizedBox(height: 10),
                          SelectableText(
                            _isVisible ? (_masterKey ?? '...') : '●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●',
                            style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
                          ),
                          SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton(
                                onPressed: () => setState(() => _isVisible = !_isVisible),
                                child: Text(_isVisible ? 'Скрыть' : 'Показать'),
                              ),
                              SizedBox(width: 10),
                              ElevatedButton(
                                onPressed: () async {
                                  await storage.delete(key: 'ntpr_master_key');
                                  await _loadMasterKey();
                                },
                                child: Text('Сбросить'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text('Ключи чатов', style: TextStyle(fontSize: 18)),
                          SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  decoration: InputDecoration(
                                    labelText: 'ID чата',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (value) => _newChatId = value,
                                ),
                              ),
                              SizedBox(width: 10),
                              ElevatedButton(
                                onPressed: _createChatKey,
                                child: Text('Создать'),
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _chatKeys.length,
                              itemBuilder: (context, index) {
                                String chatId = _chatKeys.keys.elementAt(index);
                                String key = _chatKeys[chatId]!;
                                return ListTile(
                                  title: Text('Чат: $chatId'),
                                  subtitle: SelectableText(
                                    _selectedChat == chatId ? key : '●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●',
                                    style: TextStyle(fontSize: 10, fontFamily: 'monospace'),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.visibility),
                                        onPressed: () {
                                          setState(() {
                                            _selectedChat = _selectedChat == chatId ? null : chatId;
                                          });
                                        },
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.delete),
                                        onPressed: () => _deleteChatKey(chatId),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Вкладка шифрования
            Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedChat,
                    hint: Text('Выберите чат'),
                    items: _chatKeys.keys.map((chatId) {
                      return DropdownMenuItem(value: chatId, child: Text(chatId));
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedChat = value),
                  ),
                  SizedBox(height: 20),
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Текст для шифрования',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 5,
                    onChanged: (value) => _textToEncrypt = value,
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      if (_selectedChat != null && _textToEncrypt.isNotEmpty) {
                        String key = _chatKeys[_selectedChat!]!;
                        String encrypted = _encrypt(_textToEncrypt, key);
                        setState(() => _encryptedResult = encrypted);
                      }
                    },
                    child: Text('Зашифровать'),
                  ),
                  SizedBox(height: 20),
                  if (_encryptedResult.isNotEmpty)
                    SelectableText(
                      _encryptedResult,
                      style: TextStyle(fontFamily: 'monospace', fontSize: 10),
                    ),
                ],
              ),
            ),
            // Вкладка дешифрования
            Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedChat,
                    hint: Text('Выберите чат'),
                    items: _chatKeys.keys.map((chatId) {
                      return DropdownMenuItem(value: chatId, child: Text(chatId));
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedChat = value),
                  ),
                  SizedBox(height: 20),
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Текст для дешифрования',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 5,
                    onChanged: (value) => _textToDecrypt = value,
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      if (_selectedChat != null && _textToDecrypt.isNotEmpty) {
                        String key = _chatKeys[_selectedChat!]!;
                        String decrypted = _decrypt(_textToDecrypt, key);
                        setState(() => _decryptedResult = decrypted);
                      }
                    },
                    child: Text('Дешифровать'),
                  ),
                  SizedBox(height: 20),
                  if (_decryptedResult.isNotEmpty)
                    SelectableText(
                      _decryptedResult,
                      style: TextStyle(fontFamily: 'monospace', fontSize: 14),
                    ),
                ],
              ),
            ),
            // Новая вкладка FCM
            Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('FCM Токен:', style: TextStyle(fontSize: 18)),
                  SizedBox(height: 10),
                  SelectableText(
                    _fcmToken ?? 'Не получен',
                    style: TextStyle(fontSize: 10, fontFamily: 'monospace'),
                  ),
                  SizedBox(height: 20),
                  TextField(
                    controller: _userIdController,
                    decoration: InputDecoration(
                      labelText: 'Ваш ID пользователя',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) => _userId = value,
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _sendTokenToServer,
                    child: Text('Сохранить токен на сервере'),
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
