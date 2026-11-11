import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

class GiftsPage extends StatefulWidget {
  const GiftsPage({super.key});

  @override
  State<GiftsPage> createState() => _GiftsPageState();
}

class _GiftsPageState extends State<GiftsPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late Future<List<Map<String, dynamic>>> _catalog;
  late Future<List<Map<String, dynamic>>> _owned;
  late Future<List<Map<String, dynamic>>> _history;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _catalog = _loadCatalog();
    _owned = _loadOwned();
    _history = _loadHistory();
  }

  Future<List<Map<String, dynamic>>> _loadCatalog() async {
    if (!SupabaseConfig.isConfigured) return [];
    final rows = await _client
        .from('gift_models')
        .select('id, name, artwork_url, rarity, edition_limit, collection:gift_collections(name)')
        .eq('is_published', true)
        .order('name')
        .limit(100);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> _loadOwned() async {
    if (!SupabaseConfig.isConfigured) return [];
    final rows = await _client
        .from('gifts')
        .select('id, serial_number, background_key, symbol_key, acquired_at, model:gift_models(name, artwork_url, rarity)')
        .eq('owner_id', _client.auth.currentUser!.id)
        .order('acquired_at', ascending: false)
        .limit(200);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> _loadHistory() async {
    if (!SupabaseConfig.isConfigured) return [];
    final userId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('gift_transfers')
        .select('id, transfer_kind, created_at, from_user_id, to_user_id, gift:gifts(serial_number, model:gift_models(name))')
        .or('from_user_id.eq.$userId,to_user_id.eq.$userId')
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _catalog = _loadCatalog();
      _owned = _loadOwned();
      _history = _loadHistory();
    });
    await Future.wait([_catalog, _owned, _history]);
  }

  Widget _historyList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _history,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Не удалось загрузить историю: ${snapshot.error}'),
          ));
        }
        final rows = snapshot.data ?? [];
        if (rows.isEmpty) {
          return const Center(child: Text('История подарков пока пуста'));
        }
        final userId = _client.auth.currentUser!.id;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final row = rows[index];
              final gift = row['gift'] is Map
                  ? Map<String, dynamic>.from(row['gift'] as Map)
                  : <String, dynamic>{};
              final model = gift['model'] is Map
                  ? Map<String, dynamic>.from(gift['model'] as Map)
                  : <String, dynamic>{};
              final incoming = row['to_user_id'] == userId;
              final kind = row['transfer_kind'] as String? ?? 'transfer';
              final label = kind == 'grant'
                  ? 'Выдано владельцем'
                  : kind == 'marketplace'
                      ? 'Маркетплейс'
                      : kind == 'revoke'
                          ? 'Отозвано'
                          : incoming ? 'Получен подарок' : 'Подарок передан';
              final date = DateTime.tryParse(row['created_at'] as String? ?? '');
              return Card(
                child: ListTile(
                  leading: Icon(
                    incoming ? Icons.card_giftcard : Icons.redeem,
                    color: const Color(0xFFB99AFF),
                  ),
                  title: Text(model['name'] as String? ?? 'Подарок'),
                  subtitle: Text('$label · ${date == null ? '' : date.toLocal().toString().substring(0, 16)}'),
                  trailing: gift['serial_number'] == null
                      ? null
                      : Text('№${gift['serial_number']}'),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _loadingList(Future<List<Map<String, dynamic>>> future, {required bool owned}) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Не удалось загрузить подарки: ${snapshot.error}'),
            ),
          );
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          final message = !SupabaseConfig.isConfigured
              ? 'Подключи сервер, чтобы открыть каталог подарков и коллекцию.'
              : owned
                  ? 'Здесь появятся подарки, которые тебе подарили или выдали.'
                  : 'Пока нет опубликованных подарков.';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(owned ? Icons.inventory_2_outlined : Icons.card_giftcard_outlined,
                      size: 48, color: const Color(0xFFB99AFF)),
                  const SizedBox(height: 14),
                  Text(message, textAlign: TextAlign.center),
                ],
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              final model = item['model'] is Map
                  ? Map<String, dynamic>.from(item['model'] as Map)
                  : <String, dynamic>{};
              final collection = item['collection'] is Map
                  ? Map<String, dynamic>.from(item['collection'] as Map)
                  : <String, dynamic>{};
              final name = (owned ? model['name'] : item['name']) as String? ?? 'Подарок';
              final rarity = (owned ? model['rarity'] : item['rarity']) as String? ?? 'regular';
              final imageUrl = (owned ? model['artwork_url'] : item['artwork_url']) as String?;
              final serial = item['serial_number'];
              final subtitle = owned
                  ? 'Серийный номер: ${serial ?? '—'} · ${_rarityLabel(rarity)}'
                  : '${collection['name'] ?? 'Коллекция'} · ${_rarityLabel(rarity)}';
              return Card(
                color: const Color(0xFF202130),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  leading: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF302746),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: imageUrl == null || imageUrl.isEmpty
                        ? const Icon(Icons.card_giftcard, color: Color(0xFFB99AFF), size: 28)
                        : Image.network(imageUrl, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.card_giftcard)),
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(subtitle),
                  trailing: owned ? const Icon(Icons.verified_outlined) : null,
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _rarityLabel(String rarity) {
    switch (rarity) {
      case 'limited':
        return 'Лимитированный';
      case 'rare':
        return 'Редкий';
      case 'epic':
        return 'Эпический';
      case 'legendary':
        return 'Легендарный';
      default:
        return 'Обычный';
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Material(
            color: const Color(0xFF171824),
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabs: const [
                Tab(text: 'Каталог'),
                Tab(text: 'Мои подарки'),
                Tab(text: 'История'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _loadingList(_catalog, owned: false),
                _loadingList(_owned, owned: true),
                _historyList(),
              ],
            ),
          ),
        ],
      );
}
