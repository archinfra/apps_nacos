#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-aict}"
MYSQL_NAMESPACE="${MYSQL_NAMESPACE:-${NAMESPACE}}"
MYSQL_POD="${MYSQL_POD:-}"
MYSQL_LABEL="${MYSQL_LABEL:-app=mysql}"
MYSQL_CONTAINER="${MYSQL_CONTAINER:-mysql}"
MYSQL_HOST="${MYSQL_HOST:-mysql-0.mysql.aict}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
MYSQL_DATABASE="${MYSQL_DATABASE:-frame_nacos_demo}"
SQL_FILE="${SQL_FILE:-${ROOT_DIR}/frame_nacos_demo.sql}"
CONFIG_FILE="${CONFIG_FILE:-${ROOT_DIR}/cmict-share.yaml}"
CONFIG_DATA_ID="${CONFIG_DATA_ID:-cmict-share.yaml}"
CONFIG_GROUP="${CONFIG_GROUP:-DEFAULT_GROUP}"
IMPORT_SQL="${IMPORT_SQL:-true}"
IMPORT_CONFIG="${IMPORT_CONFIG:-true}"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
  echo -e "${CYAN}[INFO]${NC} $*"
}

success() {
  echo -e "${GREEN}[OK]${NC} $*"
}

die() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  ./import-nacos.sh [options]

Options:
  -n, --namespace <ns>          App namespace, default: ${NAMESPACE}
  --mysql-namespace <ns>        MySQL pod namespace, default: ${MYSQL_NAMESPACE}
  --mysql-pod <name>            Explicit MySQL pod name, default: auto detect
  -l, --mysql-label <label>     MySQL pod selector fallback, default: ${MYSQL_LABEL}
  -c, --mysql-container <name>  MySQL container name, default: ${MYSQL_CONTAINER}
  --mysql-host <host>           MySQL host used for pod auto-detect, default: ${MYSQL_HOST}
  -u, --mysql-user <name>       MySQL username, default: ${MYSQL_USER}
  -p, --mysql-password <pwd>    MySQL password, required
  -d, --mysql-database <name>   MySQL database, default: ${MYSQL_DATABASE}
  -f, --sql-file <path>         Bootstrap SQL file, default: ${SQL_FILE}
  --config-file <path>          Config file to import, default: ${CONFIG_FILE}
  --config-data-id <name>       Config dataId, default: ${CONFIG_DATA_ID}
  --config-group <name>         Config group, default: ${CONFIG_GROUP}
  --skip-sql-import             Skip SQL bootstrap import
  --skip-config-import          Skip cmict-share import
  -h, --help                    Show this message
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--namespace)
        NAMESPACE="$2"
        shift 2
        ;;
      --mysql-namespace)
        MYSQL_NAMESPACE="$2"
        shift 2
        ;;
      --mysql-pod)
        MYSQL_POD="$2"
        shift 2
        ;;
      -l|--mysql-label)
        MYSQL_LABEL="$2"
        shift 2
        ;;
      -c|--mysql-container)
        MYSQL_CONTAINER="$2"
        shift 2
        ;;
      --mysql-host)
        MYSQL_HOST="$2"
        shift 2
        ;;
      -u|--mysql-user)
        MYSQL_USER="$2"
        shift 2
        ;;
      -p|--mysql-password)
        MYSQL_PASSWORD="$2"
        shift 2
        ;;
      -d|--mysql-database)
        MYSQL_DATABASE="$2"
        shift 2
        ;;
      -f|--sql-file)
        SQL_FILE="$2"
        shift 2
        ;;
      --config-file)
        CONFIG_FILE="$2"
        shift 2
        ;;
      --config-data-id)
        CONFIG_DATA_ID="$2"
        shift 2
        ;;
      --config-group)
        CONFIG_GROUP="$2"
        shift 2
        ;;
      --skip-sql-import)
        IMPORT_SQL="false"
        shift
        ;;
      --skip-config-import)
        IMPORT_CONFIG="false"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

require_args() {
  command -v kubectl >/dev/null 2>&1 || die "kubectl is required"
  command -v base64 >/dev/null 2>&1 || die "base64 is required"
  [[ -n "${MYSQL_PASSWORD}" ]] || die "--mysql-password is required"
  [[ "${IMPORT_SQL}" == "true" || "${IMPORT_CONFIG}" == "true" ]] || die "nothing to import; remove both skip flags"
  if [[ "${IMPORT_SQL}" == "true" ]]; then
    [[ -f "${SQL_FILE}" ]] || die "missing SQL file: ${SQL_FILE}"
  fi
  if [[ "${IMPORT_CONFIG}" == "true" ]]; then
    [[ -f "${CONFIG_FILE}" ]] || die "missing config file: ${CONFIG_FILE}"
  fi
}

