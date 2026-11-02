#!/usr/bin/env bash
# Ejecutar DENTRO del contenedor/VM donde corre Hermes, como usuario del agente (ej. hermes).
# Instala perfiles devops/auditor/research, SOULs, skills y aliases.
#
# Uso:
#   cd /path/to/homelab-devops-company
#   bash scripts/02-install-company-profiles.sh
#
# Requiere: hermes en PATH, perfiles se crean con `hermes profile`.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERMES_BIN="${HERMES_BIN:-$(command -v hermes)}"
HERMES_HOME_BASE="${HERMES_HOME_BASE:-${HOME}/.hermes}"

if [[ -z "${HERMES_BIN}" || ! -x "${HERMES_BIN}" ]]; then
  echo "ERROR: no se encuentra 'hermes' en PATH. Instala Hermes Agent primero."
  exit 1
fi

echo "==> Hermes: $(${HERMES_BIN} --version 2>/dev/null || echo ok)"

create_profile() {
  local name="$1"
  if [[ -d "${HERMES_HOME_BASE}/profiles/${name}" ]]; then
    echo "    perfil ${name}: ya existe (no se borra)"
  else
    echo "    creando perfil ${name}"
    ${HERMES_BIN} profile create "${name}" || true
  fi
}

echo "==> Perfiles"
create_profile devops
create_profile auditor
create_profile research

echo "==> Aliases CLI (devops / auditor / research)"
${HERMES_BIN} profile alias devops 2>/dev/null || {
  mkdir -p "${HOME}/.local/bin"
  printf '#!/bin/sh\nexec %s -p devops "$@"\n' "${HERMES_BIN}" > "${HOME}/.local/bin/devops"
  chmod +x "${HOME}/.local/bin/devops"
}
${HERMES_BIN} profile alias auditor 2>/dev/null || {
  printf '#!/bin/sh\nexec %s -p auditor "$@"\n' "${HERMES_BIN}" > "${HOME}/.local/bin/auditor"
  chmod +x "${HOME}/.local/bin/auditor"
}
${HERMES_BIN} profile alias research 2>/dev/null || {
  printf '#!/bin/sh\nexec %s -p research "$@"\n' "${HERMES_BIN}" > "${HOME}/.local/bin/research"
  chmod +x "${HOME}/.local/bin/research"
}

install_soul() {
  local name="$1"
  local src="$ROOT/souls/${name}.SOUL.md"
  local dst="${HERMES_HOME_BASE}/profiles/${name}/SOUL.md"
  mkdir -p "$(dirname "$dst")"
  cp -f "$src" "$dst"
  echo "    SOUL → ${dst}"
}

echo "==> SOUL.md (identidad exacta Homelab DevOps Company)"
install_soul devops
install_soul auditor
install_soul research

echo "==> Skills devops"
DEV_SK="${HERMES_HOME_BASE}/profiles/devops/skills/homelab"
mkdir -p "${DEV_SK}/proxmox-lxc-manager/references" "${DEV_SK}/quorum-review"
cp -f "$ROOT/skills/devops/proxmox-lxc-manager/SKILL.md" \
  "${DEV_SK}/proxmox-lxc-manager/SKILL.md"
cp -f "$ROOT/skills/devops/proxmox-lxc-manager/references/proxmox-api-access.md" \
  "${DEV_SK}/proxmox-lxc-manager/references/proxmox-api-access.md"
cp -f "$ROOT/skills/devops/quorum-review/SKILL.md" \
  "${DEV_SK}/quorum-review/SKILL.md"

echo "==> Skills research"
RES_SK="${HERMES_HOME_BASE}/profiles/research/skills/research/homelab-research-agent"
mkdir -p "${RES_SK}"
cp -f "$ROOT/skills/research/homelab-research-agent/SKILL.md" \
  "${RES_SK}/SKILL.md"

echo "==> .env de ejemplo (devops)"
ENV_DST="${HERMES_HOME_BASE}/profiles/devops/.env"
if [[ -f "${ENV_DST}" ]]; then
  echo "    ${ENV_DST} ya existe — no se sobrescribe"
else
  cp -f "$ROOT/env/devops.env.example" "${ENV_DST}"
  chmod 600 "${ENV_DST}"
  echo "    creado ${ENV_DST} — EDÍTALO con tu host/token"
fi

echo
echo "Listo. Siguientes pasos manuales:"
echo "  1. Editar ${HERMES_HOME_BASE}/profiles/devops/.env"
echo "  2. hermes setup / login del provider LLM en cada perfil si hace falta"
echo "  3. Probar: devops   |   auditor   |   research"
echo "  4. Smoke API Proxmox (ver README)"
