#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAME="nacos"
APP_VERSION="0.1.8"
PACKAGE_PROFILE="integrated"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
TMP_DIR="${ROOT_DIR}/.build-tmp"
INSTALLER_STUB="${ROOT_DIR}/install.sh"
MANIFESTS_DIR="${ROOT_DIR}/manifests"
IMAGES_DIR="${ROOT_DIR}/images"
IMAGE_JSON="${IMAGES_DIR}/image.json"
BOOTSTRAP_SQL="${ROOT_DIR}/frame_nacos_demo.sql"
BOOTSTRAP_CONFIG="${ROOT_DIR}/cmict-share.yaml"
IMPORT_SCRIPT="${ROOT_DIR}/import-nacos.sh"

ARCHES=()

log() {
  printf '[INFO] %s\n' "$*"
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  ./build.sh [--arch amd64|arm64|all]

Options:
  --arch <arch>   Build installer for amd64, arm64 or all (default: all)
  -h, --help      Show this message
EOF
}

parse_args() {
  local arch="all"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --arch)
        [[ $# -ge 2 ]] || die "--arch requires a value"
        arch="$2"
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

  case "${arch}" in
    amd64|arm64)
      ARCHES=("${arch}")
      ;;
    all)
      ARCHES=("amd64" "arm64")
      ;;
    *)
      die "Unsupported arch: ${arch}"
      ;;
  esac
}

check_prereqs() {
  command -v docker >/dev/null 2>&1 || die "docker is required"
  command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 || die "python or python3 is required"
  [[ -f "${INSTALLER_STUB}" ]] || die "missing install.sh"
  [[ -d "${MANIFESTS_DIR}" ]] || die "missing manifests/"
  [[ -f "${IMAGE_JSON}" ]] || die "missing images/image.json"
  [[ -f "${BOOTSTRAP_SQL}" ]] || die "missing frame_nacos_demo.sql"
  [[ -f "${BOOTSTRAP_CONFIG}" ]] || die "missing cmict-share.yaml"
  [[ -f "${IMPORT_SCRIPT}" ]] || die "missing import-nacos.sh"
  grep -q '^__PAYLOAD_BELOW__$' "${INSTALLER_STUB}" || die "install.sh must end with __PAYLOAD_BELOW__ marker"
}

python_cmd() {
  if command -v python >/dev/null 2>&1; then
    printf 'python'
  else
    printf 'python3'
  fi
}

escape_tsv() {
  printf '%s' "$1" | tr '\t' ' '
}

generate_image_index() {
  local arch="$1"
  local output="$2"
  "$(python_cmd)" - "${IMAGE_JSON}" "${arch}" > "${output}" <<'PY'
import json
import sys

image_json = sys.argv[1]
arch = sys.argv[2]

with open(image_json, "r", encoding="utf-8") as fh:
    items = json.load(fh)

matched = [item for item in items if item.get("arch") == arch]
if not matched:
    raise SystemExit(f"no image metadata for arch={arch}")

for item in matched:
    print("\t".join([
        item["tar"],
        item["pull"],
        item["tag"],
        item["platform"],
    ]))
PY
}

build_arch() {
  local arch="$1"
  local workdir="${TMP_DIR}/${arch}"
  local payload_dir="${workdir}/payload"
  local payload_file="${workdir}/payload.tar.gz"
  local image_index="${payload_dir}/images/image-index.tsv"
  local installer_name="nacos-installer-${arch}.run"
  local installer_path="${DIST_DIR}/${installer_name}"

  log "building ${installer_name}"
  rm -rf "${workdir}"
  mkdir -p "${payload_dir}/images" "${payload_dir}/manifests" "${payload_dir}/bootstrap" "${payload_dir}/tools" "${DIST_DIR}"

  cp -R "${MANIFESTS_DIR}/." "${payload_dir}/manifests/"
  cp "${IMAGE_JSON}" "${payload_dir}/images/image.json"
  cp "${BOOTSTRAP_SQL}" "${payload_dir}/bootstrap/frame_nacos_demo.sql"
  cp "${BOOTSTRAP_CONFIG}" "${payload_dir}/bootstrap/cmict-share.yaml"
  cp "${IMPORT_SCRIPT}" "${payload_dir}/tools/import-nacos.sh"
  chmod +x "${payload_dir}/tools/import-nacos.sh"

  generate_image_index "${arch}" "${image_index}"

  while IFS=$'\t' read -r tar_name pull_ref target_ref platform; do
    [[ -n "${tar_name}" ]] || continue
    log "pulling ${pull_ref} for ${platform}"
    docker pull --platform "${platform}" "${pull_ref}"
    docker tag "${pull_ref}" "${target_ref}"
    log "saving ${target_ref} to ${tar_name}"
    docker save -o "${payload_dir}/images/${tar_name}" "${target_ref}"
  done < "${image_index}"

  (
    cd "${payload_dir}"
    tar -czf "${payload_file}" .
  )

  cat "${INSTALLER_STUB}" "${payload_file}" > "${installer_path}"
  chmod +x "${installer_path}"
  sha256sum "${installer_path}" > "${installer_path}.sha256"

  log "built ${installer_path}"
}

main() {
  parse_args "$@"
  check_prereqs
  rm -rf "${TMP_DIR}"
  mkdir -p "${TMP_DIR}" "${DIST_DIR}"

  for arch in "${ARCHES[@]}"; do
    build_arch "${arch}"
  done

  rm -rf "${TMP_DIR}"
  log "done"
}

main "$@"
