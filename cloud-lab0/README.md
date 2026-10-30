# Лаба по облакам: приложение «Заметки»

Небольшое приложение из трёх частей:

| Часть | Технология | Папка |
|-------|-----------|-------|
| Бэкенд | Python + Flask | `backend/` |
| Фронтенд | HTML + JS (без сборки) | `frontend/` |
| База данных | PostgreSQL (отдельный сервис) | `db/` |

API бэкенда:

- `GET /api/health` — проверка, что бэкенд и база живы
- `GET /api/notes` — список заметок из базы
- `POST /api/notes` — добавить заметку, тело: `{"text": "..."}`

Таблица `notes` создаётся автоматически при старте бэкенда.

Flask отдаёт страницу по адресу `/`, а API — по `/api/...`. Поэтому фронт и бэкенд работают на одном адресе (`http://localhost:8000`), и страница гарантированно «видит» API.

## Структура

```
cloud-lab/
├── backend/
│   ├── app.py
│   └── requirements.txt
├── frontend/
│   └── index.html
├── db/
│   └── init.sql
└── README.md
```

## Что нужно установить

- Python 3.9+
- PostgreSQL 13+ (запущенный сервер, порт 5432)

## Запуск локально

### 1. База данных

Убедитесь, что сервер PostgreSQL запущен, и из корня проекта создайте пользователя и базу:

```bash
psql -U postgres -f db/init.sql
```

(На Linux может понадобиться `sudo -u postgres psql -f db/init.sql`.)

Должно вывестись `CREATE ROLE` и `CREATE DATABASE`.

### 2. Приложение

Из корня проекта.

Windows (PowerShell):

```powershell
cd backend
python -m venv venv
venv\Scripts\Activate.ps1
pip install -r requirements.txt
python app.py
```

Если PowerShell ругается на выполнение скриптов, выполните один раз `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` или активируйте окружение в cmd: `venv\Scripts\activate.bat`.

Linux / macOS:

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python app.py
```

Откройте http://localhost:8000

Проверка API из терминала:

```bash
curl http://localhost:8000/api/health
# {"db":"up","status":"ok"}
```

## Настройка подключения к базе

Бэкенд читает параметры из переменных окружения (в скобках значения по умолчанию):

| Переменная | Значение по умолчанию |
|-----------|----------------------|
| `DB_HOST` | `localhost` |
| `DB_PORT` | `5432` |
| `DB_NAME` | `notes_db` |
| `DB_USER` | `notes_user` |
| `DB_PASSWORD` | `notes_pass` |
| `PORT` | `8000` (порт самого приложения) |

Пример (Linux/macOS):

```bash
DB_HOST=192.168.1.10 python app.py
```

Пример (Windows PowerShell):

```powershell
$env:DB_HOST = "192.168.1.10"; python app.py
```

## Проверка работоспособности

1. Откройте http://localhost:8000 — вверху должно быть «Бэкенд и база доступны».
2. Добавьте заметку через форму — она появится в списке.
3. Перезагрузите страницу (F5) — заметка на месте, потому что она лежит в PostgreSQL.
4. Для дополнительной проверки загляните в базу напрямую:

```bash
psql -U notes_user -h localhost -d notes_db -c "SELECT * FROM notes;"
```