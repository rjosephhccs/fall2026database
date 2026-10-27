#!/usr/bin/env bash
set -euo pipefail
umask 077
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
pg_bin=${PG_BIN:-/Library/PostgreSQL/18/bin}
for program in initdb pg_ctl createdb psql; do
  [[ -x "$pg_bin/$program" ]] || { echo "Set PG_BIN to the PostgreSQL 18 bin directory." >&2; exit 1; }
done
test_dir=$(mktemp -d /tmp/inventory-verify.XXXXXX)
started=0
cleanup() {
  if [[ "$started" == 1 ]]; then
    "$pg_bin/pg_ctl" -D "$test_dir/data" -m immediate -w stop >/dev/null || return
  fi
  [[ "$test_dir" == /tmp/inventory-verify.* ]] && rm -rf -- "$test_dir"
}
trap cleanup EXIT
"$pg_bin/initdb" -D "$test_dir/data" --username=inventory_test_admin --auth=trust --encoding=UTF8 --no-locale >"$test_dir/init.log"
# Only a Unix socket inside our private directory; no TCP listener or live server.
"$pg_bin/pg_ctl" -D "$test_dir/data" -l "$test_dir/server.log" -o "-h '' -k '$test_dir' -p 55439 -c unix_socket_permissions=0700" -w start >/dev/null
started=1
export PGHOST="$test_dir" PGPORT=55439 PGUSER=inventory_test_admin
unset PGPASSWORD PGPASSFILE PGSERVICE PGOPTIONS PGDATABASE
"$pg_bin/createdb" inventory_test_restore
"$pg_bin/psql" -X -v ON_ERROR_STOP=1 -d inventory_test_restore -f "$repo_dir/database/setup.sql" >"$test_dir/restore.log" 2>&1 || { cat "$test_dir/restore.log"; exit 1; }
"$pg_bin/psql" -X -v ON_ERROR_STOP=1 -d inventory_test_restore -f "$repo_dir/tests/smoke.sql"
# A second setup must refuse to overwrite the installed database.
if "$pg_bin/psql" -X -v ON_ERROR_STOP=1 -d inventory_test_restore -f "$repo_dir/database/setup.sql" >"$test_dir/repeat.log" 2>&1; then
  echo 'FAIL: repeat setup unexpectedly succeeded.' >&2
  exit 1
fi
if ! grep -q 'Database is not empty' "$test_dir/repeat.log"; then
  cat "$test_dir/repeat.log"
  exit 1
fi
echo 'PASS: clean restore, smoke checks, and repeat-setup refusal; live database untouched.'
