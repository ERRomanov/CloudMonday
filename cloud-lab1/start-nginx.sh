#!/usr/bin/env bash
# Запуск nginx с конфигом лабы
cd "$(dirname "$0")"
mkdir -p run logs

if [ "${1:-}" = "stop" ]; then
  nginx -p "$PWD/" -c nginx/nginx.conf -e logs/error.log -s stop && echo "nginx остановлен"
  exit 0
fi

GLOBAL=""
if [ "$(id -u)" = "0" ]; then GLOBAL="user ${SUDO_USER:-root};"; fi

nginx -p "$PWD/" -c nginx/nginx.conf -e logs/error.log ${GLOBAL:+-g "$GLOBAL"} && echo "nginx запущен"