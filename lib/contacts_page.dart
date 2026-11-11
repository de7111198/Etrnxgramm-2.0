import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chats_page.dart';
import 'supabase_config.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  final _searchController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _contacts;
  bool _openingChat = false;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _contacts = SupabaseConfig.isConfigured
        ? _loadContacts()
        : Future.value(<Map<String, dynamic>>[]);
  }

  Future<List<Map<String, dynamic>>> _loadContacts() async {
    final currentUserId = _client.auth.currentUser!.id;
    final query = _searchController.text.trim().replaceFirst(RegExp(r'^@'), '');
    final profileQuery = _client
        .from('profiles')
        .select('id, display_name, about')
        .neq('id', currentUserId);
    final profileRows = query.isEmpty
        ? await profileQuery.order('display_name').limit(50)
        : await profileQuery.ilike('display_name', '%$query%').limit(50);
    final ids = profileRows.map((row) => row['id'] as String).toList();
    final usernameRows = await _client
        .from('usernames')
        .select('user_id, username')
        .eq('is_primary', true)
        .limit(500);
    final usernames = <String, String>{
      for (final row in usernameRows)
        row['user_id'] as String: row['username'] as String,
    };

    var results = profileRows.map((row) {
      final item = Map<String, dynamic>.from(row);
      item['username'] = usernames[item['id']];
      return item;
    }).toList();

    if (query.isNotEmpty) {
      final matchingIds = usernameRows
          .where((row) => (row['username'] as String)
              .toLowerCase()
              .contains(query.toLowerCase()))
          .map((row) => row['user_id'] as String)
          .where((id) => id != currentUserId && !ids.contains(id))
          .toList();
      if (matchingIds.isNotEmpty) {
        final extraProfiles = await _client
            .from('profiles')
            .select('id, display_name, about')
            .inFilter('id', matchingIds);
        results.addAll(extraProfiles.map((row) {
          final item = Map<String, dynamic>.from(row);
          item['username'] = usernames[item['id']];
          return item;
        }));
      }
    }
    results.sort((a, b) => (a['display_name'] as String)
        .toLowerCase()
        .compareTo((b['display_name'] as String).toLowerCase()));
    return results;
  }

  void _search(String _) {
    setState(() => _contacts = _loadContacts());
  }

  Future<void> _openChat(Map<String, dynamic> contact) async {
    if (_openingChat || !SupabaseConfig.isConfigured) return;
    setState(() => _openingChat = true);
    try {
      final chatId = await _client.rpc('create_direct_chat', params: {
        'target_user': contact['id'],
      });
      if (!mounted) return;
      final title = contact['display_name'] as String? ?? 'Личный чат';
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ChatThreadPage(
          chatId: chatId as String,
          title: title,
        ),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть диалог: $error')),
      );
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: _search,
            decoration: InputDecoration(
              hintText: 'Поиск по имени или @username',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: const Color(0xFF252633),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _contacts,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Не удалось загрузить контакты: ${snapshot.error}'),
                  ),
                );
              }
              final contacts = snapshot.data ?? [];
              if (contacts.isEmpty) {
                return Center(
                  child: Text(_searchController.text.trim().isEmpty
                      ? 'Пока нет пользователей'
                      : 'Ничего не найдено'),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => setState(() => _contacts = _loadContacts()),
                child: ListView.separated(
                  itemCount: contacts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                  itemBuilder: (context, index) {
                    final contact = contacts[index];
                    final name = contact['display_name'] as String? ?? 'Пользователь';
                    final username = contact['username'] as String?;
                    final about = (contact['about'] as String?) ?? '';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF302746),
                        child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase()),
                      ),
                      title: Text(name),
                      subtitle: Text(username == null
                          ? (about.isEmpty ? 'Пользователь Etrnxgram' : about)
                          : '@$username'),
                      trailing: const Icon(Icons.chat_bubble_outline),
                      onTap: _openingChat ? null : () => _openChat(contact),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

