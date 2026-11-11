import 'package:flutter/material.dart';
import 'profile_page.dart';

void main() {
  runApp(const EtrnxgramApp());
}

class EtrnxgramApp extends StatelessWidget {
  const EtrnxgramApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Etrnxgram',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF10111A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF9875FF),
          secondary: Color(0xFFB58AFF),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int selected = 0;

  static const pages = <Widget>[
    ChatsPage(),
    GiftsPage(),
    ContactsPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF171824),
        title: const Text(
          'Etrnxgram',
          style: TextStyle(
            color: Color(0xFFB99AFF),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: IndexedStack(index: selected, children: pages),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF171824),
        selectedIndex: selected,
        onDestinationSelected: (index) => setState(() => selected = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Чаты',
          ),
          NavigationDestination(
            icon: Icon(Icons.card_giftcard),
            label: 'Подарки',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            label: 'Контакты',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }
}

class ChatsPage extends StatelessWidget {
  const ChatsPage({super.key});

  @override
  Widget build(BuildContext context) => const _EmptySection(
        icon: Icons.forum_outlined,
        title: 'Чатов пока нет',
        message: 'Когда появятся реальные диалоги, они будут показаны здесь.',
      );
}

class GiftsPage extends StatelessWidget {
  const GiftsPage({super.key});

  @override
  Widget build(BuildContext context) => const _EmptySection(
        icon: Icons.card_giftcard_outlined,
        title: 'Подарки',
        message: 'Коллекция подарков пока не подключена к серверу.',
      );
}

class ContactsPage extends StatelessWidget {
  const ContactsPage({super.key});

  @override
  Widget build(BuildContext context) => const _EmptySection(
        icon: Icons.people_outline,
        title: 'Контакты',
        message: 'Список контактов появится после подключения аккаунтов.',
      );
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: const Color(0xFFB99AFF)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
