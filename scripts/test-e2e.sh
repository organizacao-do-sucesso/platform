#!/usr/bin/env bash
# End-to-end tests of the store platform, always through the gateway.
#
#   bash scripts/test-e2e.sh          build the services from the api/ submodules, start the
#                                     docker compose stack and run the tests
#   bash scripts/test-e2e.sh test     only run the tests against a gateway that is already up
#                                     (e.g. EKS: kubectl port-forward -n store service/gateway 8080:8080)
#   bash scripts/test-e2e.sh down     stop the docker compose stack
#
# Environment: GATEWAY_URL (default http://localhost:8080), ADMIN_EMAIL / ADMIN_PASSWORD
# (default: api/.env, then admin@store.local / admin), GRAFANA_ADMIN_USER / GRAFANA_ADMIN_PASSWORD
# (default admin / admin). Needs bash, curl, python3; the full mode also needs docker, maven and Java 25.
# Exits non-zero if any test fails.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API="$ROOT/api"
GW="${GATEWAY_URL:-http://localhost:8080}"
LOG="$ROOT/test-e2e.log"
MODE="${1:-full}"

env_value() { [ -f "$API/.env" ] && sed -n "s/^$1=//p" "$API/.env" | tail -n1; }
ADMIN_EMAIL="${ADMIN_EMAIL:-$(env_value ADMIN_EMAIL)}"; ADMIN_EMAIL="${ADMIN_EMAIL:-admin@store.local}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-$(env_value ADMIN_PASSWORD)}"; ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}"

compose() { docker compose --project-directory "$API" -f "$API/compose.yaml" "$@"; }

case "$MODE" in
  down)
    compose down; exit 0 ;;
  test)
    echo "== running the tests against $GW" ;;
  full)
    [ -x /usr/libexec/java_home ] && export JAVA_HOME="$(/usr/libexec/java_home -v 25)"
    [ -f "$API/account-service/pom.xml" ] || { echo "submodules missing: git submodule update --init"; exit 1; }
    : > "$LOG"
    echo "== 1/3 building (log: $LOG)"
    for c in account auth product order exchange; do
      echo "   contract $c"; (cd "$API/$c" && mvn -q -B install -DskipTests >>"$LOG" 2>&1) || { echo "BUILD FAILED: $c (see $LOG)"; exit 1; }
    done
    for s in account-service auth-service product-service order-service gateway-service; do
      echo "   service  $s"; (cd "$API/$s" && mvn -q -B clean package -DskipTests >>"$LOG" 2>&1) || { echo "BUILD FAILED: $s (see $LOG)"; exit 1; }
    done
    echo "== 2/3 starting platform"
    [ -f "$API/.env" ] || cp "$API/.env.example" "$API/.env"
    compose up -d --build >>"$LOG" 2>&1 || { echo "COMPOSE FAILED (see $LOG)"; exit 1; } ;;
  *)
    echo "usage: bash $0 [test|down]"; exit 2 ;;
esac

json() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)" 2>/dev/null; }
login() { # prints the JWT for email/password
  curl -s -D - -o /dev/null -X POST "$GW/auth/login" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | sed -n 's/^[Ss]et-[Cc]ookie: __store_jwt_token=\([^;]*\).*/\1/p'
}
printf "   waiting for gateway + admin account"
for i in $(seq 1 90); do ADMIN=$(login "$ADMIN_EMAIL" "$ADMIN_PASSWORD"); [ -n "$ADMIN" ] && break; printf "."; sleep 3; done; echo
[ -n "$ADMIN" ] || { echo "PLATFORM DID NOT COME UP: no admin login at $GW"; [ "$MODE" = test ] || { compose logs >>"$LOG" 2>&1; echo "   docker compose logs in $LOG"; }; exit 1; }

printf "   waiting for order service"
for i in $(seq 1 90); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' "$GW/orders" -H "Cookie: __store_jwt_token=$ADMIN")" = 200 ] && break; printf "."; sleep 3
done; echo

PASS=0; FAIL=0
check() { # name expected actual [detail]
  if [ "$2" = "$3" ]; then echo "  PASS  $1"; PASS=$((PASS+1)); else echo "  FAIL  $1 (expected $2, got $3) ${4:-}"; FAIL=$((FAIL+1)); fi
}
req() { # token method path [body] -> sets CODE and BODY
  local out; out=$(curl -s -w '\n%{http_code}' -X "$2" "$GW$3" -H "Cookie: __store_jwt_token=$1" -H 'Content-Type: application/json' ${4:+-d "$4"})
  CODE=$(tail -n1 <<<"$out"); BODY=$(sed '$d' <<<"$out")
}

