#!/usr/bin/env bash
# Проверки лабы 1
# Запуск:  ./check.sh | tee check-output.txt
# Предусловия: запущены оба бэкенда (./start-backends.sh) и nginx (sudo ./start-nginx.sh)
cd "$(dirname "$0")"

HOST=lab.local
OTHER=second.local
FOREIGN=evil.example
ADMIN_USER=admin
ADMIN_PASS=lab1pass

# curl: -k (самоподписанный сертификат), без системного прокси, имена -> 127.0.0.1
c() {
  curl -sk --noproxy '*' \
    --resolve "$HOST:80:127.0.0.1"  --resolve "$HOST:443:127.0.0.1" \
    --resolve "$OTHER:443:127.0.0.1" --resolve "$FOREIGN:443:127.0.0.1" "$@"
}

PASS=0; FAIL=0
ok()   { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
bad()  { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$1" = "1" ]; then ok "$2"; else bad "$2"; fi; }
instance() { c -D - -o /dev/null "$1" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-instance-id"{print $2}'; }
probe() { c -D - -o /dev/null -w 'CODE=%{http_code}\n' "$1" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-instance-id"{i=$2} /^CODE=/{sub("CODE=","");c=$0} END{print c, i}'; }
title() { echo; echo "=== $1"; }

title "1. HTTP -> HTTPS: редирект 301"
echo "\$ curl -I http://$HOST/api/health?x=1"
c -sI "http://$HOST/api/health?x=1" | tr -d '\r' | grep -i -E "^HTTP|^Server|^Location"
code=$(c -o /dev/null -w '%{http_code}' "http://$HOST/")
loc=$(c -o /dev/null -w '%{redirect_url}' "http://$HOST/api/health?x=1")
check "$([ "$code" = 301 ] && echo 1)" "HTTP отвечает 301 (получено $code)"
check "$([ "$loc" = "https://$HOST/api/health?x=1" ] && echo 1)" "Location ведёт на https и сохраняет путь и параметры ($loc)"
if [ "$code" != 301 ]; then
  echo "  подсказка: порт 80 отвечает не наш nginx (в заголовках выше должно быть 'Server: nginx')."
  echo "  Посмотрите, кто слушает порт 80:  netstat -ano | findstr :80   (Windows)"
  echo "                                    sudo ss -ltnp | grep ':80 '   (Linux)"
fi

title "2. Балансировка: запросы чередуются между двумя экземплярами"
echo "\$ for i in 1..6; do curl -k https://$HOST/api/health; done  (заголовок X-Instance-Id)"
seen=""
for i in 1 2 3 4 5 6; do
  inst=$(instance "https://$HOST/api/health")
  echo "  запрос $i -> $inst"
  seen="$seen $inst"
done
echo "  тело ответа: $(c "https://$HOST/api/health")"
check "$(echo "$seen" | grep -q backend-1 && echo "$seen" | grep -q backend-2 && echo 1)" "ответили оба экземпляра (backend-1 и backend-2)"

# ---------------------------------------------------------------------------
title "3. Отказоустойчивость: гасим backend-2, сайт продолжает отвечать"
sleep 2
./stop-backends.sh 2
sleep 1
echo "\$ for i in 1..8; do curl -k https://$HOST/api/health; done"
codes=""; seen=""
for i in 1 2 3 4 5 6 7 8; do
  read -r code inst <<< "$(probe "https://$HOST/api/health")"
  echo "  запрос $i -> HTTP $code, ответил $inst"
  codes="$codes $code"; seen="$seen $inst"
done
check "$([ -z "$(echo "$codes" | tr ' ' '\n' | grep -v -x -e 200 -e '')" ] && echo 1)" "все ответы 200 при одном упавшем бэкенде"
check "$(echo "$seen" | grep -q backend-2 || echo 1)" "трафик ушёл только на живой backend-1"
sleep 2
echo "  записи на сайте при упавшем backend-2 тоже работают:"
code=$(printf '%s' '{"text":"write while backend-2 is down"}' | c -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data-binary @- "https://$HOST/api/notes")
check "$([ "$code" = 201 ] && echo 1)" "POST /api/notes -> $code"

echo "  поднимаем backend-2 обратно"
./start-backends.sh 2 > /dev/null
sleep 6
seen=""
for i in 1 2 3 4 5 6; do seen="$seen $(instance "https://$HOST/api/health")"; done
check "$(echo "$seen" | grep -q backend-2 && echo 1)" "backend-2 снова получает трафик после восстановления"

title "4. /admin закрыт базовой авторизацией"
echo "\$ curl https://$HOST/admin/"
code=$(c -o /dev/null -w '%{http_code}' "https://$HOST/admin/")
check "$([ "$code" = 401 ] && echo 1)" "без пароля -> $code"
code=$(c -o /dev/null -w '%{http_code}' -u "$ADMIN_USER:wrong" "https://$HOST/admin/")
check "$([ "$code" = 401 ] && echo 1)" "с неверным паролем -> $code"
code=$(c -o /dev/null -w '%{http_code}' -u "$ADMIN_USER:$ADMIN_PASS" "https://$HOST/admin/")
check "$([ "$code" = 200 ] && echo 1)" "с верным паролем -> $code"

title "5. Ограничение частоты: флуд на /api упирается в 429"
sleep 3
echo "\$ 60 запросов подряд на https://$HOST/api/health"
stats=$(for i in $(seq 1 60); do c -o /dev/null -w '%{http_code}\n' "https://$HOST/api/health"; done | sort | uniq -c)
echo "$stats" | sed 's/^/  /'
n429=$(echo "$stats" | awk '$2==429{print $1}')
check "$([ "${n429:-0}" -gt 0 ] && echo 1)" "получено ответов 429: ${n429:-0}"
sleep 3

title "6. Виртуальные хосты: каждый домен отдаёт только свой проект"
body=$(c "https://$HOST/")
check "$(echo "$body" | grep -q 'Заметки' && ! echo "$body" | grep -q SECOND-PROJECT-MARKER && echo 1)" "Host: $HOST -> основной проект, без чужого содержимого"
body=$(c "https://$OTHER/")
check "$(echo "$body" | grep -q SECOND-PROJECT-MARKER && ! echo "$body" | grep -q 'Заметки' && echo 1)" "Host: $OTHER -> второй проект, без содержимого основного"
code=$(c -o /dev/null -w '%{http_code}' "https://$OTHER/api/health")
check "$([ "$code" = 404 ] && echo 1)" "у $OTHER нет API ($code), чужие маршруты не доступны"
body=$(c -w ' [HTTP %{http_code}]' "https://$FOREIGN/")
echo "  Host: $FOREIGN -> $(echo "$body" | tr '\n' ' ')"
check "$(echo "$body" | grep -q 'HTTP 404' && ! echo "$body" | grep -q -e 'Заметки' -e SECOND-PROJECT-MARKER && echo 1)" "чужой Host -> 404, ни один из проектов не отдан"

title "7. Своя страница 404"
echo "\$ curl https://$HOST/no-such-page"
body=$(c -w ' [HTTP %{http_code}]' "https://$HOST/no-such-page")
check "$(echo "$body" | grep -q 'HTTP 404' && echo "$body" | grep -q 'Страница не найдена' && echo 1)" "несуществующая страница -> наша 404, а не стандартная nginx"

title "8. alias: /docs/ отдаётся из отдельной папки docs/"
body=$(c "https://$HOST/docs/")
check "$(echo "$body" | grep -q DOCS-MARKER && echo 1)" "https://$HOST/docs/ -> содержимое папки docs/"

title "9. Оба бэкенда упали -> своя страница 50x"
./stop-backends.sh > /dev/null
sleep 1
body=$(c -w ' [HTTP %{http_code}]' "https://$HOST/api/health")
echo "  ответ: $(echo "$body" | grep -o -E 'Сервис временно недоступен|\[HTTP [0-9]+\]' | paste -sd' ')"
check "$(echo "$body" | grep -q 'Сервис временно недоступен' && echo 1)" "вместо стандартной ошибки nginx показана наша страница 50x"
./start-backends.sh > /dev/null
sleep 6

echo
echo "=============================================="
echo "Итого: PASS=$PASS, FAIL=$FAIL"
[ "$FAIL" -eq 0 ]