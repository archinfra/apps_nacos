#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAME="nacos"
APP_VERSION="0.1.4"
PACKAGE_PROFILE="integrated"
WORKDIR="/tmp/${APP_NAME}-installer"
IMAGE_DIR="${WORKDIR}/images"
MANIFEST_DIR="${WORKDIR}/manifests"
BOOTSTRAP_DIR="${WORKDIR}/bootstrap"
IMAGE_INDEX="${IMAGE_DIR}/image-index.tsv"
YAML_FILE="${MANIFEST_DIR}/nacos.yaml"
BOOTSTRAP_SQL_FILE="${BOOTSTRAP_DIR}/frame_nacos_demo.sql"
CMICT_SHARE_FILE="${BOOTSTRAP_DIR}/cmict-share.yaml"

IMAGE_NAME="nacos-server"
IMAGE_TAG="v2.3.0-slim"

ACTION="help"
NAMESPACE="aict"
REPLICAS="1"
MYSQL_HOST="mysql-0.mysql.aict"
MYSQL_PORT="3306"
MYSQL_DATABASE="frame_nacos_demo"
MYSQL_USER="root"
MYSQL_PASSWORD=""
REGISTRY_REPO="sealos.hub:5000/kube4"
REGISTRY_REPO_EXPLICIT="false"
IMAGE="${REGISTRY_REPO}/${IMAGE_NAME}:${IMAGE_TAG}"
IMAGE_SPECIFIED="false"
REGISTRY_USER=""
REGISTRY_PASSWORD=""
SKIP_IMAGE_PREPARE="false"
IMAGE_PULL_POLICY="IfNotPresent"
ENABLE_METRICS="true"
ENABLE_SERVICEMONITOR="true"
SERVICE_MONITOR_NAMESPACE=""
SERVICE_MONITOR_INTERVAL="30s"
SERVICE_MONITOR_SCRAPE_TIMEOUT="10s"
WAIT_TIMEOUT="10m"
NODE_PORT="30094"
ENABLE_DB_BOOTSTRAP="true"
ENABLE_CMICT_SHARE_IMPORT="true"
CMICT_SHARE_DATA_ID="cmict-share.yaml"
CMICT_SHARE_GROUP="DEFAULT_GROUP"
AUTO_YES="false"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

NACOS_IMAGE_REF=""
MYSQL_HELPER_IMAGE_REF=""

log() {
  echo -e "${CYAN}[INFO]${NC} $*"
}

success() {
  echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

die() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
  exit 1
}

section() {
  echo
  echo -e "${BLUE}${BOLD}============================================================${NC}"
  echo -e "${BLUE}${BOLD}$*${NC}"
  echo -e "${BLUE}${BOLD}============================================================${NC}"
}

program_name() {
  basename "$0"
}

refresh_default_image() {
  if [[ "${IMAGE_SPECIFIED}" != "true" ]]; then
    IMAGE="${REGISTRY_REPO}/${IMAGE_NAME}:${IMAGE_TAG}"
  fi
}

