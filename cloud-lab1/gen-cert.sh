#!/usr/bin/env bash
# Генерирует самоподписанный сертификат для локальной разработки.
set -euo pipefail
cd "$(dirname "$0")"

openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout nginx/certs/server.key -out nginx/certs/server.crt \
  -subj "/CN=lab.local" \
  -addext "subjectAltName=DNS:lab.local,DNS:second.local,DNS:localhost"

echo "Готово: nginx/certs/server.crt и nginx/certs/server.key"