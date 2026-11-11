import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';
import 'owner_admin_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String name = 'Etrnx User';
  String username = '';
  String about = '';
  String avatarUrl = '';
  String coverUrl = '';
  bool loading = true;
  bool saving = false;
  bool isOwner = false;
  List<Map<String, dynamic>> recentGifts = [];
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!SupabaseConfig.isConfigured) {
      if (mounted) setState(() {
        loading = false;
        error = 'Сервер ещё не настроен. Профиль станет доступен после подключения.';
      });
      return;
    }
    try {
      final db = Supabase.instance.client;
      final user = db.auth.currentUser;
      if (user == null) return;
      final profile = await db.from('profiles')
          .select('display_name, about, avatar_url, cover_url').eq('id', user.id).maybeSingle();
      final handle = await db.from('usernames')
          .select('username').eq('user_id', user.id)
          .eq('is_primary', true).maybeSingle();
      final gifts = await db
          .from('gifts')
          .select('id, serial_number, background_key, symbol_key, model:gift_models(name, rarity)')
          .eq('owner_id', user.id)
          .order('acquired_at', ascending: false)
          .limit(4);
      var ownerAccess = false;
      try {
        ownerAccess = await db.rpc('is_platform_owner') as bool;
      } catch (_) {
        ownerAccess = false;
      }
      if (!mounted) return;
      setState(() {
        name = profile?['display_name'] as String? ?? name;
        about = profile?['about'] as String? ?? '';
        avatarUrl = profile?['avatar_url'] as String? ?? '';
        coverUrl = profile?['cover_url'] as String? ?? '';
        username = handle?['username'] as String? ?? '';
        isOwner = ownerAccess;
        recentGifts = gifts.map((row) => Map<String, dynamic>.from(row)).toList();
        loading = false;
        error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'Не удалось загрузить профиль. Проверь подключение.';
      });
    }
  }

  Future<void> _save(String newName, String newUsername, String newAbout, String newAvatarUrl, String newCoverUrl) async {
    if (!SupabaseConfig.isConfigured) return;
    final db = Supabase.instance.client;
    final user = db.auth.currentUser;
    if (user == null) return;
    setState(() => saving = true);
    try {
      if (newUsername.trim().isNotEmpty) {
        await db.rpc('set_primary_username',
            params: {'username_value': newUsername.trim()});
      }
      await db.from('profiles').update({
        'display_name': newName.trim(),
        'about': newAbout.trim(),
        'avatar_url': newAvatarUrl.trim().isEmpty ? null : newAvatarUrl.trim(),
        'cover_url': newCoverUrl.trim().isEmpty ? null : newCoverUrl.trim(),
      }).eq('id', user.id);
      if (!mounted) return;
      setState(() {
        name = newName.trim();
        about = newAbout.trim();
        avatarUrl = newAvatarUrl.trim();
        coverUrl = newCoverUrl.trim();
        if (newUsername.trim().isNotEmpty) {
          username = newUsername.trim().toLowerCase();
        }
        saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль сохранён на сервере')),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить профиль')),
      );
    }
  }

  Future<void> _edit() async {
    final n = TextEditingController(text: name);
    final u = TextEditingController(text: username);
    final a = TextEditingController(text: about);
    final avatar = TextEditingController(text: avatarUrl);
    final cover = TextEditingController(text: coverUrl);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Редактировать профиль'),
        content: SingleChildScrollView(
          child: Column(children: [
            TextField(controller: n, maxLength: 64,
                decoration: const InputDecoration(labelText: 'Имя')),
            TextField(controller: u, maxLength: 32, autocorrect: false,
                decoration: const InputDecoration(
                    labelText: 'Основной username', prefixText: '@')),
            TextField(controller: a, maxLength: 160,
                decoration: const InputDecoration(labelText: 'О себе')),
            TextField(controller: avatar, keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Ссылка на аватар (https://)')),
            TextField(controller: cover, keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Ссылка на обложку (https://)')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Отмена')),
          FilledButton(
            onPressed: saving ? null : () async {
              if (n.text.trim().isEmpty) return;
              Navigator.pop(dialogContext);
              await _save(n.text, u.text, a.text, avatar.text, cover.text);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    n.dispose();
    u.dispose();
    a.dispose();
    avatar.dispose();
    cover.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (error != null)
          ListTile(
            leading: const Icon(Icons.cloud_off),
            title: Text(error!),
            trailing: IconButton(onPressed: _load,
                icon: const Icon(Icons.refresh)),
          ),
        Container(
          height: 145,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6548D8), Color(0xFF172B65)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            image: coverUrl.isEmpty ? null : DecorationImage(
              image: NetworkImage(coverUrl), fit: BoxFit.cover,
              onError: (_, __) {},
            ),
          ),
          child: coverUrl.isEmpty
              ? const Center(child: Icon(Icons.auto_awesome, size: 55))
              : const SizedBox.expand(),
        ),
        const SizedBox(height: 18),
        Center(
          child: CircleAvatar(
            radius: 48,
            backgroundColor: const Color(0xFF9875FF),
            backgroundImage: avatarUrl.isEmpty ? null : NetworkImage(avatarUrl),
            child: avatarUrl.isEmpty ? const Icon(Icons.person, size: 52) : null,
          ),
        ),
        const SizedBox(height: 12),
        Center(child: Text(name, style: const TextStyle(
            fontSize: 25, fontWeight: FontWeight.bold))),
        if (username.isNotEmpty)
          Center(child: Text('@$username',
              style: const TextStyle(color: Colors.purpleAccent))),
        const SizedBox(height: 8),
        Center(child: Text(about, textAlign: TextAlign.center)),
        const SizedBox(height: 22),
        if (isOwner)
          Card(
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings, color: Colors.purpleAccent),
              title: const Text('Панель владельца'),
              subtitle: const Text('Управление коллекциями и выдачей подарков'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const OwnerAdminPage(),
              )),
            ),
          ),
        FilledButton.icon(
          onPressed: saving ? null : _edit,
          icon: const Icon(Icons.edit),
          label: Text(saving ? 'Сохранение...' : 'Редактировать профиль'),
        ),
        const SizedBox(height: 28),
        const Text('Моя коллекция подарков',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        if (recentGifts.isEmpty)
          const Card(child: ListTile(
            leading: Icon(Icons.card_giftcard, color: Colors.purpleAccent),
            title: Text('Подарков пока нет'),
            subtitle: Text('Полученные подарки появятся здесь'),
          ))
        else
          ...recentGifts.map((gift) {
            final model = gift['model'] is Map
                ? Map<String, dynamic>.from(gift['model'] as Map)
                : <String, dynamic>{};
            final serial = gift['serial_number'];
            final details = [
              if (serial != null) '№$serial',
              if (gift['background_key'] != null) 'Фон: ${gift['background_key']}',
              if (gift['symbol_key'] != null) 'Символ: ${gift['symbol_key']}',
            ].join(' · ');
            return Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF302746),
                  child: Icon(Icons.card_giftcard, color: Color(0xFFB99AFF)),
                ),
                title: Text(model['name'] as String? ?? 'Подарок'),
                subtitle: Text(details.isEmpty ? 'В коллекции' : details),
                trailing: Text(model['rarity'] as String? ?? ''),
              ),
            );
          }),
      ],
    );
  }
}