usage() {
  local cmd="./$(program_name)"
  cat <<EOF
Usage:
  ${cmd} <install|uninstall|status|help> [options]
  ${cmd} -h|--help

Actions:
  install       Prepare image and install or upgrade Nacos
  uninstall     Remove Nacos resources from the namespace
  status        Show Deployment and Service status
  help          Show this message

Core options:
  -n, --namespace <ns>                 Namespace, default: ${NAMESPACE}
  --replicas <num>                     Replica count, default: ${REPLICAS}
  --mysql-host <host>                  MySQL host, default: ${MYSQL_HOST}
  --mysql-port <port>                  MySQL port, default: ${MYSQL_PORT}
  --mysql-database <name>              MySQL database, default: ${MYSQL_DATABASE}
  --mysql-user <name>                  MySQL user, default: ${MYSQL_USER}
  --mysql-password <pwd>               MySQL password, required for install
  --node-port <port>                   Nacos 8848 NodePort, default: ${NODE_PORT}
  --image <image>                      Override Nacos image
  --registry <repo>                    Target registry repo prefix, default: ${REGISTRY_REPO}
  --registry-user <user>               Optional docker registry username
  --registry-password <password>       Optional docker registry password
  --image-pull-policy <policy>         Always|IfNotPresent|Never, default: ${IMAGE_PULL_POLICY}
  --skip-image-prepare                 Reuse images already present in the target registry
  --wait-timeout <duration>            Rollout wait timeout, default: ${WAIT_TIMEOUT}
  -y, --yes                            Skip confirmation

Monitoring:
  --enable-metrics                     Enable Nacos Prometheus endpoint, default: ${ENABLE_METRICS}
  --disable-metrics                    Disable Nacos Prometheus endpoint
  --enable-servicemonitor              Create ServiceMonitor, default: ${ENABLE_SERVICEMONITOR}
  --disable-servicemonitor             Disable ServiceMonitor
  --service-monitor-namespace <ns>     Namespace for ServiceMonitor, default: app namespace
  --service-monitor-interval <value>   ServiceMonitor interval, default: ${SERVICE_MONITOR_INTERVAL}
  --service-monitor-scrape-timeout <v> ServiceMonitor scrape timeout, default: ${SERVICE_MONITOR_SCRAPE_TIMEOUT}

Bootstrap:
  --enable-db-bootstrap                Initialize standard Nacos tables and baseline data, default: ${ENABLE_DB_BOOTSTRAP}
  --disable-db-bootstrap               Skip SQL bootstrap
  --enable-cmict-share-import          Import ${CMICT_SHARE_DATA_ID} baseline config, default: ${ENABLE_CMICT_SHARE_IMPORT}
  --disable-cmict-share-import         Skip ${CMICT_SHARE_DATA_ID} import
  --cmict-share-data-id <name>         Default: ${CMICT_SHARE_DATA_ID}
  --cmict-share-group <name>           Default: ${CMICT_SHARE_GROUP}

Examples:
  ${cmd} install --mysql-password '<MYSQL_PASSWORD>' -y
  ${cmd} install --mysql-host ${MYSQL_HOST} --mysql-password '<MYSQL_PASSWORD>' -y
  ${cmd} install --disable-db-bootstrap --mysql-password '<MYSQL_PASSWORD>' -y
  ${cmd} status -n ${NAMESPACE}
  ${cmd} uninstall -n ${NAMESPACE} -y
EOF
}

parse_args() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 0
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      install|uninstall|status|help)
        ACTION="$1"
        shift
        ;;
      -n|--namespace)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        NAMESPACE="$2"
        shift 2
        ;;
      --replicas)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        REPLICAS="$2"
        shift 2
        ;;
      --mysql-host)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        MYSQL_HOST="$2"
        shift 2
        ;;
      --mysql-port)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        MYSQL_PORT="$2"
        shift 2
        ;;
      --mysql-database)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        MYSQL_DATABASE="$2"
        shift 2
        ;;
      --mysql-user)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        MYSQL_USER="$2"
        shift 2
        ;;
      --mysql-password)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        MYSQL_PASSWORD="$2"
        shift 2
        ;;
      --node-port)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        NODE_PORT="$2"
        shift 2
        ;;
      --image)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        IMAGE="$2"
        IMAGE_SPECIFIED="true"
        shift 2
        ;;
      --registry)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        REGISTRY_REPO="$2"
        REGISTRY_REPO_EXPLICIT="true"
        refresh_default_image
        shift 2
        ;;
      --registry-user)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        REGISTRY_USER="$2"
        shift 2
        ;;
      --registry-password)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        REGISTRY_PASSWORD="$2"
        shift 2
        ;;
      --image-pull-policy)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        IMAGE_PULL_POLICY="$2"
        shift 2
        ;;
      --skip-image-prepare)
        SKIP_IMAGE_PREPARE="true"
        shift
        ;;
      --wait-timeout)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        WAIT_TIMEOUT="$2"
        shift 2
        ;;
      --enable-metrics)
        ENABLE_METRICS="true"
        shift
        ;;
      --disable-metrics)
        ENABLE_METRICS="false"
        ENABLE_SERVICEMONITOR="false"
        shift
        ;;
      --enable-servicemonitor)
        ENABLE_SERVICEMONITOR="true"
        ENABLE_METRICS="true"
        shift
        ;;
      --disable-servicemonitor)
        ENABLE_SERVICEMONITOR="false"
        shift
        ;;
      --service-monitor-namespace)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        SERVICE_MONITOR_NAMESPACE="$2"
        shift 2
        ;;
      --service-monitor-interval)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        SERVICE_MONITOR_INTERVAL="$2"
        shift 2
        ;;
      --service-monitor-scrape-timeout)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        SERVICE_MONITOR_SCRAPE_TIMEOUT="$2"
        shift 2
        ;;
      --enable-db-bootstrap)
        ENABLE_DB_BOOTSTRAP="true"
        shift
        ;;
      --disable-db-bootstrap)
        ENABLE_DB_BOOTSTRAP="false"
        shift
        ;;
      --enable-cmict-share-import)
        ENABLE_CMICT_SHARE_IMPORT="true"
        shift
        ;;
      --disable-cmict-share-import)
        ENABLE_CMICT_SHARE_IMPORT="false"
        shift
        ;;
      --cmict-share-data-id)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        CMICT_SHARE_DATA_ID="$2"
        shift 2
        ;;
      --cmict-share-group)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        CMICT_SHARE_GROUP="$2"
        shift 2
        ;;
      -y|--yes)
        AUTO_YES="true"
        shift
        ;;
      -h|--help)
        ACTION="help"
        shift
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done

  refresh_default_image
}

