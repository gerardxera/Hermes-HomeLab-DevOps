#!/usr/bin/env bash
# Ejecutar en el NODO PROXMOX como root@pam
# Crea usuario + API token + ACL espejadas (privsep=1) para Hermes DevOps.
#
# Uso:
#   export DEVOPS_USER="${DEVOPS_USER:-devops@pve}"
#   export TOKEN_NAME="${TOKEN_NAME:-hermes-devops}"
#   export BRIDGE_ACL_PATH="${BRIDGE_ACL_PATH:-/sdn/zones/localnetwork/vmbr0}"
#   export STORAGE_LIST="${STORAGE_LIST:-local}"   # ej: "local almacen4tb"
#   bash 01-pve-create-user-token-acl.sh
#
# Ajusta BRIDGE_ACL_PATH a tu topología SDN/bridge.
# En PVE sin SDN path, prueba también ACL en el bridge que uses (consulta pveum acl list / UI).

set -euo pipefail

DEVOPS_USER="${DEVOPS_USER:-devops@pve}"
TOKEN_NAME="${TOKEN_NAME:-hermes-devops}"
TOKEN_FULL="${DEVOPS_USER}!${TOKEN_NAME}"
BRIDGE_ACL_PATH="${BRIDGE_ACL_PATH:-/sdn/zones/localnetwork/vmbr0}"
STORAGE_LIST="${STORAGE_LIST:-local}"
POOL_PATH="${POOL_PATH:-}"  # ej: /pool/Infrastructure  (vacío = omitir)

echo "==> Usuario ${DEVOPS_USER}"
if ! pveum user list | grep -q "^${DEVOPS_USER}"; then
  pveum user add "${DEVOPS_USER}" --comment "Hermes DevOps AI Agent"
else
  echo "    (ya existe)"
fi

echo "==> Rol custom HermesSDN (SDN.Use) si no existe"
if ! pveum role list | grep -q '^HermesSDN'; then
  pveum role add HermesSDN -privs SDN.Use || true
fi

echo "==> Token ${TOKEN_FULL} (privsep=1)"
echo "    Si el token ya existe y no recuerdas el secret, bórralo y créalo de nuevo:"
echo "      pveum user token remove ${DEVOPS_USER%*} ${TOKEN_NAME}   # ajustar sintaxis según versión"
echo "    Creando/recreando puede invalidar el secret anterior."
# No borramos automáticamente. Intentamos add; si falla, el admin decide.
if pveum user token add "${DEVOPS_USER}" "${TOKEN_NAME}" --privsep 1 --comment "Hermes devops" 2>/tmp/pve-token-add.err; then
  echo "    *** GUARDA EL SECRET AHORA en el .env de Hermes (PROXMOX_TOKEN_SECRET) ***"
else
  echo "    Aviso: no se pudo crear el token (¿ya existe?). Detalle:"
  cat /tmp/pve-token-add.err || true
  echo "    Continúo aplicando ACL al token existente ${TOKEN_FULL}"
fi

apply_acl() {
  local subject="$1"  # "-user devops@pve" o "-token devops@pve!hermes-devops"
  pveum acl modify / ${subject} -role PVEAuditor
  pveum acl modify / ${subject} -role PVEVMAdmin
  pveum acl modify /storage ${subject} -role PVEDatastoreUser
  for st in ${STORAGE_LIST}; do
    pveum acl modify "/storage/${st}" ${subject} -role PVEDatastoreUser
  done
  # SDN / bridge (PVE 9 create LXC con bridge)
  pveum acl modify /sdn ${subject} -role PVESDNUser 2>/dev/null || true
  pveum acl modify /sdn ${subject} -role HermesSDN 2>/dev/null || true
  pveum acl modify "${BRIDGE_ACL_PATH}" ${subject} -role PVESDNUser 2>/dev/null || true
  pveum acl modify "${BRIDGE_ACL_PATH}" ${subject} -role HermesSDN 2>/dev/null || true
  if [[ -n "${POOL_PATH}" ]]; then
    pveum acl modify "${POOL_PATH}" ${subject} -role PVEVMAdmin
  fi
}

echo "==> ACL espejadas USER ∩ TOKEN (privsep)"
apply_acl "-user ${DEVOPS_USER}"
apply_acl "-token ${TOKEN_FULL}"

echo "==> Resumen ACL (filtrado)"
pveum acl list | grep -E "${DEVOPS_USER}|HermesSDN|PVEVMAdmin|PVEAuditor|PVEDatastore|SDN" || pveum acl list

echo
echo "Hecho. En Hermes (~/.hermes/profiles/devops/.env):"
echo "  PROXMOX_HOST=<ip-o-host-api-de-TU-pve>"
echo "  PROXMOX_USER=${DEVOPS_USER}"
echo "  PROXMOX_TOKEN_ID=${TOKEN_FULL}"
echo "  PROXMOX_TOKEN_SECRET=<secret>"
echo "  PROXMOX_VERIFY_SSL=false   # o true con cert válido"
echo
echo "Smoke test desde el CT Hermes:"
echo "  curl -sk -H \"Authorization: PVEAPIToken=\${PROXMOX_TOKEN_ID}=\${PROXMOX_TOKEN_SECRET}\" \\"
echo "    \"https://\${PROXMOX_HOST}:8006/api2/json/version\""
