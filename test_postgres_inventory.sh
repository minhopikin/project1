#!/usr/bin/env bash
# Standalone LOCAL PostgreSQL / EDB inventory test: Bash + psql, no Python/JSON.
# Run once per instance from the Linux shell on its database server.
# Reads metadata only. Does not connect to SQL Server or register in DBPortal.
# Examples:
#   PGPORT=7432 PGUSER=enterprisedb bash test_postgres_inventory.sh
#   PSQL_BIN=/usr/edb/as16/bin/psql PGHOST=/tmp PGPORT=7432 \
#       PGUSER=enterprisedb bash test_postgres_inventory.sh > inventory.txt
# PGHOST must be a LOCAL socket directory; when unset libpq uses default sockets.
# Authenticate with peer auth or a protected .pgpass/PGPASSFILE; no password in script.
# Optional display-only business metadata:
#   INSTANCE_NAME=enterprisedb APPLICATION_NAME='Your application' \
#   APPLICATION_CONTACT_KEY='<CONTACT_KEY>' BAI_ID='<BAI_ID>' ENVIRONMENT=Development
# Applications may differ by database: these values are not inferred or auto-linked.
set -euo pipefail
umask 077

psql_bin="${PSQL_BIN:-psql}"
if ! command -v "$psql_bin" >/dev/null 2>&1; then
    if [[ -z "${PSQL_BIN:-}" && -x /usr/edb/as16/bin/psql ]]; then
        psql_bin=/usr/edb/as16/bin/psql
    else
        printf '%s\n' 'ERROR: psql not found. Set PSQL_BIN to its installed path.' >&2
        exit 2
    fi
fi
if [[ -n "${PGHOST:-}" && "${PGHOST}" != /* ]]; then
    printf '%s\n' 'ERROR: Set PGHOST to a local Unix socket directory, or unset it. TCP hosts are rejected.' >&2
    exit 2
fi
if [[ -n "${PGSERVICE:-}" || -n "${PGHOSTADDR:-}" ]]; then
    printf '%s\n' 'ERROR: Unset PGSERVICE and PGHOSTADDR to ensure collection stays local.' >&2
    exit 2
fi
if [[ "${PGDATABASE:-postgres}" == *'='* || "${PGDATABASE:-postgres}" == *'://'* ]]; then
    printf '%s\n' 'ERROR: PGDATABASE must be a database name, not a connection string.' >&2
    exit 2
fi
if [[ -n "${PGPORT:-}" && ! "${PGPORT}" =~ ^[0-9]+$ ]]; then
    printf '%s\n' 'ERROR: PGPORT must be numeric.' >&2
    exit 2
fi

printf '%s\n' 'POSTGRESQL LOCAL INVENTORY TEST'
printf 'Collected at (UTC): %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S')"
printf 'Host FQDN: %s\n' "$(hostname -f 2>/dev/null || hostname)"
printf 'Host addresses (verify registered IP): %s\n' "$(hostname -I 2>/dev/null || printf 'Unavailable')"
printf 'Kernel: %s\n' "$(uname -sr)"
if [[ -r /etc/os-release ]]; then
    awk -F= '$1=="PRETTY_NAME" {v=substr($0,index($0,"=")+1); gsub(/^"|"$/,"",v); print "Operating system: " v}' /etc/os-release
fi
printf 'Portal instance name (supplied): %s\n' "${INSTANCE_NAME:-<INSTANCE_NAME>}"
printf 'Environment (supplied): %s\n' "${ENVIRONMENT:-<ENVIRONMENT>}"
printf 'Application (supplied; confirm per database): %s\n' "${APPLICATION_NAME:-<APPLICATION_NAME>}"
printf 'Application contact (supplied): %s\n' "${APPLICATION_CONTACT_KEY:-<CONTACT_KEY>}"
printf 'BAI ID (supplied): %s\n' "${BAI_ID:-<BAI_ID>}"
printf '\n%s\n' 'Querying the selected local instance. Connection errors mean collection is incomplete.'

# Fixed read-only SQL. -X ignores .psqlrc; -w avoids unattended password prompts.
# No privileged data-directory/settings query or database-size scans are performed.
PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}" \
PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=15000' \
"$psql_bin" -X -w -v ON_ERROR_STOP=1 -P pager=off -d "${PGDATABASE:-postgres}" <<'SQL'
\echo INSTANCE DETAILS
SELECT current_setting('server_version') AS server_version,
       current_setting('port') AS server_port,
       current_setting('cluster_name', true) AS configured_cluster_name,
       pg_is_in_recovery() AS in_recovery,
       pg_postmaster_start_time() AS started_at,
       current_database() AS connected_database,
       current_user AS collector_role;
\echo DATABASE DETAILS (includes template0 and template1)
SELECT datname AS database_name,
       pg_get_userbyid(datdba) AS database_owner,
       pg_encoding_to_char(encoding) AS encoding,
       datistemplate AS is_template,
       datallowconn AS allows_connections
FROM pg_database
ORDER BY datname;
SQL
printf '\n%s\n' 'Collection completed. Application/BAI/contact values above are supplied metadata, not discovered facts.'
