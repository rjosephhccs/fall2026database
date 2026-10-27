#!/usr/bin/env bash
set -euo pipefail
umask 077
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
pg_bin=${PG_BIN:-/Library/PostgreSQL/18/bin}
: "${PGDATABASE:?Set PGDATABASE to the intended source database name.}"
: "${PGUSER:?Set PGUSER to your existing database administrator role.}"
[[ "$PGDATABASE" != *://* ]] || { echo 'Use a database name, not a connection URL.' >&2; exit 1; }
[[ -x "$pg_bin/pg_dump" ]] || { echo 'Set PG_BIN to the PostgreSQL bin directory.' >&2; exit 1; }
mkdir -p "$repo_dir/.private/exports"
output_file=$(mktemp "$repo_dir/.private/exports/schema.XXXXXX")
if ! "$pg_bin/pg_dump" --host="${PGHOST:-localhost}" --port="${PGPORT:-5432}" \
  --username="$PGUSER" --dbname="$PGDATABASE" --password --format=plain \
  --schema-only --no-tablespaces --no-publications --no-subscriptions \
  --no-security-labels --lock-wait-timeout=10s --file="$output_file"; then
  rm -f -- "$output_file"
  exit 1
fi
echo "Private schema export saved to: $output_file"
echo 'Review function bodies, defaults, comments, owners, and grants before publishing.'
