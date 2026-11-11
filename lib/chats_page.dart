import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  late Future<List<Map<String, dynamic>>> _chats;
  bool _showArchived = false;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _chats = SupabaseConfig.isConfigured ? _loadChats() : Future.value([]);
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

    final membershipsForChats = await _client
        .from('chat_members')
        .select('chat_id, user_id')
        .inFilter('chat_id', ids)
        .neq('user_id', userId);
    final otherUserIds = membershipsForChats
        .map((row) => row['user_id'] as String)
        .toSet()
        .toList();
    final profileRows = otherUserIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await _client
            .from('profiles')
            .select('id, display_name')
            .inFilter('id', otherUserIds);
    final usernameRows = otherUserIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await _client
            .from('usernames')
            .select('user_id, username')
            .inFilter('user_id', otherUserIds)
            .eq('is_primary', true);

    final names = <String, String>{
      for (final row in profileRows)
        row['id'] as String: (row['display_name'] as String?) ?? 'Пользователь',
    };
    final usernames = <String, String>{
      for (final row in usernameRows)
        row['user_id'] as String: row['username'] as String,
    };
    final otherByChat = <String, List<String>>{};
    for (final row in membershipsForChats) {
      otherByChat.putIfAbsent(row['chat_id'] as String, () => [])
          .add(row['user_id'] as String);
    }

    final settings = await _client
        .from('chat_user_settings')
        .select('chat_id, archived_at, muted_until')
        .eq('user_id', userId)
        .inFilter('chat_id', ids);
    final archivedIds = settings
        .where((row) => row['archived_at'] != null)
        .map((row) => row['chat_id'] as String)
        .toSet();
    final mutedIds = settings.where((row) {
      final raw = row['muted_until'] as String?;
      return raw != null && DateTime.tryParse(raw)?.isAfter(DateTime.now().toUtc()) == true;
    }).map((row) => row['chat_id'] as String).toSet();

    return rows.map((chat) {
      final result = Map<String, dynamic>.from(chat);
      if (chat['kind'] == 'direct') {
        final others = otherByChat[chat['id']] ?? [];
        final otherId = others.isEmpty ? null : others.first;
        result['display_title'] = otherId == null
            ? 'Личный чат'
            : (names[otherId] ?? 'Пользователь');
        result['display_subtitle'] =
            otherId != null && usernames.containsKey(otherId)
                ? '@${usernames[otherId]}'
                : 'Личный диалог';
      } else {
        result['display_title'] = chat['title'] ?? 'Группа';
        result['display_subtitle'] = chat['kind'] == 'channel' ? 'Канал' : 'Групповой чат';
      }
      result['is_muted'] = mutedIds.contains(chat['id']);
      return result;
    }).where((chat) => archivedIds.contains(chat['id']) == _showArchived).toList();
  }

  Future<void> _setMuted(Map<String, dynamic> chat, bool muted) async {
    try {
      await _client.from('chat_user_settings').upsert({
        'chat_id': chat['id'],
        'user_id': _client.auth.currentUser!.id,
        'muted_until': muted
            ? DateTime.now().toUtc().add(const Duration(hours: 8)).toIso8601String()
            : null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось изменить уведомления: $error')),
      );
    }
  }

  Future<void> _setArchived(Map<String, dynamic> chat, bool archived) async {
    try {
      await _client.from('chat_user_settings').upsert({
        'chat_id': chat['id'],
        'user_id': _client.auth.currentUser!.id,
        'archived_at': archived ? DateTime.now().toUtc().toIso8601String() : null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось изменить архив: $error')),
      );
    }
  }

  void _reload() => setState(() => _chats = _loadChats());

  Future<void> _startGroup() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Новая группа'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Название группы'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.trim().isEmpty || !mounted) return;
    try {
      final chatId = await _client.rpc('create_group_chat', params: {
        'chat_title': title.trim(),
        'member_ids': <String>[],
      });
      if (!mounted) return;
      _reload();
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ChatThreadPage(
          chatId: chatId as String,
          title: title.trim(),
          isGroup: true,
        ),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать группу: $error')),
      );
    }
  }

  Future<void> _startChannel() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Новый канал'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Название канала'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.trim().isEmpty || !mounted) return;
    try {
      final chatId = await _client.rpc('create_channel_chat', params: {
        'channel_title': title.trim(),
        'member_ids': <String>[],
      });
      if (!mounted) return;
      _reload();
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ChatThreadPage(
          chatId: chatId as String,
          title: title.trim(),
          isGroup: true,
          isChannel: true,
        ),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать канал: $error')),
      );
    }
  }

  Future<void> _showCreateOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt_1),
              title: const Text('Новый диалог'),
              onTap: () {
                Navigator.pop(sheetContext);
                _startChat();
              },
            ),
            ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: const Text('Новый канал'),
              onTap: () {
                Navigator.pop(sheetContext);
                _startChannel();
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Новая группа'),
              onTap: () {
                Navigator.pop(sheetContext);
                _startGroup();
              },
            ),
          ],
        ),
      ),
    );
  }

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
        onPressed: _showCreateOptions,
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
              return ListView(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ChoiceChip(
                      label: Text(_showArchived ? 'Архив' : 'Все чаты'),
                      selected: _showArchived,
                      onSelected: (value) {
                        setState(() {
                          _showArchived = value;
                          _reload();
                        });
                      },
                    ),
                  ),
                ),
                SizedBox(height: 100),
                Center(child: Text(_showArchived ? 'Архив пуст' : 'Чатов пока нет',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Нажми кнопку ✎, чтобы найти пользователя по @username и начать диалог.',
                      textAlign: TextAlign.center),
                ),
              ]);
            }
            return ListView.builder(
              itemCount: chats.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ChoiceChip(
                        label: Text(_showArchived ? 'Архив' : 'Все чаты'),
                        selected: _showArchived,
                        onSelected: (value) {
                          setState(() {
                            _showArchived = value;
                            _reload();
                          });
                        },
                      ),
                    ),
                  );
                }
                final chat = chats[index - 1];
                final isDirect = chat['kind'] == 'direct';
                final title = chat['display_title'] as String? ??
                    (isDirect ? 'Личный чат' : (chat['title'] as String? ?? 'Группа'));
                final subtitle = chat['display_subtitle'] as String? ??
                    (isDirect ? 'Личный диалог' : 'Групповой чат');
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF302746),
                    child: Icon(isDirect ? Icons.person_outline : (chat['kind'] == 'channel' ? Icons.campaign_outlined : Icons.groups_outlined)),
                  ),
                  title: Text(title),
                  subtitle: Text(subtitle),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'archive' || value == 'unarchive') {
                        _setArchived(chat, value == 'archive');
                      } else if (value == 'mute' || value == 'unmute') {
                        _setMuted(chat, value == 'mute');
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: chat['is_muted'] == true ? 'unmute' : 'mute',
                        child: Text(chat['is_muted'] == true
                            ? 'Включить уведомления'
                            : 'Отключить на 8 часов'),
                      ),
                      PopupMenuItem(
                        value: _showArchived ? 'unarchive' : 'archive',
                        child: Text(_showArchived ? 'Вернуть из архива' : 'В архив'),
                      ),
                    ],
                  ),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => ChatThreadPage(chatId: chat['id'] as String, title: title, isGroup: !isDirect, isChannel: chat['kind'] == 'channel'),
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
  const ChatThreadPage({super.key, required this.chatId, required this.title, this.isGroup = false, this.isChannel = false});

  final String chatId;
  final String title;
  final bool isGroup;
  final bool isChannel;

  @override
  State<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends State<ChatThreadPage> {
  final _controller = TextEditingController();
  bool _sending = false;
  bool _canPost = false;
  Map<String, dynamic>? _replyTo;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    if (widget.isChannel) _loadPostingPermission();
  }

  Future<void> _loadPostingPermission() async {
    try {
      final row = await _client
          .from('chat_members')
          .select('role')
          .eq('chat_id', widget.chatId)
          .eq('user_id', _client.auth.currentUser!.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() => _canPost =
          row?['role'] == 'owner' || row?['role'] == 'admin');
    } catch (_) {
      if (mounted) setState(() => _canPost = false);
    }
  }





  Future<void> _manageMember(String userId, String action) async {
    final messages = {
      'admin': 'Назначить участника администратором?',
      'member': 'Снять права администратора?',
      'remove': 'Удалить участника из группы?',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Управление участником'),
        content: Text(messages[action]!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      if (action == 'remove') {
        await _client.rpc('remove_chat_member', params: {
          'target_chat': widget.chatId,
          'target_user': userId,
        });
      } else {
        await _client.rpc('set_chat_member_role', params: {
          'target_chat': widget.chatId,
          'target_user': userId,
          'new_role': action,
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Изменения сохранены')),
      );
      _showMembers();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось изменить участника: $error')),
      );
    }
  }

  Future<void> _showMembers() async {
    try {
      final memberships = await _client
          .from('chat_members')
          .select('user_id, role')
          .eq('chat_id', widget.chatId);
      final ids = memberships.map((row) => row['user_id'] as String).toList();
      final profiles = await _client
          .from('profiles')
          .select('id, display_name')
          .inFilter('id', ids);
      final usernames = await _client
          .from('usernames')
          .select('user_id, username')
          .inFilter('user_id', ids)
          .eq('is_primary', true);
      final names = <String, String>{
        for (final row in profiles)
          row['id'] as String: (row['display_name'] as String?) ?? 'Пользователь',
      };
      final handles = <String, String>{
        for (final row in usernames)
          row['user_id'] as String: row['username'] as String,
      };
      if (!mounted) return;
      final currentUserId = _client.auth.currentUser!.id;
      final currentRole = memberships.firstWhere(
        (row) => row['user_id'] == currentUserId,
        orElse: () => <String, dynamic>{'role': 'member'},
      )['role'];
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.65,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Участники группы · ${memberships.length}',
                      style: Theme.of(sheetContext).textTheme.titleLarge),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: memberships.length,
                    itemBuilder: (context, index) {
                      final member = memberships[index];
                      final id = member['user_id'] as String;
                      final role = member['role'] as String;
                      final label = role == 'owner'
                          ? 'Владелец'
                          : role == 'admin' ? 'Администратор' : 'Участник';
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                        title: Text(names[id] ?? 'Пользователь'),
                        subtitle: Text(handles[id] == null
                            ? label
                            : '@${handles[id]} · $label'),
                        trailing: id == currentUserId || role == 'owner'
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (currentRole == 'owner')
                                    TextButton(
                                      onPressed: () async {
                                        Navigator.pop(sheetContext);
                                        final confirmed = await showDialog<bool>(
                                          context: this.context,
                                          builder: (dialogContext) => AlertDialog(
                                            title: const Text('Передать владение?'),
                                            content: Text('Владелец группы изменится на ${names[id] ?? 'этого участника'}.'),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(dialogContext, false),
                                                child: const Text('Отмена'),
                                              ),
                                              FilledButton(
                                                onPressed: () => Navigator.pop(dialogContext, true),
                                                child: const Text('Передать'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirmed != true || !mounted) return;
                                        try {
                                          await _client.rpc('transfer_chat_ownership', params: {
                                            'target_chat': widget.chatId,
                                            'new_owner': id,
                                          });
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(this.context).showSnackBar(
                                            const SnackBar(content: Text('Владение группой передано')),
                                          );
                                        } catch (error) {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(this.context).showSnackBar(
                                            SnackBar(content: Text('Не удалось передать владение: $error')),
                                          );
                                        }
                                      },
                                      child: const Text('Передать'),
                                    ),
                                  if (currentRole == 'owner' ||
                                      (currentRole == 'admin' && role == 'member'))
                                    PopupMenuButton<String>(
                                      onSelected: (action) {
                                        Navigator.pop(sheetContext);
                                        _manageMember(id, action);
                                      },
                                      itemBuilder: (_) => [
                                        if (currentRole == 'owner' && role == 'member')
                                          const PopupMenuItem(
                                            value: 'admin',
                                            child: Text('Назначить администратором'),
                                          ),
                                        if (currentRole == 'owner' && role == 'admin')
                                          const PopupMenuItem(
                                            value: 'member',
                                            child: Text('Снять права администратора'),
                                          ),
                                        if (currentRole == 'owner' || role == 'member')
                                          const PopupMenuItem(
                                            value: 'remove',
                                            child: Text('Удалить из группы'),
                                          ),
                                      ],
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
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить участников: $error')),
      );
    }
  }

  Future<void> _addMember() async {
    final controller = TextEditingController();
    final username = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Добавить участника'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Имя пользователя',
            prefixText: '@',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    controller.dispose();
    final normalized = username?.trim().replaceFirst(RegExp(r'^@'), '');
    if (normalized == null || normalized.isEmpty || !mounted) return;
    try {
      final profile = await _client
          .from('usernames')
          .select('user_id')
          .ilike('username', normalized)
          .maybeSingle();
      if (profile == null) throw Exception('Пользователь не найден');
      await _client.rpc('add_chat_member', params: {
        'target_chat': widget.chatId,
        'new_member': profile['user_id'],
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('@$normalized добавлен(а) в группу')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось добавить участника: $error')),
      );
    }
  }

  Future<void> _showMessageActions(
      Map<String, dynamic> message, bool mine) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Ответить'),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() => _replyTo = message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: const Text('Закрепить'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pinMessage(message, true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.push_pin),
              title: const Text('Открепить'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pinMessage(message, false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward),
              title: const Text('Переслать'),
              onTap: () {
                Navigator.pop(sheetContext);
                _forwardMessage(message);
              },
            ),
            if (mine)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Изменить'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _editMessage(message);
                },
              ),
            if (mine)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Удалить'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deleteMessage(message);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pinMessage(
      Map<String, dynamic> message, bool pin) async {
    try {
      if (pin) {
        await _client.rpc('pin_chat_message', params: {
          'target_message': message['id'],
        });
      } else {
        await _client.rpc('unpin_chat_message', params: {
          'target_chat': widget.chatId,
          'target_message': message['id'],
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(pin ? 'Сообщение закреплено' : 'Сообщение откреплено')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось изменить закрепление: $error')),
      );
    }
  }

  Future<void> _editMessage(Map<String, dynamic> message) async {
    final controller = TextEditingController(text: message['body'] as String? ?? '');
    final replacement = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Изменить сообщение'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          maxLength: 10000,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (replacement == null || replacement.trim().isEmpty) return;
    try {
      await _client.rpc('edit_chat_message', params: {
        'target_message': message['id'],
        'replacement_text': replacement,
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось изменить сообщение: $error')),
      );
    }
  }

  Future<void> _deleteMessage(Map<String, dynamic> message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить сообщение?'),
        content: const Text('Сообщение будет удалено из этого чата.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _client.rpc('delete_chat_message', params: {
        'target_message': message['id'],
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить сообщение: $error')),
      );
    }
  }

  Future<void> _forwardMessage(Map<String, dynamic> message) async {
    try {
      final userId = _client.auth.currentUser!.id;
      final memberships = await _client
          .from('chat_members')
          .select('chat_id')
          .eq('user_id', userId);
      final chatIds = memberships.map((row) => row['chat_id'] as String).toList();
      if (chatIds.isEmpty) return;
      final chats = await _client
          .from('chats')
          .select('id, kind, title')
          .inFilter('id', chatIds)
          .order('updated_at', ascending: false);
      final otherMembers = await _client
          .from('chat_members')
          .select('chat_id, user_id')
          .inFilter('chat_id', chatIds)
          .neq('user_id', userId);
      final otherIds = otherMembers.map((row) => row['user_id'] as String).toSet().toList();
      final profiles = otherIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await _client.from('profiles')
              .select('id, display_name').inFilter('id', otherIds);
      final names = <String, String>{
        for (final row in profiles)
          row['id'] as String: row['display_name'] as String? ?? 'Пользователь',
      };
      final othersByChat = <String, List<String>>{};
      for (final row in otherMembers) {
        othersByChat.putIfAbsent(row['chat_id'] as String, () => [])
            .add(row['user_id'] as String);
      }
      if (!mounted) return;
      final destination = await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Переслать в...'),
          children: chats.map((chat) {
            final id = chat['id'] as String;
            final isDirect = chat['kind'] == 'direct';
            final others = othersByChat[id] ?? [];
            final title = isDirect
                ? (others.isEmpty ? 'Личный чат' : names[others.first] ?? 'Пользователь')
                : (chat['title'] as String? ?? 'Группа');
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, id),
              child: Text(title),
            );
          }).toList(),
        ),
      );
      if (destination == null) return;
      await _client.rpc('forward_chat_message', params: {
        'source_message': message['id'],
        'destination_chat': destination,
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось переслать сообщение: $error')),
      );
    }
  }

  Widget _pinnedBanner() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _client
          .from('chat_pins')
          .stream(primaryKey: ['id'])
          .eq('chat_id', widget.chatId)
          .order('pinned_at', ascending: false),
      builder: (context, snapshot) {
        final pins = snapshot.data ?? [];
        if (pins.isEmpty) return const SizedBox.shrink();
        final pin = pins.first;
        return FutureBuilder<Map<String, dynamic>?>(
          future: _client
              .from('messages')
              .select('body')
              .eq('id', pin['message_id'])
              .maybeSingle(),
          builder: (context, messageSnapshot) {
            final body = messageSnapshot.data?['body'] as String? ?? 'Закреплённое сообщение';
            return Material(
              color: const Color(0xFF302746),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.push_pin, color: Color(0xFFB99AFF)),
                title: const Text('Закреплённое сообщение'),
                subtitle: Text(body, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: 'Открепить',
                  icon: const Icon(Icons.close),
                  onPressed: () => _pinMessage(
                    {'id': pin['message_id']},
                    false,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _toggleReaction(String messageId, String emoji) async {
    try {
      await _client.rpc('toggle_message_reaction', params: {
        'target_message': messageId,
        'reaction_emoji': emoji,
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось поставить реакцию: $error')),
      );
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _client.rpc('send_chat_message', params: {
        'target_chat': widget.chatId,
        'message_text': text,
        'reply_message': _replyTo?['id'],
      });
      _controller.clear();
      if (mounted) setState(() => _replyTo = null);
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
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.isGroup) ...[
            IconButton(
              tooltip: 'Участники группы',
              onPressed: _showMembers,
              icon: const Icon(Icons.people_outline),
            ),
            IconButton(
              tooltip: 'Добавить участника',
              onPressed: _addMember,
              icon: const Icon(Icons.person_add_alt_1),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          _pinnedBanner(),
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
                    final replyId = message['reply_to'] as String?;
                    final replied = replyId == null ? null : messages.cast<Map<String, dynamic>?>().firstWhere(
                      (item) => item?['id'] == replyId,
                      orElse: () => null,
                    );
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: () => _showMessageActions(message, mine),
                        child: Container(
                        constraints: const BoxConstraints(maxWidth: 300),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: mine ? const Color(0xFF59458A) : const Color(0xFF252633),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (replied != null)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  replied['body'] as String,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                                ),
                              ),
                            if (message['forwarded_from'] != null)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 4),
                                child: Text('Пересланное сообщение', style: TextStyle(fontSize: 11, color: Colors.white70)),
                              ),
                            Text(message['body'] as String),
                            if (message['edited_at'] != null)
                              const Align(
                                alignment: Alignment.centerRight,
                                child: Text('изменено', style: TextStyle(fontSize: 10, color: Colors.white60)),
                              ),
                            const SizedBox(height: 6),
                            StreamBuilder<List<Map<String, dynamic>>>(
                              stream: _client
                                  .from('message_reactions')
                                  .stream(primaryKey: ['id'])
                                  .eq('message_id', message['id'] as String),
                              builder: (context, reactionSnapshot) {
                                final rows = reactionSnapshot.data ?? [];
                                final counts = <String, int>{};
                                final mine = <String>{};
                                for (final row in rows) {
                                  final emoji = row['emoji'] as String;
                                  counts[emoji] = (counts[emoji] ?? 0) + 1;
                                  if (row['user_id'] == userId) mine.add(emoji);
                                }
                                const choices = ['👍', '❤️', '😂', '😮', '😢', '🔥', '🎉'];
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (counts.isNotEmpty)
                                      Flexible(
                                        child: Wrap(
                                          spacing: 4,
                                          runSpacing: 2,
                                          children: counts.entries.map((entry) => ActionChip(
                                            visualDensity: VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            label: Text('${entry.key} ${entry.value}'),
                                            backgroundColor: mine.contains(entry.key)
                                                ? const Color(0xFF8065B5)
                                                : const Color(0xFF393442),
                                            onPressed: () => _toggleReaction(
                                              message['id'] as String, entry.key,
                                            ),
                                          )).toList(),
                                        ),
                                      ),
                                    PopupMenuButton<String>(
                                      tooltip: 'Поставить реакцию',
                                      padding: EdgeInsets.zero,
                                      iconSize: 19,
                                      onSelected: (emoji) => _toggleReaction(
                                        message['id'] as String, emoji,
                                      ),
                                      itemBuilder: (_) => choices.map((emoji) =>
                                        PopupMenuItem<String>(
                                          value: emoji,
                                          child: Text(emoji, style: const TextStyle(fontSize: 22)),
                                        ),
                                      ).toList(),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 6),
                                        child: Icon(Icons.add_reaction_outlined, size: 19),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    );
                  },
                );
              },
            ),
          ),
          if (!widget.isChannel || _canPost)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_replyTo != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF302746),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.reply, color: Color(0xFFB99AFF)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ответ: ${_replyTo!['body']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Отменить ответ',
                            onPressed: () => setState(() => _replyTo = null),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                  Row(
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
                ],
              ),
            ),
          ),
          if (widget.isChannel && !_canPost)
            const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('Этот канал доступен для чтения. Публиковать могут только администраторы.'),
              ),
            ),
        ],
      ),
    );
  }
}
