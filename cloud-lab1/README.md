# Лаба 1. nginx

nginx стоит перед сервисом «Заметки» из лабы 0 и держит сайт живым, даже когда один из двух бэкендов упал.


## Что настроено

| Требование | Где в `nginx/nginx.conf` |
|-----------|--------------------------|
| HTTPS с самоподписанным сертификатом | `listen 443 ssl`, `ssl_certificate`, `ssl_certificate_key` |
| HTTP (80) → HTTPS (443) | `server { listen 80 ... return 301 https://$host$request_uri; }` |
| Фронт отдаёт nginx, `/api` проксируется на бэкенд | `root frontend;` и `location /api/ { proxy_pass http://backend_pool; }` |
| Балансировка между двумя экземплярами | `upstream backend_pool { server :5001; server :5002; }` |
| Идентификатор экземпляра в ответе | бэкенд добавляет заголовок `X-Instance-Id` и поле `instance` в `/api/health` |
| Отказоустойчивость | `max_fails`, `fail_timeout`, `proxy_next_upstream`, `proxy_connect_timeout` |
| `alias` | `location /docs/ { alias docs/; }` |
| Виртуальные хосты | `server_name lab.local;`, `server_name second.local;` и `default_server` для чужих имён |
| Ограничение частоты | `limit_req_zone` и `limit_req zone=api burst=10 nodelay;` (ответ 429) |
| Своя страница 404 и 50x | `error_page 404 /404.html;`, `error_page 500 502 503 504 /50x.html;` |
| `/admin` под паролем | `auth_basic` + `auth_basic_user_file htpasswd` |

Доступ в `/admin`: логин `admin`, пароль `lab1pass` (учебный).

## Структура

```
lab1/
├── backend/            Flask-бэкенд (app.py, requirements.txt)
├── frontend/           статика основного проекта (index.html)
├── docs/               папка для alias (/docs/)
├── admin/              страница под basic-авторизацией (/admin/)
├── second/             статика второго виртуального хоста
├── errors/             страницы 404.html и 50x.html
├── nginx/
│   ├── nginx.conf      главный конфиг
│   ├── mime.types
│   ├── htpasswd        пароль для /admin
│   └── certs/          самоподписанный сертификат
├── db/init.sql         создание пользователя и базы (как в лабе 0)
├── gen-cert.sh         перегенерировать сертификат
├── start-backends.sh   запуск двух экземпляров бэкенда
├── stop-backends.sh
├── start-nginx.sh
└── check.sh            проверки всех пунктов
```

## Что нужно

- nginx 1.18+
- Python 3.9+ и PostgreSQL 13+ (база из лабы 0)
- `curl` и `openssl`
- На Windows скрипты `.sh` запускаются в **Git Bash** (ставится вместе с Git)

## Запуск

### 1. Имена хостов

Браузеру нужно знать, что `lab.local` и `second.local` — это ваш компьютер. Добавьте в файл hosts строку:

```
127.0.0.1 lab.local second.local
```

- Windows: `C:\Windows\System32\drivers\etc\hosts` (редактор от имени администратора)
- Linux/macOS: `/etc/hosts`

Для `check.sh` это не нужно: он подставляет имена сам.

### 2. База данных

Если она ещё не создана:

```bash
psql -U postgres -f db/init.sql
```

### 3. Бэкенд

```bash
cd backend
python -m venv venv
source venv/bin/activate            # Git Bash: source venv/Scripts/activate
pip install -r requirements.txt
cd ..
./start-backends.sh                 # backend-1 на :5001 и backend-2 на :5002
```

### 4. Сертификат

Готовый самоподписанный сертификат уже лежит в `nginx/certs/`. Чтобы создать новый: `./gen-cert.sh`.

### 5. nginx

Linux/macOS (порты 80 и 443 требуют прав администратора):

```bash
sudo ./start-nginx.sh
```

Windows (из папки лабы, в cmd или PowerShell; путь к `nginx.exe` — ваш):

```powershell
C:\nginx\nginx.exe -p "D:/путь/к/lab1/" -c nginx/nginx.conf -e logs/error.log
```

Остановка: `./start-nginx.sh stop` (Windows: то же самое с ключом `-s stop`).

### 6. Проверка

Откройте https://lab.local. Браузер предупредит о самоподписанном сертификате, это нормально: подтвердите переход. Вверху страницы написано, какой экземпляр бэкенда ответил; статус обновляется раз в 3 секунды.

Остановите один бэкенд (`./stop-backends.sh 2`) и подождите: сайт продолжает работать, отвечает только `backend-1`.

Другие адреса: https://lab.local/docs/, https://lab.local/admin/ (запросит пароль), https://second.local, https://lab.local/нет-такой-страницы.

### 7. Автоматические проверки

```bash
./check.sh | tee check-output.txt
```

Скрипт проверяет по порядку: редирект 301, чередование экземпляров, работу при упавшем бэкенде, 401 на `/admin`, 429 при флуде, разведение виртуальных хостов, свою 404, `alias` и (по желанию) страницу 50x. Заканчивается строкой `Итого: PASS=…, FAIL=…`.

## Как это работает

- **Отказоустойчивость.** Если бэкенд не отвечает, nginx за секунду (`proxy_connect_timeout 1s`) понимает это, повторяет запрос на соседнем экземпляре (`proxy_next_upstream`) и 5 секунд (`fail_timeout`) не отправляет на упавший новые запросы. Пользователь ошибки не видит.
- **Ограничение частоты.** 5 запросов в секунду с одного IP и всплеск до 10. Всё сверх этого получает 429. Поэтому в `check.sh` между шагами есть паузы.
- **Чужой Host.** Запрос с неизвестным именем попадает в `default_server`, который отвечает 404 `Unknown host` и ничего из проектов не отдаёт.
- **Пути в конфиге.** `root`, `alias`, логи и страницы ошибок считаются от ключа `-p` (корень лабы). Сертификат, `htpasswd` и `include` — от папки `nginx/`. Благодаря этому конфиг одинаково работает на Linux и Windows.
