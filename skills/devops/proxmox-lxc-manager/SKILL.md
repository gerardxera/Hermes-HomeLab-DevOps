---
name: proxmox-lxc-manager
description: Create, list, configure, and manage Proxmox LXC/VM guests safely from the Hermes devops host via API (not local pct/qm). Enforces governance, snapshots, and conservative resources.
---

# Proxmox LXC Manager

Centraliza creación, inventario y gestión de **LXC/VM en Proxmox** de forma segura y reproducible (Homelab DevOps Company).

## Cuándo usar

- Listar contenedores y VMs del cluster
- Crear un LXC o modificar recursos/red/mounts
- Start / stop / reboot / clone
- Diagnosticar acceso API o permisos del token antes de operar

## Contexto de ejecución

El agente **no corre en el nodo PVE**. En Hermes normalmente **no existen** `pct` / `qm` / `pvesh`.

- Inventario y operaciones: **API REST** (`https://$PROXMOX_HOST:8006/api2/json/...`)
- Credenciales: `~/.hermes/profiles/devops/.env`
- `PROXMOX_TOKEN_ID` ya viene como `user@realm!tokenname` — header `Authorization: PVEAPIToken={TOKEN_ID}={SECRET}` **sin** anteponer de nuevo el user
- privsep=1: ACL efectiva = user ∩ token (mirror roles en ambos)
- PVE 8/9 + bridge (p. ej. `vmbr0`): en PVE 9 hace falta **SDN.Use** (`PVESDNUser` o rol custom) en `/sdn` y en el path del bridge
- Bind `mp0`: solo `root@pam` (`pct set` en el nodo); API create **sin** mp0
- SSH Debian 13: `ssh-public-keys` (y password) **en el POST create**; bootstrap `pct exec` one-liner si hace falta
- Detalle API: `references/proxmox-api-access.md`

## Flujo de cambios

1. Políticas de despliegue (community-scripts → LXC Debian → VM solo si hace falta)
2. Plan (VMID libre a elección del operador, recursos, storage, red/IP a elección)
3. Quorum → `quorum-review` si el cambio es importante
4. Human approval → frase exacta `Sí, ejecuta` (o la acordada en el lab)
5. Snapshot / vzdump antes de cambios relevantes
6. Ejecutar vía API o community-scripts **en shell del nodo PVE**
7. Verificar guest
8. Reverse proxy solo si el usuario lo pide
9. Auditoría final (perfil Auditor)

## Recursos conservadores (orientativos)

| Tipo | vCPU | RAM | Disco |
|------|------|-----|-------|
| DNS / adblock | 1 | 1 GB | 8 GB |
| Monitorización ligera | 1 | 1–2 GB | 10 GB |
| Reverse proxy | 1–2 | 2 GB | 10 GB |
| App media (todo en CT) | 2–4 | 4–8 GB | 20–50 GB |
| Media server + bind NAS | 1–2 | 1–3 GB | **4–8 GB rootfs** |
| Suite finanzas Docker | 2 | 4 GB | 40 GB |
| LangGraph / AI Python | 2 | 4 GB | 20–25 GB |
| ONLYOFFICE Docs | 2 | 3 GB (mín. 2) | 16 GB |
| DB | 2 | 4–8 GB | 20+ GB |
| **Hermes Agent host (recomendado)** | **2–4** | **4–8 GB** | **20–40 GB** |

Si el storage de rootfs es tipo `dir` + disco `.raw`, el snapshot nativo de PVE suele ser poco fiable → preferir **vzdump** cuando el guest esté estable.

## Variables del operador (no hardcodear)

El operador define en su lab (no copies valores de otro home):

- `PVE_NODE`, `PVE_BRIDGE` (ej. vmbr0)
- `STORAGE_ROOTFS`, `STORAGE_TMPL` (plantillas/ISO/backup)
- `VMID_*`, `IP_*` / DHCP
- Hostname y tags por guest

## Pitfalls

- Listas vacías de guests: no asumir cluster vacío sin chequear ACL/privsep
- Token rotado: actualizar `PROXMOX_TOKEN_SECRET` y reaplicar ACL del **token** (incl. SDN)
- `pct exec` multi-línea en consola PVE se rompe → one-liners
- community-scripts solo en nodo PVE, no desde el CT Hermes
- No dar por cerrado un servicio web si solo responde la página default del reverse/nginx del SO

## Related skills

`quorum-review`, y opcionalmente (si las creas): `homelab-governance`, `human-approval`, `backup-orchestrator`, `reverse-proxy-integrator`
