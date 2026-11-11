import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OwnerAdminPage extends StatefulWidget {
  const OwnerAdminPage({super.key});

  @override
  State<OwnerAdminPage> createState() => _OwnerAdminPageState();
}

class _OwnerAdminPageState extends State<OwnerAdminPage> {
  final _client = Supabase.instance.client;
  late Future<bool> _access;
  late Future<List<Map<String, dynamic>>> _collections;
  late Future<List<Map<String, dynamic>>> _models;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _access = _checkAccess();
    _collections = _loadCollections();
    _models = _loadModels();
  }

  Future<bool> _checkAccess() async =>
      await _client.rpc('is_platform_owner') as bool;

  Future<List<Map<String, dynamic>>> _loadCollections() async {
    final rows = await _client
        .from('gift_collections')
        .select('id, name, description')
        .order('created_at', ascending: false);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> _loadModels() async {
    final rows = await _client
        .from('gift_models')
        .select('id, name, rarity, edition_limit, collection_id')
        .order('created_at', ascending: false);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void _reload() {
    setState(() {
      _collections = _loadCollections();
      _models = _loadModels();
    });
  }

  Future<void> _createCollection() async {
    final name = TextEditingController();
    final description = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Новая коллекция'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, maxLength: 80,
                decoration: const InputDecoration(labelText: 'Название')),
            TextField(controller: description, maxLength: 500,
                decoration: const InputDecoration(labelText: 'Описание')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Создать')),
        ],
      ),
    );
    if (result != true || name.text.trim().isEmpty) {
      name.dispose();
      description.dispose();
      return;
    }
    await _run(() async {
      await _client.rpc('owner_create_gift_collection', params: {
        'collection_name': name.text.trim(),
        'collection_description': description.text.trim(),
      });
    });
    name.dispose();
    description.dispose();
  }

  Future<void> _createModel() async {
    final collections = await _collections;
    if (!mounted) return;
    if (collections.isEmpty) {
      _notice('Сначала создай коллекцию.');
      return;
    }
    final name = TextEditingController();
    final image = TextEditingController();
    final limit = TextEditingController();
    String collectionId = collections.first['id'] as String;
    String rarity = 'regular';
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Новая модель подарка'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, maxLength: 80,
                    decoration: const InputDecoration(labelText: 'Название')),
                DropdownButtonFormField<String>(
                  value: collectionId,
                  decoration: const InputDecoration(labelText: 'Коллекция'),
                  items: collections.map((item) => DropdownMenuItem(
                    value: item['id'] as String,
                    child: Text(item['name'] as String),
                  )).toList(),
                  onChanged: (value) => setDialogState(() => collectionId = value!),
                ),
                DropdownButtonFormField<String>(
                  value: rarity,
                  decoration: const InputDecoration(labelText: 'Редкость'),
                  items: const [
                    DropdownMenuItem(value: 'regular', child: Text('Обычный')),
                    DropdownMenuItem(value: 'limited', child: Text('Лимитированный')),
                    DropdownMenuItem(value: 'rare', child: Text('Редкий')),
                    DropdownMenuItem(value: 'epic', child: Text('Эпический')),
                    DropdownMenuItem(value: 'legendary', child: Text('Легендарный')),
                  ],
                  onChanged: (value) => setDialogState(() => rarity = value!),
                ),
                TextField(controller: image,
                    decoration: const InputDecoration(labelText: 'URL изображения')),
                TextField(controller: limit, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Лимит выпуска (необязательно)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Создать')),
          ],
        ),
      ),
    );
    if (result != true || name.text.trim().isEmpty) {
      name.dispose();
      image.dispose();
      limit.dispose();
      return;
    }
    await _run(() async {
      await _client.rpc('owner_create_gift_model', params: {
        'target_collection': collectionId,
        'model_name': name.text.trim(),
        'image_url': image.text.trim().isEmpty ? null : image.text.trim(),
        'model_rarity': rarity,
        'max_edition': limit.text.trim().isEmpty ? null : int.parse(limit.text.trim()),
      });
    });
    name.dispose();
    image.dispose();
    limit.dispose();
  }

  Future<void> _grantGift() async {
    final models = await _models;
    if (!mounted) return;
    if (models.isEmpty) {
      _notice('Сначала создай модель подарка.');
      return;
    }
    final username = TextEditingController();
    String modelId = models.first['id'] as String;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Выдать подарок'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: username,
                  decoration: const InputDecoration(
                    labelText: 'Username получателя', prefixText: '@')),
              DropdownButtonFormField<String>(
                value: modelId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Подарок'),
                items: models.map((item) => DropdownMenuItem(
                  value: item['id'] as String,
                  child: Text(item['name'] as String, overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (value) => setDialogState(() => modelId = value!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Выдать')),
          ],
        ),
      ),
    );
    if (result != true || username.text.trim().isEmpty) {
      username.dispose();
      return;
    }
    await _run(() async {
      final normalized = username.text.trim().replaceFirst(RegExp(r'^@'), '');
      final profile = await _client.from('usernames')
          .select('user_id').ilike('username', normalized).maybeSingle();
      if (profile == null) throw Exception('Пользователь не найден');
      await _client.rpc('owner_grant_gift', params: {
        'target_user': profile['user_id'],
        'target_model': modelId,
      });
    });
    username.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
      _reload();
      if (mounted) _notice('Готово');
    } catch (error) {
      if (mounted) _notice('Не удалось выполнить действие: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _notice(String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: _access,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError || snapshot.data != true) {
            return Scaffold(
              appBar: AppBar(title: const Text('Панель владельца')),
              body: const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Доступ запрещён. Панель доступна только владельцу проекта.',
                      textAlign: TextAlign.center),
                ),
              ),
            );
          }
          return Scaffold(
            appBar: AppBar(title: const Text('Панель владельца')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Управление подарками',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Создавай коллекции и модели, затем выдавай подарки пользователям. Все операции проверяются сервером.'),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _working ? null : _createCollection,
                  icon: const Icon(Icons.collections_bookmark_outlined),
                  label: const Text('Создать коллекцию'),
                ),
                FilledButton.icon(
                  onPressed: _working ? null : _createModel,
                  icon: const Icon(Icons.card_giftcard),
                  label: const Text('Создать подарок'),
                ),
                FilledButton.icon(
                  onPressed: _working ? null : _grantGift,
                  icon: const Icon(Icons.redeem),
                  label: const Text('Выдать подарок пользователю'),
                ),
                if (_working)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                const SizedBox(height: 20),
                const Text('Коллекции', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _collections,
                  builder: (context, snapshot) {
                    final rows = snapshot.data ?? [];
                    if (rows.isEmpty) return const ListTile(title: Text('Коллекций пока нет'));
                    return Column(children: rows.map((row) => ListTile(
                      leading: const Icon(Icons.collections_bookmark_outlined),
                      title: Text(row['name'] as String),
                      subtitle: Text(row['description'] as String? ?? ''),
                    )).toList());
                  },
                ),
                const SizedBox(height: 12),
                const Text('Модели подарков', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _models,
                  builder: (context, snapshot) {
                    final rows = snapshot.data ?? [];
                    if (rows.isEmpty) return const ListTile(title: Text('Подарков пока нет'));
                    return Column(children: rows.map((row) => ListTile(
                      leading: const Icon(Icons.card_giftcard),
                      title: Text(row['name'] as String),
                      subtitle: Text('${row['rarity']} · лимит: ${row['edition_limit'] ?? 'без лимита'}'),
                    )).toList());
                  },
                ),
              ],
            ),
          );
        },
      );
}
