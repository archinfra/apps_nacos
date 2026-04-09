#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-aict}"
MYSQL_LABEL="${MYSQL_LABEL:-app=mysql}"
MYSQL_CONTAINER="${MYSQL_CONTAINER:-mysql}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
MYSQL_DATABASE="${MYSQL_DATABASE:-frame_nacos_demo}"
SQL_FILE="${SQL_FILE:-${ROOT_DIR}/frame_nacos_demo.sql}"
CONFIG_FILE="${CONFIG_FILE:-${ROOT_DIR}/cmict-share.yaml}"
CONFIG_DATA_ID="${CONFIG_DATA_ID:-cmict-share.yaml}"
CONFIG_GROUP="${CONFIG_GROUP:-DEFAULT_GROUP}"

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
  -n, --namespace <ns>          Kubernetes namespace, default: ${NAMESPACE}
  -l, --mysql-label <label>     MySQL pod selector, default: ${MYSQL_LABEL}
  -c, --mysql-container <name>  MySQL container name, default: ${MYSQL_CONTAINER}
  -u, --mysql-user <name>       MySQL username, default: ${MYSQL_USER}
  -p, --mysql-password <pwd>    MySQL password, required
  -d, --mysql-database <name>   MySQL database, default: ${MYSQL_DATABASE}
  -f, --sql-file <path>         Bootstrap SQL file, default: ${SQL_FILE}
  --config-file <path>          Config file to import, default: ${CONFIG_FILE}
  --config-data-id <name>       Config dataId, default: ${CONFIG_DATA_ID}
  --config-group <name>         Config group, default: ${CONFIG_GROUP}
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
      -l|--mysql-label)
        MYSQL_LABEL="$2"
        shift 2
        ;;
      -c|--mysql-container)
        MYSQL_CONTAINER="$2"
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
  [[ -n "${MYSQL_PASSWORD}" ]] || die "--mysql-password is required"
  [[ -f "${SQL_FILE}" ]] || die "missing SQL file: ${SQL_FILE}"
  [[ -f "${CONFIG_FILE}" ]] || die "missing config file: ${CONFIG_FILE}"
}

mysql_pod() {
  kubectl get pod -n "${NAMESPACE}" -l "${MYSQL_LABEL}" -o jsonpath="{.items[0].metadata.name}"
}

mysql_exec() {
  local pod_name="$1"
  shift
  kubectl exec -n "${NAMESPACE}" -c "${MYSQL_CONTAINER}" "${pod_name}" -- \
    env MYSQL_PWD="${MYSQL_PASSWORD}" mysql -u"${MYSQL_USER}" "$@"
}

mysql_exec_stdin() {
  local pod_name="$1"
  shift
  kubectl exec -i -n "${NAMESPACE}" -c "${MYSQL_CONTAINER}" "${pod_name}" -- \
    env MYSQL_PWD="${MYSQL_PASSWORD}" mysql -u"${MYSQL_USER}" "$@"
}

import_sql() {
  local pod_name="$1"
  log "Creating database ${MYSQL_DATABASE} if needed"
  mysql_exec "${pod_name}" -e "CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"

  log "Importing ${SQL_FILE}"
  mysql_exec_stdin "${pod_name}" "${MYSQL_DATABASE}" < "${SQL_FILE}"
}

import_config() {
  local pod_name="$1"
  local content_escaped
  local md5_value
  content_escaped="$(sed "s/'/''/g" "${CONFIG_FILE}")"
  md5_value="$(md5sum "${CONFIG_FILE}" | awk '{print $1}')"

  log "Upserting ${CONFIG_DATA_ID}"
  mysql_exec_stdin "${pod_name}" "${MYSQL_DATABASE}" <<SQL
REPLACE INTO config_info (
  data_id, group_id, content, md5, gmt_create, gmt_modified,
  src_user, src_ip, app_name, tenant_id, c_desc, c_use, effect, type, c_schema, encrypted_data_key
) VALUES (
  '${CONFIG_DATA_ID}', '${CONFIG_GROUP}', '${content_escaped}', '${md5_value}', NOW(), NOW(),
  'manual-import', '127.0.0.1', NULL, '', NULL, NULL, NULL, 'yaml', NULL, ''
);
SQL
}

main() {
  local pod_name
  parse_args "$@"
  require_args

  pod_name="$(mysql_pod)"
  [[ -n "${pod_name}" ]] || die "no mysql pod found with label ${MYSQL_LABEL} in namespace ${NAMESPACE}"

  log "Using MySQL pod ${pod_name}"
  import_sql "${pod_name}"
  import_config "${pod_name}"
  success "Nacos bootstrap data imported successfully"
}

main "$@"
