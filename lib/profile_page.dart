import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String name = 'Etrnx User';
  String username = '';
  String about = '';
  bool loading = true;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = Supabase.instance.client;
      final user = db.auth.currentUser;
      if (user == null) return;
      final profile = await db.from('profiles')
          .select('display_name, about').eq('id', user.id).maybeSingle();
      final handle = await db.from('usernames')
          .select('username').eq('user_id', user.id)
          .eq('is_primary', true).maybeSingle();
      if (!mounted) return;
      setState(() {
        name = profile?['display_name'] as String? ?? name;
        about = profile?['about'] as String? ?? '';
        username = handle?['username'] as String? ?? '';
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

  Future<void> _save(String newName, String newUsername, String newAbout) async {
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
      }).eq('id', user.id);
      if (!mounted) return;
      setState(() {
        name = newName.trim();
        about = newAbout.trim();
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
              await _save(n.text, u.text, a.text);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    n.dispose();
    u.dispose();
    a.dispose();
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
          ),
          child: const Center(child: Icon(Icons.auto_awesome, size: 55)),
        ),
        const SizedBox(height: 18),
        const Center(child: CircleAvatar(
          radius: 48, backgroundColor: Color(0xFF9875FF),
          child: Icon(Icons.person, size: 52),
        )),
        const SizedBox(height: 12),
        Center(child: Text(name, style: const TextStyle(
            fontSize: 25, fontWeight: FontWeight.bold))),
        if (username.isNotEmpty)
          Center(child: Text('@$username',
              style: const TextStyle(color: Colors.purpleAccent))),
        const SizedBox(height: 8),
        Center(child: Text(about, textAlign: TextAlign.center)),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: saving ? null : _edit,
          icon: const Icon(Icons.edit),
          label: Text(saving ? 'Сохранение...' : 'Редактировать профиль'),
        ),
        const SizedBox(height: 28),
        const Text('Моя коллекция подарков',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Card(child: ListTile(
          leading: Icon(Icons.card_giftcard, color: Colors.purpleAccent),
          title: Text('Подарков пока нет'),
          subtitle: Text('Полученные подарки появятся здесь'),
        )),
      ],
    );
  }
}
