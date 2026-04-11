import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

const String API_URL = 'https://ntpr-backend2.vercel.app';
const String WEB_APP_URL = 'https://ntpr-gilt.vercel.app';

// ========== ФОНОВЫЙ ОБРАБОТЧИК FCM ==========
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  
  final storage = FlutterSecureStorage();
  final data = message.data;
  
  if (data['type'] == 'chat_key') {
    String? keysJson = await storage.read(key: 'ntpr_chat_keys');
    Map<String, dynamic> keys = keysJson != null ? jsonDecode(keysJson) : {};
    keys[data['dialog_id']] = data['key'];
    await storage.write(key: 'ntpr_chat_keys', value: jsonEncode(keys));
  }
  
  if (data['type'] == 'request_vault_key') {
    final key = _generateKey();
    String? keysJson = await storage.read(key: 'ntpr_chat_keys');
    Map<String, dynamic> keys = keysJson != null ? jsonDecode(keysJson) : {};
    keys[data['dialog_id']] = key;
    await storage.write(key: 'ntpr_chat_keys', value: jsonEncode(keys));
    
    await _sendKeyViaBackend(data['receiver_id'], data['dialog_id'], key, null);
  }
}

String _generateKey() {
  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%^&*()_+-=[]{}|;:,.<>?';
  final random = Random.secure();
  return String.fromCharCodes(List.generate(30, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
}

Future<void> _sendKeyViaBackend(String receiverId, String dialogId, String key, String? senderId) async {
  try {
    final storage = FlutterSecureStorage();
    final userId = senderId ?? await storage.read(key: 'ntpr_user_id');
    
    await http.post(
      Uri.parse('$API_URL/api?action=send-chat-key'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'dialog_id': dialogId,
        'sender_id': userId,
        'receiver_id': receiverId,
        'chat_key': key
      })
    );
  } catch (e) {
    print('Error sending key: $e');
  }
}

// ========== ГЛАВНОЕ ПРИЛОЖЕНИЕ ==========
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
      home: ActivationScreen(),
    );
  }
}

// ========== ЭКРАН АКТИВАЦИИ ==========
class ActivationScreen extends StatefulWidget {
  @override
  _ActivationScreenState createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final storage = FlutterSecureStorage();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String? _fcmToken;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _setupFCM();
    _checkActivation();
  }

  Future<void> _setupFCM() async {
    await FirebaseMessaging.instance.requestPermission();
    String? token = await FirebaseMessaging.instance.getToken();
    setState(() => _fcmToken = token);
  }

  Future<void> _checkActivation() async {
    String? userId = await storage.read(key: 'ntpr_user_id');
    if (userId != null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => VaultWebView()));
    }
  }

  Future<void> _activate() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    
    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Введите логин и пароль')));
      return;
    }
    
    setState(() => _loading = true);
    
    try {
      final response = await http.post(
        Uri.parse('$API_URL/api?action=login'),
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
            Uri.parse('$API_URL/api?action=save-fcm-token'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': userId, 'token': _fcmToken, 'client_type': 'vault'})
          );
        }
        
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => VaultWebView()));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Неверный логин или пароль')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка соединения')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Активация Vault'), centerTitle: true),
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 80, color: Colors.blue),
            SizedBox(height: 40),
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(labelText: 'Логин', border: OutlineInputBorder()),
              enabled: !_loading,
            ),
            SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(labelText: 'Пароль', border: OutlineInputBorder()),
              obscureText: true,
              enabled: !_loading,
            ),
            SizedBox(height: 32),
            ElevatedButton(
              onPressed: _loading ? null : _activate,
              style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 50), backgroundColor: Colors.blue),
              child: _loading ? CircularProgressIndicator() : Text('АКТИВИРОВАТЬ', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}

// ========== WEBVIEW С VAULT ==========
class VaultWebView extends StatefulWidget {
  @override
  _VaultWebViewState createState() => _VaultWebViewState();
}

class _VaultWebViewState extends State<VaultWebView> {
  WebViewController? _webViewController;
  final storage = FlutterSecureStorage();
  Map<String, String> _chatKeys = {};
  String? _userId;

  @override
  void initState() {
    super.initState();
    _loadData();
    _setupFCM();
  }

