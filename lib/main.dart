import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:math';
import 'dart:convert';

void main() => runApp(NtprVault());

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
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Ntpr Vault'),
          bottom: TabBar(tabs: [
            Tab(text: 'Ключи'),
            Tab(text: 'Шифр'),
            Tab(text: 'Дешифр'),
          ]),
        ),
        body: TabBarView(
          children: [
            // Вкладка управления ключами
            Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  // Мастер-ключ
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
                  // Создание ключа для чата
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
          ],
        ),
      ),
    );
  }
}