require_install_args() {
  [[ -n "${MYSQL_PASSWORD}" ]] || die "--mysql-password is required for install"
}

validate_config() {
  [[ "${NODE_PORT}" =~ ^[0-9]+$ ]] || die "--node-port must be a number"
  if (( NODE_PORT < 30000 || NODE_PORT > 32767 )); then
    die "--node-port must be between 30000 and 32767"
  fi
  [[ -n "${CMICT_SHARE_DATA_ID}" ]] || die "--cmict-share-data-id must not be empty"
  [[ -n "${CMICT_SHARE_GROUP}" ]] || die "--cmict-share-group must not be empty"
}

check_deps() {
  command -v kubectl >/dev/null 2>&1 || die "kubectl is required"

  if [[ "${ACTION}" == "install" && "${SKIP_IMAGE_PREPARE}" != "true" ]]; then
    command -v docker >/dev/null 2>&1 || die "docker is required unless --skip-image-prepare is used"
  fi
}

confirm() {
  [[ "${AUTO_YES}" == "true" ]] && return

  echo
  echo "Action: ${ACTION}"
  echo "Namespace: ${NAMESPACE}"
  echo "Replicas: ${REPLICAS}"
  echo "MySQL: ${MYSQL_USER}@${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DATABASE}"
  echo "NodePort: ${NODE_PORT}"
  echo "Image: ${IMAGE}"
  echo "Enable metrics: ${ENABLE_METRICS}"
  echo "Enable ServiceMonitor: ${ENABLE_SERVICEMONITOR}"
  echo "Enable DB bootstrap: ${ENABLE_DB_BOOTSTRAP}"
  echo "Enable cmict-share import: ${ENABLE_CMICT_SHARE_IMPORT}"
  echo "Skip image prepare: ${SKIP_IMAGE_PREPARE}"
  echo
  read -r -p "Continue? [y/N] " answer
  [[ "${answer}" =~ ^[Yy]$ ]] || die "Aborted"
}

payload_start_offset() {
  local marker_line payload_offset skip_bytes byte_hex
  marker_line="$(awk '/^__PAYLOAD_BELOW__$/ { print NR; exit }' "$0")"
  [[ -n "${marker_line}" ]] || return 1
  payload_offset="$(( $(head -n "${marker_line}" "$0" | wc -c | tr -d ' ') + 1 ))"

  skip_bytes=0
  while :; do
    byte_hex="$(dd if="$0" bs=1 skip="$((payload_offset + skip_bytes - 1))" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    case "${byte_hex}" in
      0a|0d)
        skip_bytes=$((skip_bytes + 1))
        ;;
      "")
        return 1
        ;;
      *)
        break
        ;;
    esac
  done

  printf '%s' "$((payload_offset + skip_bytes))"
}

extract_payload() {
  local offset
  section "Extract Payload"
  rm -rf "${WORKDIR}"
  mkdir -p "${IMAGE_DIR}" "${MANIFEST_DIR}" "${BOOTSTRAP_DIR}"

  offset="$(payload_start_offset)" || die "failed to find payload marker"
  tail -c +"${offset}" "$0" | tar -xzf - -C "${WORKDIR}" || die "failed to extract payload"

  [[ -f "${YAML_FILE}" ]] || die "missing manifest file"
  [[ -f "${IMAGE_INDEX}" ]] || die "missing image index"
  [[ -f "${BOOTSTRAP_SQL_FILE}" ]] || die "missing bootstrap SQL file"
  [[ -f "${CMICT_SHARE_FILE}" ]] || die "missing cmict-share config file"
}

