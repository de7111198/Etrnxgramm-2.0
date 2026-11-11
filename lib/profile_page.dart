import 'package:flutter/material.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String name = 'Etrnx User';
  String username = 'etrnx';
  String about = 'Добро пожаловать в Etrnxgram!';
  int cover = 0;

  final covers = [
    [const Color(0xFF6548D8), const Color(0xFF172B65)],
    [const Color(0xFFCE579A), const Color(0xFF573AAB)],
    [const Color(0xFF168D91), const Color(0xFF173B68)],
    [const Color(0xFFE18B42), const Color(0xFF7B345E)],
  ];

  void editProfile() {
    final nameController = TextEditingController(text: name);
    final usernameController = TextEditingController(text: username);
    final aboutController = TextEditingController(text: about);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Редактировать профиль'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Имя'),
              ),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              TextField(
                controller: aboutController,
                decoration: const InputDecoration(labelText: 'О себе'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                name = nameController.text;
                username = usernameController.text;
                about = aboutController.text;
              });
              Navigator.pop(context);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          height: 145,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: covers[cover],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Center(
            child: Icon(Icons.auto_awesome, size: 55),
          ),
        ),
        const SizedBox(height: 18),
        const Center(
          child: CircleAvatar(
            radius: 48,
            backgroundColor: Color(0xFF9875FF),
            child: Icon(Icons.person, size: 52),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Center(
          child: Text(
            '@$username',
            style: const TextStyle(color: Colors.purpleAccent),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: Text(about, textAlign: TextAlign.center)),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: editProfile,
          icon: const Icon(Icons.edit),
          label: const Text('Редактировать профиль'),
        ),
        const SizedBox(height: 20),
        const Text(
          'Выбрать обложку',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          children: List.generate(covers.length, (index) {
            return GestureDetector(
              onTap: () => setState(() => cover = index),
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: covers[index]),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: cover == index ? Colors.white : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 28),
        const Text(
          'Моя коллекция подарков',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Card(
          child: ListTile(
            leading: Icon(Icons.card_giftcard, color: Colors.purpleAccent),
            title: Text('Подарков пока нет'),
            subtitle: Text('Полученные подарки появятся здесь'),
          ),
        ),
      ],
    );
  }
}
