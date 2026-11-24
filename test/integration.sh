#!/usr/bin/env bash
# End-to-end run of main.rb against real endpoints, directly and behind a blocking proxy.
set -u
RUBY_BIN="${RUBY:-ruby}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$DIR/test/output"
mkdir -p "$OUT"
rm -f "$OUT"/run-*.txt

PORT=$("$RUBY_BIN" -rsocket -e 's = TCPServer.new("127.0.0.1", 0); puts s.addr[1]; s.close')
"$RUBY_BIN" "$DIR/test/blocking_proxy.rb" "$PORT" androidpublisher.googleapis.com >"$OUT/proxy.log" 2>&1 &
PROXY_PID=$!
trap 'kill "$PROXY_PID" 2>/dev/null' EXIT
sleep 1

STORES=(AC_CHECK_NETWORK_WWW_GOOGLEAPIS_COM AC_CHECK_NETWORK_ANDROIDPUBLISHER_GOOGLEAPIS_COM
  AC_CHECK_NETWORK_CONNECT_API_CLOUD_HUAWEI_COM AC_CHECK_NETWORK_API_APPSTORECONNECT_APPLE_COM
  AC_CHECK_NETWORK_APPSTORECONNECT_APPLE_COM AC_CHECK_NETWORK_CONTENTDELIVERY_ITUNES_APPLE_COM
  AC_CHECK_NETWORK_NORTHAMERICA_1_OBJECT_STORAGE_APPLE_COM)
ALL_OFF=(AC_CHECK_NETWORK_API_ENTERPRISE_DEVELOPER_APPLE_COM "${STORES[@]}")
PROXY_VARS=(HTTPS_PROXY https_proxy HTTP_PROXY http_proxy ALL_PROXY all_proxy NO_PROXY no_proxy SSL_CERT_FILE CURL_CA_BUNDLE)

FAILED=0
CODE=0

# run NAME [VAR=VALUE ...]: runs main.rb with a clean proxy env, stores output and exit code
run() {
  local name="$1"; shift
  local v
  for v in "${PROXY_VARS[@]}"; do unset "$v"; done
  for v in "${ALL_OFF[@]}"; do export "$v=false"; done
  unset AC_CHECK_NETWORK_EXTRA_URL_PARAMETERS
  env "$@" "$RUBY_BIN" "$DIR/main.rb" >"$OUT/$name.txt" 2>&1
  CODE=$?
  for v in "${ALL_OFF[@]}"; do unset "$v"; done
}

stores_on() { local v; for v in "${STORES[@]}"; do printf '%s=true\n' "$v"; done; }

check() { # check LABEL CONDITION-COMMAND...
  local label="$1"; shift
  if ! "$@"; then echo "  FAIL: $label"; RUN_OK=0; fi
}

finish() {
  if [ "$RUN_OK" = 1 ]; then echo "PASS $1"; else echo "FAIL $1"; FAILED=1; fi
}

has() { grep -qE -- "$2" "$OUT/$1.txt"; }
hasnt() { ! grep -qE -- "$2" "$OUT/$1.txt"; }

# Run A: direct
RUN_OK=1
run run-a $(stores_on)
check "exit code 0 (got $CODE)" test "$CODE" = 0
check "no NOT REACHABLE row" hasnt run-a '\| NOT REACHABLE'
check "7 REACHABLE rows" test "$(grep -cE '^https://[^ ]+ +\| REACHABLE' "$OUT/run-a.txt")" = 7
check "Huawei warning" has run-a '^@@\[warning\].*Huawei'
finish "run A (direct, all default store inputs)"

# Run B: proxy blocking androidpublisher, with credentials
RUN_OK=1
run run-b $(stores_on) "HTTPS_PROXY=http://bob:s3cret@127.0.0.1:$PORT"
check "exit code 1 (got $CODE)" test "$CODE" = 1
check "androidpublisher row refused CONNECT 403" has run-b '^https://androidpublisher\.googleapis\.com/ +\| NOT REACHABLE +\| proxy refused CONNECT \(HTTP 403\)'
check "6 REACHABLE rows" test "$(grep -cE '^https://[^ ]+ +\| REACHABLE' "$OUT/run-b.txt")" = 6
check "no secret" hasnt run-b 's3cret|Ym9iOnMzY3JldA'
finish "run B (proxy blocks androidpublisher)"

# Run C: same, with NO_PROXY bypass
RUN_OK=1
run run-c $(stores_on) "HTTPS_PROXY=http://bob:s3cret@127.0.0.1:$PORT" NO_PROXY=androidpublisher.googleapis.com
check "exit code 0 (got $CODE)" test "$CODE" = 0
check "no NOT REACHABLE row" hasnt run-c '\| NOT REACHABLE'
check "no secret" hasnt run-c 's3cret|Ym9iOnMzY3JldA'
finish "run C (NO_PROXY bypass)"

# Run D: extra URLs only, DNS and TLS failures
RUN_OK=1
run run-d AC_CHECK_NETWORK_EXTRA_URL_PARAMETERS=https://does-not-exist.invalid,https://expired.badssl.com
check "exit code 1 (got $CODE)" test "$CODE" = 1
check "DNS row" has run-d '^https://does-not-exist\.invalid +\| NOT REACHABLE +\| .*curl exit 6'
check "TLS row" has run-d '^https://expired\.badssl\.com +\| NOT REACHABLE +\| .*curl exit (35|51|58|60|77|83|90|91)'
check "verbose trace" has run-d 'curl -v trace:'
check "DNS lookup line" has run-d 'DNS lookup'
check "error line" has run-d '^@@\[error\] 2 of 2 endpoints are not reachable\.'
finish "run D (DNS and TLS failures)"

# Run E: same as B, proxy URL without a scheme
RUN_OK=1
run run-e $(stores_on) "HTTPS_PROXY=bob:s3cret@127.0.0.1:$PORT"
check "exit code 1 (got $CODE)" test "$CODE" = 1
check "androidpublisher row refused CONNECT 403" has run-e '^https://androidpublisher\.googleapis\.com/ +\| NOT REACHABLE +\| proxy refused CONNECT \(HTTP 403\)'
check "6 REACHABLE rows" test "$(grep -cE '^https://[^ ]+ +\| REACHABLE' "$OUT/run-e.txt")" = 6
check "masked env line" has run-e '^  HTTPS_PROXY=\*\*\*:\*\*\*@127\.0\.0\.1:'
check "no secret" hasnt run-e 's3cret|Ym9iOnMzY3JldA'
finish "run E (scheme-less proxy URL with credentials)"

exit "$FAILED"