sql_escape_literal() {
  printf '%s' "$1" | sed "s/'/''/g"
}

file_md5() {
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$1" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl md5 "$1" | awk '{print $2}'
  else
    die "md5sum or openssl is required"
  fi
}

pod_exists() {
  local pod_name="$1"
  kubectl get pod -n "${MYSQL_NAMESPACE}" "${pod_name}" >/dev/null 2>&1
}

resolve_mysql_pod() {
  local pod_name
  local host_candidate

  if [[ -n "${MYSQL_POD}" ]]; then
    pod_exists "${MYSQL_POD}" || die "mysql pod ${MYSQL_POD} not found in namespace ${MYSQL_NAMESPACE}"
    printf '%s\n' "${MYSQL_POD}"
    return 0
  fi

  host_candidate="${MYSQL_HOST%%.*}"
  if [[ -n "${host_candidate}" ]] && pod_exists "${host_candidate}"; then
    printf '%s\n' "${host_candidate}"
    return 0
  fi

  pod_name="$(kubectl get pod -n "${MYSQL_NAMESPACE}" -l "${MYSQL_LABEL}" -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || true)"
  [[ -n "${pod_name}" ]] || die "no mysql pod found in namespace ${MYSQL_NAMESPACE}; use --mysql-pod or adjust --mysql-label"
  printf '%s\n' "${pod_name}"
}

mysql_exec() {
  local pod_name="$1"
  shift
  kubectl exec -n "${MYSQL_NAMESPACE}" -c "${MYSQL_CONTAINER}" "${pod_name}" -- \
    env MYSQL_PWD="${MYSQL_PASSWORD}" mysql -u"${MYSQL_USER}" "$@"
}

mysql_exec_stdin() {
  local pod_name="$1"
  shift
  kubectl exec -i -n "${MYSQL_NAMESPACE}" -c "${MYSQL_CONTAINER}" "${pod_name}" -- \
    env MYSQL_PWD="${MYSQL_PASSWORD}" mysql -u"${MYSQL_USER}" "$@"
}

import_sql() {
  local pod_name="$1"
  log "Creating database ${MYSQL_DATABASE} if needed"
  mysql_exec "${pod_name}" -e "CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"

  if [[ "${IMPORT_SQL}" == "true" ]]; then
    log "Importing SQL from ${SQL_FILE}"
    mysql_exec_stdin "${pod_name}" "${MYSQL_DATABASE}" < "${SQL_FILE}"
  else
    log "Skipping SQL bootstrap import"
  fi
}

import_config() {
  local pod_name="$1"
  local config_b64
  local md5_value
  local data_id_sql
  local group_sql
  local temp_sql

  if [[ "${IMPORT_CONFIG}" != "true" ]]; then
    log "Skipping cmict-share import"
    return 0
  fi

  config_b64="$(base64 "${CONFIG_FILE}" | tr -d '\r\n')"
  md5_value="$(file_md5 "${CONFIG_FILE}")"
  data_id_sql="$(sql_escape_literal "${CONFIG_DATA_ID}")"
  group_sql="$(sql_escape_literal "${CONFIG_GROUP}")"
  temp_sql="$(mktemp)"

  cat > "${temp_sql}" <<SQL
REPLACE INTO config_info (
  data_id, group_id, content, md5, gmt_create, gmt_modified,
  src_user, src_ip, app_name, tenant_id, c_desc, c_use, effect, type, c_schema, encrypted_data_key
) VALUES (
  '${data_id_sql}', '${group_sql}',
  CONVERT(FROM_BASE64('${config_b64}') USING utf8mb4),
  '${md5_value}', NOW(), NOW(),
  'manual-import', '127.0.0.1', NULL, '', NULL, NULL, NULL, 'yaml', NULL, ''
);
SQL

  log "Upserting ${CONFIG_DATA_ID}"
  mysql_exec_stdin "${pod_name}" "${MYSQL_DATABASE}" < "${temp_sql}"
  rm -f "${temp_sql}"
}

main() {
  local pod_name
  parse_args "$@"
  require_args

  pod_name="$(resolve_mysql_pod)"
  log "Using MySQL pod ${pod_name} in namespace ${MYSQL_NAMESPACE}"
  import_sql "${pod_name}"
  import_config "${pod_name}"
  success "Nacos bootstrap data imported successfully"
}

main "$@"