  Future<void> _loadData() async {
    String? keysJson = await storage.read(key: 'ntpr_chat_keys');
    if (keysJson != null) {
      _chatKeys = Map<String, String>.from(jsonDecode(keysJson));
    }
    _userId = await storage.read(key: 'ntpr_user_id');
    setState(() {});
  }

  Future<void> _setupFCM() async {
    FirebaseMessaging.onMessage.listen((message) {
      final data = message.data;
      
      if (data['type'] == 'chat_key') {
        _saveKey(data['dialog_id'], data['key']);
      }
      
      if (data['type'] == 'request_vault_key') {
        _handleCreateKey(data['dialog_id'], data['receiver_id']);
      }
    });
  }

  Future<void> _saveKey(String dialogId, String key) async {
    setState(() => _chatKeys[dialogId] = key);
    await storage.write(key: 'ntpr_chat_keys', value: jsonEncode(_chatKeys));
  }

  Future<void> _handleCreateKey(String dialogId, String receiverId) async {
    if (_chatKeys.containsKey(dialogId)) {
      await _sendKeyViaBackend(receiverId, dialogId, _chatKeys[dialogId]!);
      return;
    }
    
    final key = _generateKey();
    await _saveKey(dialogId, key);
    await _sendKeyViaBackend(receiverId, dialogId, key);
  }

  Future<void> _sendKeyViaBackend(String receiverId, String dialogId, String key) async {
    try {
      await http.post(
        Uri.parse('$API_URL/api?action=send-chat-key'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'dialog_id': dialogId,
          'sender_id': _userId,
          'receiver_id': receiverId,
          'chat_key': key
        })
      );
    } catch (e) {
      print('Error sending key: $e');
    }
  }

  String _generateKey() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%^&*()_+-=[]{}|;:,.<>?';
    final random = Random.secure();
    return String.fromCharCodes(List.generate(30, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
  }

  String _encrypt(String text, String key) {
    List<int> encrypted = [];
    for (int i = 0; i < text.length; i++) {
      encrypted.add(text.codeUnitAt(i) ^ key.codeUnitAt(i % key.length));
    }
    return base64.encode(encrypted);
  }

  String _decrypt(String encrypted, String key) {
    try {
      List<int> bytes = base64.decode(encrypted);
      List<int> decrypted = [];
      for (int i = 0; i < bytes.length; i++) {
        decrypted.add(bytes[i] ^ key.codeUnitAt(i % key.length));
      }
      return String.fromCharCodes(decrypted);
    } catch (e) {
      return '';
    }
  }

  Future<String> _handleWebRequest(String request) async {
    try {
      final data = jsonDecode(request);
      final action = data['action'];
      final dialogId = data['dialog_id']?.toString();
      final requestId = data['request_id'];
      
      if (action == 'decrypt') {
        final text = data['text'];
        final key = _chatKeys[dialogId];
        if (key == null) return jsonEncode({'request_id': requestId, 'error': 'no_key', 'text': ''});
        final decrypted = _decrypt(text, key);
        return jsonEncode({'request_id': requestId, 'text': decrypted});
      }
      
      if (action == 'encrypt') {
        final text = data['text'];
        final key = _chatKeys[dialogId];
        if (key == null) return jsonEncode({'request_id': requestId, 'error': 'no_key', 'text': text});
        final encrypted = _encrypt(text, key);
        return jsonEncode({'request_id': requestId, 'text': encrypted});
      }
      
      if (action == 'has_key') {
        return jsonEncode({'request_id': requestId, 'has_key': _chatKeys.containsKey(dialogId)});
      }
      
      if (action == 'deactivate') {
        await storage.delete(key: 'ntpr_user_id');
        await storage.delete(key: 'ntpr_username');
        await storage.delete(key: 'ntpr_chat_keys');
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ActivationScreen()));
        return jsonEncode({'request_id': requestId, 'success': true});
      }
      
      return jsonEncode({'request_id': requestId, 'error': 'unknown_action'});
    } catch (e) {
      return jsonEncode({'error': e.toString()});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: WebView(
        initialUrl: WEB_APP_URL,
        javascriptMode: JavascriptMode.unrestricted,
        onWebViewCreated: (controller) => _webViewController = controller,
        javascriptChannels: {
          JavascriptChannel(
            name: 'VaultBridge',
            onMessageReceived: (JavascriptMessage message) async {
              final response = await _handleWebRequest(message.message);
              _webViewController?.runJavascript("window.vaultCallback($response);");
            },
          ),
        },
      ),
    );
  }
}
