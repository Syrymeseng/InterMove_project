import 'package:flutter/material.dart';
import 'local_store.dart';
import 'auth_service.dart';

class ProfilePanel extends StatefulWidget {
  final AuthService auth;
  final Account? account;
  final ValueChanged<Account?> onAccountChanged;
  const ProfilePanel({super.key, required this.auth, required this.account,
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
    if (busy || !widget.auth.available || !form.currentState!.validate()) return;
    setState(() { busy = true; error = null; });
    try {
      final account = registering
          ? await widget.auth.register(name.text, login.text, password.text)
          : await widget.auth.login(login.text, password.text);
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

  Future<void> signOut() async {
    setState(() { busy = true; error = null; });
    try {
      await widget.auth.logout();
      if (!mounted) return;
      widget.onAccountChanged(null);
      setState(() { registering = false; });
    } catch (_) {
      if (mounted) setState(() => error = 'Не удалось завершить сессию на сервере. Проверь сеть и повтори выход.');
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> adminSummary() async {
    setState(() { busy = true; error = null; });
    try {
      final summary = await widget.auth.adminSummary();
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: const Text('Администратор · демо'),
        content: Text('Аккаунтов: ${summary['accounts']}\nСобытий аудита: ${summary['auditEvents']}'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть'))]));
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Сервер недоступен.');
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> editProfile() async {
    final updated = await showDialog<Account>(context: context,
      builder: (_) => ProfileEditor(auth: widget.auth, account: widget.account!));
    if (mounted && updated != null) widget.onAccountChanged(updated);
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
        Text('${widget.auth.remote ? "Email" : "Логин"}: ${account.login}'),
        if (widget.auth.remote) ...[
          Text('Роль: ${account.role}'),
          TextButton(onPressed: busy ? null : editProfile, child: const Text('Редактировать профиль')),
          if (account.role == 'admin') TextButton(onPressed: busy ? null : adminSummary,
            child: const Text('Проверить доступ администратора')),
        ],
        const SizedBox(height: 24),
        if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        OutlinedButton.icon(onPressed: busy ? null : signOut, icon: const Icon(Icons.logout), label: const Text('Выйти')),
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
            decoration: InputDecoration(labelText: widget.auth.remote ? 'Email' : 'Логин',
              hintText: widget.auth.remote ? 'name@example.com' : 'Например, syrym'),
            keyboardType: widget.auth.remote ? TextInputType.emailAddress : TextInputType.text,
            validator: (value) {
              final pattern = widget.auth.remote ? r'^[^\s@]+@[^\s@]+\.[^\s@]+$' : r'^[a-zA-Z0-9_.-]{3,40}$';
              return RegExp(pattern).hasMatch((value ?? '').trim()) ? null
                : widget.auth.remote ? 'Укажи корректный email' : 'Логин: 3–40 символов';
            }),
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
          if (!widget.auth.available) const Text('База профилей недоступна. Перезапусти приложение.'),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: busy || !widget.auth.available ? null : submit,
            child: Text(busy ? 'Подожди…' : registering ? 'Создать профиль' : 'Войти'))),
        ])),
      ],
      const SizedBox(height: 24),
      Text(widget.auth.remote
        ? 'Общая база аккаунтов. После перезапуска войди снова. Старые локальные аккаунты не переносятся автоматически.'
        : 'Локальный режим: аккаунты только на этом устройстве. Общий сервер ещё не подключён.',
        style: const TextStyle(color: Colors.black54)),
    ]));
  }
}

class ProfileEditor extends StatefulWidget {
  final AuthService auth;
  final Account account;
  const ProfileEditor({super.key, required this.auth, required this.account});
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late final TextEditingController name = TextEditingController(text: widget.account.name);
  late bool stepFree = widget.account.preferences['stepFree'] == true;
  late bool assistance = widget.account.preferences['boardingAssistance'] == true;
  late String wheelchair = widget.account.preferences['wheelchair'] as String? ?? 'none';
  bool busy = false;
  String? error;
  @override
  void dispose() { name.dispose(); super.dispose(); }
  Future<void> save({bool remove = false}) async {
    if (busy) return;
    if (name.text.trim().isEmpty || name.text.trim().length > 60) {
      setState(() => error = 'Имя: от 1 до 60 символов.'); return;
    }
    setState(() { busy = true; error = null; });
    try {
      final account = await widget.auth.updateProfile(name.text.trim(), remove ? {} : {
        'stepFree': stepFree, 'boardingAssistance': assistance, 'wheelchair': wheelchair,
      });
      if (mounted) Navigator.pop(context, account);
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Сохранение не подтверждено. Проверь сеть и повтори.');
    } finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Редактирование профиля'),
    content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: name, enabled: !busy, maxLength: 60,
          decoration: const InputDecoration(labelText: 'Имя')),
        const Text('Необязательные предпочтения. Сохраняются только по кнопке ниже.'),
        SwitchListTile(title: const Text('Без ступенек'), value: stepFree,
          onChanged: busy ? null : (v) => setState(() => stepFree = v)),
        SwitchListTile(title: const Text('Помощь при посадке'), value: assistance,
          onChanged: busy ? null : (v) => setState(() => assistance = v)),
        DropdownButton<String>(value: wheelchair, isExpanded: true,
          items: const [DropdownMenuItem(value: 'none', child: Text('Без коляски')),
            DropdownMenuItem(value: 'folded', child: Text('Складная коляска')),
            DropdownMenuItem(value: 'seated', child: Text('Оставаться в коляске'))],
          onChanged: busy ? null : (v) => setState(() => wheelchair = v ?? 'none')),
        const Text('На этом этапе это сохранённые предпочтения. '
          'Автоматическое применение к поиску будет добавлено с новым планировщиком.'),
        if (error != null) Semantics(liveRegion: true, child: Text(error!)),
        TextButton(onPressed: busy ? null : () => save(remove: true),
          child: const Text('Удалить сохранённые предпочтения')),
      ]))),
    actions: [TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(onPressed: busy ? null : () => save(), child: Text(busy ? 'Сохраняем…' : 'Сохранить'))],
  );
}
