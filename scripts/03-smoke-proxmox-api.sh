#!/usr/bin/env bash
# Smoke test API Proxmox desde el host Hermes (perfil devops .env)
set -euo pipefail

ENV_FILE="${1:-${HOME}/.hermes/profiles/devops/.env}"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "No existe ${ENV_FILE}"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

: "${PROXMOX_HOST:?}"
: "${PROXMOX_TOKEN_ID:?}"
: "${PROXMOX_TOKEN_SECRET:?}"

AUTH="Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}"
BASE="https://${PROXMOX_HOST}:8006/api2/json"
CURL=(curl -sS)
if [[ "${PROXMOX_VERIFY_SSL:-false}" == "false" ]]; then
  CURL+=(-k)
fi

echo "==> GET /version"
"${CURL[@]}" -H "${AUTH}" "${BASE}/version"
echo
echo
echo "==> GET /nodes"
"${CURL[@]}" -H "${AUTH}" "${BASE}/nodes"
echo
echo
echo "==> GET /access/permissions (efectivos)"
"${CURL[@]}" -H "${AUTH}" "${BASE}/access/permissions" | head -c 4000
echo
echo
echo "Si /version falla 401 → secret/token mal."
echo "Si listados vacíos o 403 → revisa privsep ACL user∩token (y SDN.Use en PVE9)."
