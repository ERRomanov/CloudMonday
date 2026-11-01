#!/usr/bin/env bash
# Запускает экземпляры бэкенда на портах 5001 и 5002 (или только указанные).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p run logs

if [ -z "${PYTHON:-}" ]; then
  if   [ -x backend/venv/bin/python ];         then PYTHON=backend/venv/bin/python
  elif [ -x backend/venv/Scripts/python.exe ]; then PYTHON=backend/venv/Scripts/python.exe
  else PYTHON=python3; fi
fi

NUMS=("$@"); [ ${#NUMS[@]} -eq 0 ] && NUMS=(1 2)

for i in "${NUMS[@]}"; do
  # Не запускаем второй раз то, что уже работает: иначе pid-файл
  # потеряет настоящий процесс, и ./stop-backends.sh его не остановит.
  if [ -f "run/backend$i.pid" ] && kill -0 "$(cat run/backend$i.pid)" 2>/dev/null; then
    echo "backend-$i уже запущен (pid $(cat run/backend$i.pid)), пропускаю"
    continue
  fi
  PORT=$((5000 + i)) INSTANCE_ID="backend-$i" \
    nohup "$PYTHON" backend/app.py > "run/backend$i.log" 2>&1 &
  echo $! > "run/backend$i.pid"
  echo "backend-$i запущен на порту $((5000 + i)) (pid $(cat run/backend$i.pid))"
done

# Ждём, пока экземпляры начнут отвечать.
for i in "${NUMS[@]}"; do
  for _ in $(seq 1 30); do
    curl -s -o /dev/null "http://127.0.0.1:$((5000 + i))/api/health" && break
    sleep 0.5
  done
done