target_registry_host() {
  local image_ref="$1"
  local first_segment="${image_ref%%/*}"
  if [[ "${image_ref}" == */* && ( "${first_segment}" == *.* || "${first_segment}" == *:* || "${first_segment}" == "localhost" ) ]]; then
    printf '%s\n' "${first_segment}"
  fi
}

docker_login_if_needed() {
  local registry_host="$1"
  [[ -n "${registry_host}" ]] || return 0
  [[ -n "${REGISTRY_USER}" ]] || return 0
  [[ -n "${REGISTRY_PASSWORD}" ]] || return 0

  log "logging into registry ${registry_host}"
  printf '%s' "${REGISTRY_PASSWORD}" | docker login "${registry_host}" --username "${REGISTRY_USER}" --password-stdin >/dev/null
}

target_ref_from_default() {
  local default_ref="$1"
  local suffix="${default_ref##*/}"
  printf '%s/%s\n' "${REGISTRY_REPO}" "${suffix}"
}

resolve_target_ref() {
  local tar_name="$1"
  local default_ref="$2"
  case "${tar_name}" in
    nacos-server-*.tar)
      printf '%s\n' "${IMAGE}"
      ;;
    mysql-client-*.tar)
      target_ref_from_default "${default_ref}"
      ;;
    *)
      target_ref_from_default "${default_ref}"
      ;;
  esac
}

load_image_metadata() {
  while IFS=$'\t' read -r tar_name _pull_ref default_target_ref _platform; do
    [[ -n "${tar_name}" ]] || continue
    case "${tar_name}" in
      nacos-server-*.tar)
        NACOS_IMAGE_REF="$(resolve_target_ref "${tar_name}" "${default_target_ref}")"
        ;;
      mysql-client-*.tar)
        MYSQL_HELPER_IMAGE_REF="$(resolve_target_ref "${tar_name}" "${default_target_ref}")"
        ;;
    esac
  done < "${IMAGE_INDEX}"

  [[ -n "${NACOS_IMAGE_REF}" ]] || die "failed to resolve nacos image"
  [[ -n "${MYSQL_HELPER_IMAGE_REF}" ]] || die "failed to resolve mysql helper image"
}

prepare_images() {
  local registry_host
  if [[ "${SKIP_IMAGE_PREPARE}" == "true" ]]; then
    log "skipping image preparation because --skip-image-prepare was requested"
    return 0
  fi

  registry_host="$(target_registry_host "${NACOS_IMAGE_REF}")"
  docker_login_if_needed "${registry_host}"

  while IFS=$'\t' read -r tar_name _pull_ref load_ref _platform; do
    local target_ref
    [[ -n "${tar_name}" ]] || continue
    target_ref="$(resolve_target_ref "${tar_name}" "${load_ref}")"
    [[ -f "${IMAGE_DIR}/${tar_name}" ]] || die "missing image archive ${tar_name}"
    log "loading ${tar_name}"
    docker load -i "${IMAGE_DIR}/${tar_name}" >/dev/null
    if [[ "${load_ref}" != "${target_ref}" ]]; then
      log "tagging ${load_ref} -> ${target_ref}"
      docker tag "${load_ref}" "${target_ref}"
    fi
    log "pushing ${target_ref}"
    docker push "${target_ref}" >/dev/null
  done < "${IMAGE_INDEX}"
}

ensure_namespace() {
  kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${NAMESPACE}" >/dev/null
}

check_service_monitor_support() {
  if [[ "${ENABLE_SERVICEMONITOR}" != "true" ]]; then
    return 0
  fi

  if ! kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
    warn "ServiceMonitor CRD not found, disabling ServiceMonitor creation"
    ENABLE_SERVICEMONITOR="false"
  fi
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&|\\]/\\&/g'
}

mysql_jdbc_url() {
  printf 'jdbc:mysql://%s:%s/%s?characterEncoding=utf8&connectTimeout=1000&socketTimeout=3000&autoReconnect=true&useUnicode=true&useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true' \
    "${MYSQL_HOST}" "${MYSQL_PORT}" "${MYSQL_DATABASE}"
}

service_monitor_namespace() {
  if [[ -n "${SERVICE_MONITOR_NAMESPACE}" ]]; then
    printf '%s\n' "${SERVICE_MONITOR_NAMESPACE}"
  else
    printf '%s\n' "${NAMESPACE}"
  fi
}

job_logs_or_warn() {
  local job_name="$1"
  kubectl logs -n "${NAMESPACE}" "job/${job_name}" --all-containers=true 2>/dev/null || true
}

wait_for_job() {
  local job_name="$1"
  if ! kubectl wait -n "${NAMESPACE}" --for=condition=complete "job/${job_name}" --timeout="${WAIT_TIMEOUT}"; then
    job_logs_or_warn "${job_name}"
    die "job ${job_name} did not complete successfully"
  fi
}

