В 0.8 общий HTTPS-адрес можно сохранить через «Настройки → Адрес сервера».
На Windows/Mac обычный запуск по умолчанию использует http://127.0.0.1:8787.
Сохранённая настройка имеет приоритет над BACKEND_URL.

# Общий HTTPS для команды

Для первого командного демо можно дать вашему уже работающему серверу временный
HTTPS-адрес через Cloudflare Quick Tunnel. Один сервер = одна база у всей команды.
В этой поставке туннель не запускался и приложение в интернет не публиковалось.

## Быстрое подключение

1. Установите cloudflared на компьютере, где будет работать Python-сервер:
   https://developers.cloudflare.com/tunnel/downloads/
   Для Windows на странице есть MSI/exe; для Mac команда `brew install cloudflared`.
   Если Windows не находит команду после установки, откройте новый терминал.

2. Терминал 1, папка проекта:

```powershell
python backend/server.py --local-dev
```

3. Терминал 2 на ТОМ ЖЕ компьютере:

```powershell
cloudflared tunnel --url http://127.0.0.1:8787
```

4. Скопируйте напечатанный адрес вида https://something.trycloudflare.com.
   Проверка в браузере: https://something.trycloudflare.com/health → JSON со status=ok.
   Это пример; используйте адрес из собственного терминала.

5. Все участники запускают приложение с одним этим адресом:

```text
flutter run -d windows --dart-define=BACKEND_URL=https://YOUR-URL.trycloudflare.com
flutter run -d macos --dart-define=BACKEND_URL=https://YOUR-URL.trycloudflare.com
flutter run -d YOUR_ANDROID_DEVICE --dart-define=BACKEND_URL=https://YOUR-URL.trycloudflare.com
```

Android device ID показывает flutter devices. В AndroidManifest.xml для релиза должно быть
android.permission.INTERNET. На Mac сохраните network.client entitlement.

Проверьте одним тестовым аккаунтом на двух устройствах: изменить имя на одном,
выйти/войти на втором; создать бронирование → обновить Bookings на другом.
Потом создайте отдельные аккаунты каждому участнику. Не используйте настоящие платёжные данные.

## Что знать

- Компьютер с Python и cloudflared должен быть включён и подключён к интернету.
- Туннель создаёт публичный адрес; вход и роли проверяет наше приложение. Не публикуйте
  адрес как готовый массовый сервис: это учебный сервер и тестовые данные.
- Внешняя связь HTTPS и соединение cloudflared с Cloudflare зашифрованы;
  HTTP от cloudflared до Python проходит только по loopback того же компьютера.
- После остановки cloudflared адрес перестаёт работать; при новом запуске hostname меняется.
  Нужно передать новое BACKEND_URL при запуске Flutter. Для постоянного APK нужен стабильный hostname.
- Не добавляйте --allowed-mail для этого API: документированный email-фильтр Quick Tunnel
  требует интерактивного браузерного входа, который наш HTTP-клиент не реализует.
- Если получили HTML вместо JSON / 502: сначала проверьте Python /health локально,
  затем адрес туннеля. Приложение не должно быть направлено на страницу информационного сайта.
- Туннель — средство разработки без гарантии uptime, не постоянный хостинг.

## Постоянный адрес

После первого успешного демо используйте named Cloudflare Tunnel со своим hostname
или сервер с доменом и Caddy. Для Caddy DNS A/AAAA должен указывать на доступный сервер,
а необходимые порты 80/443 — быть доступны согласно документации.
Python оставьте на 127.0.0.1:8787, Caddy принимает HTTPS:

```text
api.your-domain.example {
    reverse_proxy 127.0.0.1:8787
}
```

Замените домен на свой. Caddy управляет сертификатом автоматически при выполнении
его сетевых/DNS условий. Права приложения остаются серверными. Базу и резервные копии
держите на постоянном диске; не копируйте разные SQLite-файлы каждому участнику.

Официальные источники, проверены при подготовке:
- https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/
- https://developers.cloudflare.com/tunnel/downloads/
- https://developers.cloudflare.com/tunnel/features/locally-managed-tunnels/create-local-tunnel/
- https://caddyserver.com/docs/automatic-https
- https://caddyserver.com/docs/caddyfile/directives/reverse_proxy
