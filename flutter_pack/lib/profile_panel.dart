import 'package:flutter/material.dart';
import 'local_store.dart';

class ProfilePanel extends StatefulWidget {
  final LocalStore? store;
  final Account? account;
  final ValueChanged<Account?> onAccountChanged;
  const ProfilePanel({super.key, required this.store, required this.account,
    required this.onAccountChanged});
  @override
  State<ProfilePanel> createState() => _ProfilePanelState();
}

class _ProfilePanelState extends State<ProfilePanel> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final login = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool registering = false;
  bool busy = false;
  bool hidden = true;
  String? error;

  @override
  void dispose() {
    name.dispose(); login.dispose(); password.dispose(); confirmation.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || widget.store == null || !form.currentState!.validate()) return;
    setState(() { busy = true; error = null; });
    try {
      final account = registering
          ? await widget.store!.register(name.text, login.text, password.text)
          : await widget.store!.login(login.text, password.text);
      if (!mounted) return;
      password.clear(); confirmation.clear();
      widget.onAccountChanged(account);
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Не удалось открыть профиль. Попробуй ещё раз.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    return SafeArea(child: ListView(padding: const EdgeInsets.all(24), children: [
      Row(children: [
        const Expanded(child: Text('Профиль', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold))),
        IconButton(tooltip: 'Закрыть профиль', onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close)),
      ]),
      const SizedBox(height: 28),
      const Align(alignment: Alignment.centerLeft, child: CircleAvatar(radius: 34,
        child: Icon(Icons.person_outline, size: 38))),
      const SizedBox(height: 20),
      if (account != null) ...[
        Text('Добро пожаловать, ${account.name}!',
          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Text('Логин: ${account.login}'),
        const SizedBox(height: 24),
        OutlinedButton.icon(onPressed: () {
          widget.onAccountChanged(null);
          setState(() { error = null; registering = false; });
        }, icon: const Icon(Icons.logout), label: const Text('Выйти')),
      ] else ...[
        const Text('Вход необязателен', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Картой и поиском можно пользоваться без аккаунта.'),
        const SizedBox(height: 20),
        SegmentedButton<bool>(segments: const [
          ButtonSegment(value: false, label: Text('Вход')),
          ButtonSegment(value: true, label: Text('Регистрация')),
        ], selected: {registering}, onSelectionChanged: busy ? null : (value) {
          setState(() { registering = value.first; error = null; });
          form.currentState?.reset(); password.clear(); confirmation.clear();
        }),
        const SizedBox(height: 20),
        Form(key: form, child: Column(children: [
          if (registering) ...[
            TextFormField(controller: name, enabled: !busy,
              decoration: const InputDecoration(labelText: 'Имя'), maxLength: 60,
              validator: (value) => (value ?? '').trim().isEmpty ? 'Укажи имя' : null),
            const SizedBox(height: 12),
          ],
          TextFormField(controller: login, enabled: !busy, autocorrect: false,
            decoration: const InputDecoration(labelText: 'Логин', hintText: 'Например, syrym'),
            validator: (value) => !RegExp(r'^[a-zA-Z0-9_.-]{3,40}$').hasMatch((value ?? '').trim())
                ? '3–40 символов: латиница, цифры, _ . -' : null),
          const SizedBox(height: 16),
          TextFormField(controller: password, enabled: !busy, obscureText: hidden,
            enableSuggestions: false, autocorrect: false,
            decoration: InputDecoration(labelText: 'Пароль', suffixIcon: IconButton(
              tooltip: hidden ? 'Показать пароль' : 'Скрыть пароль',
              onPressed: () => setState(() => hidden = !hidden),
              icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined))),
            validator: (value) => (value ?? '').length < 8 ? 'Минимум 8 символов' : null,
            onFieldSubmitted: (_) { if (!registering) submit(); }),
          if (registering) ...[
            const SizedBox(height: 16),
            TextFormField(controller: confirmation, enabled: !busy, obscureText: hidden,
              enableSuggestions: false, autocorrect: false,
              decoration: const InputDecoration(labelText: 'Повтори пароль'),
              validator: (value) => value != password.text ? 'Пароли не совпадают' : null,
              onFieldSubmitted: (_) => submit()),
          ],
          const SizedBox(height: 20),
          if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12),
            child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (widget.store == null) const Text('База профилей недоступна. Перезапусти приложение.'),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: busy || widget.store == null ? null : submit,
            child: Text(busy ? 'Подожди…' : registering ? 'Создать профиль' : 'Войти'))),
        ])),
      ],
      const SizedBox(height: 24),
      const Text('Учебный прототип: профили сохраняются на этом устройстве. '
          'После перезапуска можно войти снова.', style: TextStyle(color: Colors.black54)),
    ]));
  }
}