bootstrap_database() {
  local cm_name="nacos-bootstrap-assets"
  local secret_name="nacos-bootstrap-db-auth"
  local job_name="nacos-db-bootstrap"

  if [[ "${ENABLE_DB_BOOTSTRAP}" != "true" && "${ENABLE_CMICT_SHARE_IMPORT}" != "true" ]]; then
    return 0
  fi

  section "Bootstrap Nacos Database"
  kubectl delete job "${job_name}" -n "${NAMESPACE}" --ignore-not-found --wait >/dev/null 2>&1 || true
  kubectl create secret generic "${secret_name}" \
    -n "${NAMESPACE}" \
    --from-literal=mysql-host="${MYSQL_HOST}" \
    --from-literal=mysql-port="${MYSQL_PORT}" \
    --from-literal=mysql-database="${MYSQL_DATABASE}" \
    --from-literal=mysql-user="${MYSQL_USER}" \
    --from-literal=mysql-password="${MYSQL_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl create configmap "${cm_name}" \
    -n "${NAMESPACE}" \
    --from-file=frame_nacos_demo.sql="${BOOTSTRAP_SQL_FILE}" \
    --from-file=cmict-share.yaml="${CMICT_SHARE_FILE}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
  namespace: ${NAMESPACE}
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: mysql-bootstrap
        image: ${MYSQL_HELPER_IMAGE_REF}
        imagePullPolicy: ${IMAGE_PULL_POLICY}
        env:
        - name: MYSQL_HOST
          valueFrom:
            secretKeyRef:
              name: ${secret_name}
              key: mysql-host
        - name: MYSQL_PORT
          valueFrom:
            secretKeyRef:
              name: ${secret_name}
              key: mysql-port
        - name: MYSQL_DATABASE
          valueFrom:
            secretKeyRef:
              name: ${secret_name}
              key: mysql-database
        - name: MYSQL_USER
          valueFrom:
            secretKeyRef:
              name: ${secret_name}
              key: mysql-user
        - name: MYSQL_PWD
          valueFrom:
            secretKeyRef:
              name: ${secret_name}
              key: mysql-password
        command:
        - /bin/sh
        - -ec
        - |
          mysql --protocol=TCP -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" -e "CREATE DATABASE IF NOT EXISTS \\\`${MYSQL_DATABASE}\\\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
          if [ '${ENABLE_DB_BOOTSTRAP}' = 'true' ]; then
            mysql --protocol=TCP -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" "${MYSQL_DATABASE}" < /bootstrap/frame_nacos_demo.sql
          fi
          if [ '${ENABLE_CMICT_SHARE_IMPORT}' = 'true' ]; then
            CMICT_SHARE_CONTENT="\$(sed \"s/'/''/g\" /bootstrap/cmict-share.yaml)"
            CMICT_SHARE_MD5="\$(md5sum /bootstrap/cmict-share.yaml | awk '{print \$1}')"
            mysql --protocol=TCP -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" "${MYSQL_DATABASE}" --execute="
              REPLACE INTO config_info (
                data_id, group_id, content, md5, gmt_create, gmt_modified,
                src_user, src_ip, app_name, tenant_id, c_desc, c_use, effect, type, c_schema, encrypted_data_key
              ) VALUES (
                '${CMICT_SHARE_DATA_ID}', '${CMICT_SHARE_GROUP}', '\${CMICT_SHARE_CONTENT}', '\${CMICT_SHARE_MD5}', NOW(), NOW(),
                'nacos-installer', '127.0.0.1', NULL, '', NULL, NULL, NULL, 'yaml', NULL, ''
              );
            "
          fi
        volumeMounts:
        - name: bootstrap-assets
          mountPath: /bootstrap
      volumes:
      - name: bootstrap-assets
        configMap:
          name: ${cm_name}
EOF

  wait_for_job "${job_name}"
  success "Nacos bootstrap data is ready"
}

render_yaml() {
  local sm_namespace
  local metrics_line
  local metrics_enabled_value
  local rendered

  sm_namespace="$(service_monitor_namespace)"
  if [[ "${ENABLE_METRICS}" == "true" ]]; then
    metrics_line='management.endpoints.web.exposure.include=*'
    metrics_enabled_value='true'
  else
    metrics_line='#management.endpoints.web.exposure.include=*'
    metrics_enabled_value='false'
  fi

  rendered="$(
    awk -v sm_enabled="${ENABLE_SERVICEMONITOR}" '
      /#__FEATURE_SERVICE_MONITOR_START__/ { in_sm=1; next }
      /#__FEATURE_SERVICE_MONITOR_END__/ { in_sm=0; next }
      in_sm && sm_enabled != "true" { next }
      { print }
    ' "${YAML_FILE}"
  )"

  printf '%s' "${rendered}" | sed \
    -e "s|__NAMESPACE__|$(escape_sed_replacement "${NAMESPACE}")|g" \
    -e "s|__REPLICAS__|$(escape_sed_replacement "${REPLICAS}")|g" \
    -e "s|__MYSQL_JDBC_URL__|$(escape_sed_replacement "$(mysql_jdbc_url)")|g" \
    -e "s|__MYSQL_USER__|$(escape_sed_replacement "${MYSQL_USER}")|g" \
    -e "s|__MYSQL_PASSWORD__|$(escape_sed_replacement "${MYSQL_PASSWORD}")|g" \
    -e "s|__NODE_PORT__|$(escape_sed_replacement "${NODE_PORT}")|g" \
    -e "s|__IMAGE__|$(escape_sed_replacement "${IMAGE}")|g" \
    -e "s|__IMAGE_PULL_POLICY__|$(escape_sed_replacement "${IMAGE_PULL_POLICY}")|g" \
    -e "s|__MANAGEMENT_ENDPOINTS_EXPOSURE_INCLUDE__|$(escape_sed_replacement "${metrics_line}")|g" \
    -e "s|__PROMETHEUS_METRICS_ENABLED__|$(escape_sed_replacement "${metrics_enabled_value}")|g" \
    -e "s|__SERVICE_MONITOR_NAMESPACE__|$(escape_sed_replacement "${sm_namespace}")|g" \
    -e "s|__SERVICE_MONITOR_INTERVAL__|$(escape_sed_replacement "${SERVICE_MONITOR_INTERVAL}")|g" \
    -e "s|__SERVICE_MONITOR_SCRAPE_TIMEOUT__|$(escape_sed_replacement "${SERVICE_MONITOR_SCRAPE_TIMEOUT}")|g"
}

wait_for_rollout() {
  section "Wait For Nacos"
  kubectl rollout status deployment/nacos -n "${NAMESPACE}" --timeout="${WAIT_TIMEOUT}"
}

install_app() {
  require_install_args
  confirm
  extract_payload
  load_image_metadata
  prepare_images
  ensure_namespace
  bootstrap_database
  check_service_monitor_support

  section "Install Nacos"
  render_yaml | kubectl apply -n "${NAMESPACE}" -f -
  wait_for_rollout
  success "Nacos is ready"
}

uninstall_app() {
  confirm
  section "Uninstall Nacos"
  kubectl delete deployment/nacos -n "${NAMESPACE}" --ignore-not-found
  kubectl delete service/nacos -n "${NAMESPACE}" --ignore-not-found
  kubectl delete configmap/nacos -n "${NAMESPACE}" --ignore-not-found
  kubectl delete configmap/nacos-config -n "${NAMESPACE}" --ignore-not-found
  kubectl delete configmap/nacos-bootstrap-assets -n "${NAMESPACE}" --ignore-not-found
  kubectl delete secret/nacos-bootstrap-db-auth -n "${NAMESPACE}" --ignore-not-found
  kubectl delete job/nacos-db-bootstrap -n "${NAMESPACE}" --ignore-not-found
  kubectl delete servicemonitor/nacos -n "$(service_monitor_namespace)" --ignore-not-found
  success "Nacos resources removed from ${NAMESPACE}"
}

status_app() {
  section "Nacos Status"
  kubectl get deployment,service,configmap,pods -n "${NAMESPACE}" -l app=nacos 2>/dev/null || true
  kubectl get job -n "${NAMESPACE}" nacos-db-bootstrap 2>/dev/null || true
  if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
    kubectl get servicemonitor -n "$(service_monitor_namespace)" nacos 2>/dev/null || true
  fi
}

main() {
  parse_args "$@"

  case "${ACTION}" in
    help)
      usage
      exit 0
      ;;
    install|uninstall|status)
      ;;
    *)
      die "Unsupported action: ${ACTION}"
      ;;
  esac

  check_deps
  validate_config

  case "${ACTION}" in
    install) install_app ;;
    uninstall) uninstall_app ;;
    status) status_app ;;
  esac
}

main "$@"
exit 0

__PAYLOAD_BELOW__