echo "== 3/3 tests"
req "$ADMIN" POST /products '{"name":"Tomato","price":10.12,"unit":"kg"}'; check "admin creates product" 201 "$CODE" "$BODY"
PID=$(json "d['id']" <<<"$BODY")

req "$ADMIN" POST /orders "{\"items\":[{\"idProduct\":\"$PID\",\"quantity\":2}]}"; check "POST /orders" 201 "$CODE" "$BODY"
OID=$(json "d['id']" <<<"$BODY"); check "order total = 2 x 10.12" "20.24" "$(json "d['total']" <<<"$BODY")"

req "$ADMIN" POST /orders '{"items":[{"idProduct":"00000000-0000-0000-0000-000000000000","quantity":1}]}'; check "unknown product -> 400" 400 "$CODE"
req "$ADMIN" POST /orders "{\"items\":[{\"idProduct\":\"$PID\",\"quantity\":0}]}"; check "quantity 0 -> 400" 400 "$CODE"
req "$ADMIN" GET /orders; check "GET /orders" 200 "$CODE"
req "$ADMIN" GET "/orders/$OID"; check "GET /orders/{id}" 200 "$CODE"; check "currency defaults to USD" USD "$(json "d['currency']" <<<"$BODY")"
req "$ADMIN" GET "/orders/$OID?currency=BRL"; check "GET /orders/{id}?currency=BRL (via exchange)" 200 "$CODE" "$BODY"; check "currency = BRL" BRL "$(json "d['currency']" <<<"$BODY")"
req "$ADMIN" GET "/orders/$OID?currency=XYZ"; check "unsupported currency -> 422" 422 "$CODE" "$BODY"

EMAIL="customer$RANDOM@test.local"
curl -s -o /dev/null -X POST "$GW/auth/register" -H 'Content-Type: application/json' -d "{\"name\":\"Customer\",\"email\":\"$EMAIL\",\"password\":\"123\"}"
CUST=$(login "$EMAIL" 123); check "customer registers and logs in" yes "$([ -n "$CUST" ] && echo yes || echo no)"
req "$CUST" GET "/orders/$OID"; check "another user's order -> 404" 404 "$CODE"
req "$CUST" POST /products '{"name":"X","price":1,"unit":"u"}'; check "customer cannot create product -> 403" 403 "$CODE"
req "" GET /orders; check "no token -> 401" 401 "$CODE"
req "$CUST" GET /prometheus/api/v1/targets; check "customer cannot open Prometheus -> 403" 403 "$CODE"

PROM="$GW/prometheus/api/v1"; PC="Cookie: __store_jwt_token=$ADMIN"
check "Prometheus via gateway without login -> 401" 401 "$(curl -s -o /dev/null -w '%{http_code}' "$PROM/targets")"
check "Grafana via gateway (/grafana/api/health)" 200 "$(curl -s -o /dev/null -w '%{http_code}' "$GW/grafana/api/health")"
check "Grafana datasource reaches Prometheus" 200 "$(curl -s -o /dev/null -w '%{http_code}' -u "$GRAFANA_ADMIN_USER:$GRAFANA_ADMIN_PASSWORD" "$GW/grafana/api/datasources/uid/prometheus/health")"
for i in $(seq 1 8); do  # service discovery (docker or kubernetes) refreshes every 15s
  UP=$(curl -s "$PROM/targets" -H "$PC" | json "next((t['health'] for t in d['data']['activeTargets'] if t['labels'].get('service')=='order'),'missing')")
  [ "$UP" = up ] && break; sleep 5
done
check "Prometheus scrapes order" up "$UP"
for i in $(seq 1 8); do  # prometheus scrapes every 15s: wait for the scrape after the orders above
  N=$(curl -s "$PROM/query?query=orders_placed_total" -H "$PC" | json "d['data']['result'][0]['value'][1] if d['data']['result'] else 'none'")
  [ "$N" != none ] && [ "${N%%.*}" -ge 1 ] 2>/dev/null && break; sleep 5
done
check "metric orders_placed_total >= 1" yes "$([ "$N" != none ] && [ "${N%%.*}" -ge 1 ] 2>/dev/null && echo yes || echo "no ($N, may need 15s)")"

echo; echo "== $PASS passed, $FAIL failed"
echo "   Grafana: $GW/grafana/ · Prometheus: $GW/prometheus/ (store administrator) · stop: bash $0 down"
[ "$FAIL" -eq 0 ]
