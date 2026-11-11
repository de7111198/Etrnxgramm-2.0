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

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _catalog = _loadCatalog();
    _owned = _loadOwned();
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

  Future<void> _refresh() async {
    setState(() {
      _catalog = _loadCatalog();
      _owned = _loadOwned();
    });
    await Future.wait([_catalog, _owned]);
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
              tabs: const [
                Tab(text: 'Каталог'),
                Tab(text: 'Мои подарки'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _loadingList(_catalog, owned: false),
                _loadingList(_owned, owned: true),
              ],
            ),
          ),
        ],
      );
}
