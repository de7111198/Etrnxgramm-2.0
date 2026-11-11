import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  late Future<List<Map<String, dynamic>>> _chats;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _chats = _loadChats();
  }

  Future<List<Map<String, dynamic>>> _loadChats() async {
    final userId = _client.auth.currentUser!.id;
    final memberships = await _client
        .from('chat_members')
        .select('chat_id')
        .eq('user_id', userId);
    final ids = memberships.map((row) => row['chat_id'] as String).toList();
    if (ids.isEmpty) return [];
    final rows = await _client
        .from('chats')
        .select('id, kind, title, updated_at')
        .inFilter('id', ids)
        .order('updated_at', ascending: false);
    return rows;
  }

  void _reload() => setState(() => _chats = _loadChats());

  Future<void> _startChat() async {
    final controller = TextEditingController();
    final username = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Новый диалог'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Имя пользователя',
            prefixText: '@',
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Найти'),
          ),
        ],
      ),
    );
    final normalized = username?.trim().replaceFirst(RegExp(r'^@'), '');
    if (normalized == null || normalized.isEmpty || !mounted) return;

    try {
      final result = await _client
          .from('usernames')
          .select('user_id')
          .ilike('username', normalized)
          .maybeSingle();
      if (result == null) throw Exception('Пользователь не найден');
      final chatId = await _client.rpc(
        'create_direct_chat',
        params: {'target_user': result['user_id']},
      );
      if (!mounted) return;
      _reload();
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ChatThreadPage(chatId: chatId as String, title: '@$normalized'),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть диалог: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _startChat,
        tooltip: 'Новый диалог',
        child: const Icon(Icons.edit),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _chats,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(children: [
                const SizedBox(height: 100),
                Center(child: Text('Не удалось загрузить чаты: ${snapshot.error}')),
              ]);
            }
            final chats = snapshot.data ?? [];
            if (chats.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 110),
                Icon(Icons.forum_outlined, size: 52, color: Color(0xFFB99AFF)),
                SizedBox(height: 14),
                Center(child: Text('Чатов пока нет',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Нажми кнопку ✎, чтобы найти пользователя по @username и начать диалог.',
                      textAlign: TextAlign.center),
                ),
              ]);
            }
            return ListView.builder(
              itemCount: chats.length,
              itemBuilder: (context, index) {
                final chat = chats[index];
                final isDirect = chat['kind'] == 'direct';
                final title = isDirect ? 'Личный чат' : (chat['title'] as String? ?? 'Группа');
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF302746),
                    child: Icon(isDirect ? Icons.person_outline : Icons.groups_outlined),
                  ),
                  title: Text(title),
                  subtitle: Text(isDirect ? 'Откройте диалог' : 'Групповой чат'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => ChatThreadPage(chatId: chat['id'] as String, title: title),
                  )),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class ChatThreadPage extends StatefulWidget {
  const ChatThreadPage({super.key, required this.chatId, required this.title});

  final String chatId;
  final String title;

  @override
  State<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends State<ChatThreadPage> {
  final _controller = TextEditingController();
  bool _sending = false;

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _client.rpc('send_chat_message', params: {
        'target_chat': widget.chatId,
        'message_text': text,
      });
      _controller.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Сообщение не отправлено: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = _client.auth.currentUser!.id;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _client
                  .from('messages')
                  .stream(primaryKey: ['id'])
                  .eq('chat_id', widget.chatId)
                  .order('created_at'),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Ошибка загрузки: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data!;
                if (messages.isEmpty) {
                  return const Center(child: Text('Пока нет сообщений. Напиши первым!'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final mine = message['sender_id'] == userId;
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 300),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: mine ? const Color(0xFF59458A) : const Color(0xFF252633),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(message['body'] as String),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Сообщение',
                        filled: true,
                        fillColor: const Color(0xFF252633),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
