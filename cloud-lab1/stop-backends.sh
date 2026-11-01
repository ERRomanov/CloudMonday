#!/usr/bin/env bash
# Останавливает экземпляры бэкенда (все или указанные)
cd "$(dirname "$0")"
NUMS=("$@"); [ ${#NUMS[@]} -eq 0 ] && NUMS=(1 2)
for i in "${NUMS[@]}"; do
  if [ -f "run/backend$i.pid" ]; then
    kill "$(cat run/backend$i.pid)" 2>/dev/null && echo "backend-$i остановлен"
    rm -f "run/backend$i.pid"
  fi
done