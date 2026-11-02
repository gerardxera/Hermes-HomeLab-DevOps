# Hermes HomeLab DevOps

**Tu propio departamento de DevOps impulsado por IA para tu homelab.**

Esta plantilla reproducible despliega un equipo de tres agentes [Hermes](https://github.com/NousResearch/hermes-agent) que te permite instalar, configurar y gestionar tus contenedores en Proxmox de forma automática y dialogada. Todo el sistema está diseñado con seguridad Zero-Trust: los agentes operan mediante tokens de API **sin permisos de root** en tu hipervisor, requiriendo siempre tu aprobación humana antes de ejecutar cualquier cambio en la infraestructura.

---

**reproducible** para montar en **cualquier Proxmox** un equipo de tres agentes.

| Agente | Perfil | Rol |
|--------|--------|-----|
| **Research** | `research` | Investiga alternativas y entrega un **JSON** de handoff. No ejecuta. |
| **DevOps** | `devops` | Arquitecto + operador. Planifica, pide quorum, ejecuta **solo** tras aprobación humana. |
| **Auditor** | `auditor` | Quorum Light previo + auditoría final. Veredicto **PASS / WARNING / FAIL**. |

Este repositorio no impone tus IPs, VMIDs ni nombres de storage. **Tú eliges** la red y los IDs. Lo que se replica **tal cual** es el modelo operativo: SOUL, skills, flujos, formato JSON, permisos API y el orden de instalación.

```text
Usuario
  → Research (opciones + JSON)
  → DevOps (plan)
  → Auditor / Quorum Light (PASS|WARNING|FAIL)
  → Usuario: «Sí, ejecuta»
  → DevOps ejecuta (API Proxmox / scripts en el nodo)
  → Auditor (validación final)
```

---

## Índice (pasos 1–14)

1. [Requisitos](#1-requisitos)  
2. [Variables que TÚ defines](#2-variables-que-tú-defines)  
3. [Usuario y API token en Proxmox](#3-usuario-y-api-token-en-proxmox)  
4. [Crear el LXC (o VM) de Hermes](#4-crear-el-lxc-o-vm-de-hermes)  
5. [Instalar Hermes Agent dentro del guest](#5-instalar-hermes-agent-dentro-del-guest)  
6. [Clonar este repo e instalar la “compañía”](#6-clonar-este-repo-e-instalar-la-compañía)  
7. [Configurar `.env` de devops (Proxmox)](#7-configurar-env-de-devops-proxmox)  
8. [Auth del modelo LLM](#8-auth-del-modelo-llm)  
9. [SOUL exactos (identidad de cada agente)](#9-soul-exactos-identidad-de-cada-agente)  
10. [Skills obligatorias](#10-skills-obligatorias)  
11. [Flujos, JSON y veredictos](#11-flujos-json-y-veredictos)  
12. [Cómo arrancar cada chat/bot](#12-cómo-arrancar-cada-chatbot)  
13. [Smoke tests y checklist](#13-smoke-tests-y-checklist)  
14. [Operación diaria y pits](#14-operación-diaria-y-pits)  

Archivos del repo: [Estructura](#estructura-del-repositorio).

---

## 1. Requisitos

- Un nodo o cluster **Proxmox VE** (8.x o 9.x). En **PVE 9**, crear LXC con bridge suele exigir privilegio **SDN.Use** (el script de ACL lo contempla).
- Shell **root@pam** en el nodo (para community-scripts, `pveum`, binds `pct set`).
- Red LAN donde el guest de Hermes pueda alcanzar `https://TU_PVE:8006`.
- Cuenta de un **provider LLM** soportado por Hermes (OpenAI, OpenRouter, xAI, etc.).
- Conocimientos básicos de LXC o voluntad de usar [community-scripts](https://community-scripts.org).

**No hace falta** que Hermes corra *en* el nodo PVE. El diseño canónico es:

> Guest Linux (LXC recomendado) con Hermes → gestiona el cluster por **API token**.

---

## 2. Variables que TÚ defines

Copia esta tabla y rellénala **antes** de instalar. No uses los valores de otro lab.

| Variable | Significado | Ejemplo (solo ejemplo) |
|----------|-------------|------------------------|
| `PVE_HOST` | IP/DNS de la API Proxmox | `192.168.10.2` |
| `PVE_NODE` | Nombre del nodo | `pve` |
| `PVE_BRIDGE` | Bridge de los CT | `vmbr0` |
| `BRIDGE_ACL_PATH` | Path ACL SDN/bridge (PVE9) | `/sdn/zones/localnetwork/vmbr0` |
| `STORAGE_ROOTFS` | Storage discos de CT | `local` |
| `STORAGE_TMPL` | Plantillas/ISO/backup | `local` u otro |
| `DEVOPS_USER` | Usuario API | `devops@pve` |
| `TOKEN_NAME` | Nombre del token | `hermes-devops` |
| `HERMES_VMID` | VMID del CT Hermes | el que quieras libre |
| `HERMES_HOSTNAME` | Hostname del CT | `hermes` |
| `HERMES_IP` | Estática o DHCP | la que quieras |
| `HERMES_CORES` | vCPU | `2`–`4` recomendado |
| `HERMES_RAM_MB` | RAM MB | `4096`–`8192` |
| `HERMES_DISK_GB` | Disco root | `20`–`40` |

El resto de guests de tu homelab (media, *arr*, etc.) **no** forman parte de esta plantilla: los despliega el DevOps Agent *después*, con VMIDs e IPs que elijas tú.

---

## 3. Usuario y API token en Proxmox

### 3.1 Por qué un usuario dedicado

No uses `root@pam` en el agente. Crea `devops@pve` (o el nombre que prefieras) y un **API token con privsep=1**.

Con **privilege separation** (`privsep=1`):

```text
privilegios_efectivos = ACL(usuario) ∩ ACL(token)
```

Debes **espejar** los mismos roles en el usuario **y** en el token. Si solo asignas uno de los dos, verás `401/403`, listas de guests vacías o fallos al crear LXC.

### 3.2 Roles recomendados (mínimo útil)

| Ámbito | Roles | Para qué |
|--------|-------|----------|
| `/` | `PVEAuditor` + `PVEVMAdmin` | Inventario + crear/configurar/arrancar guests |
| `/storage` y cada storage usado | `PVEDatastoreUser` | Espacio y plantillas |
| `/sdn` y path del bridge | `PVESDNUser` y/o rol `HermesSDN` (`SDN.Use`) | Crear LXC con `net0 ... bridge=...` en PVE 9 |
| `/pool/...` (opcional) | `PVEVMAdmin` | Si organizas por pools |

### 3.3 Script automático (en el nodo PVE, root)

> ⚠️ **ATENCIÓN: Ejecuta este bloque SOLO en la consola de tu nodo Proxmox (como root@pam). Nunca dentro del contenedor de Hermes.**

```bash
# Copia este repo al nodo o pega el script
export DEVOPS_USER=devops@pve
export TOKEN_NAME=hermes-devops
export BRIDGE_ACL_PATH=/sdn/zones/localnetwork/vmbr0   # AJUSTA a tu path real
export STORAGE_LIST="local"                            # añade storages: "local datos"
# export POOL_PATH=/pool/Infrastructure                # opcional

bash scripts/01-pve-create-user-token-acl.sh
```

**Guarda el secret del token** en un sitio seguro. Solo se muestra al crearlo.

### 3.4 Header HTTP correcto (crítico)

En el `.env` de devops:

```bash
PROXMOX_TOKEN_ID=devops@pve!hermes-devops   # ya lleva user@realm!token
PROXMOX_TOKEN_SECRET=...
```

Header:

```http
Authorization: PVEAPIToken=devops@pve!hermes-devops=<SECRET>
```

**No** antepongas otra vez el usuario. Detalle y troubleshooting:  
[`skills/devops/proxmox-lxc-manager/references/proxmox-api-access.md`](skills/devops/proxmox-lxc-manager/references/proxmox-api-access.md)

### 3.5 Límites del token (diseño a propósito)

| Acción | ¿Con token desde Hermes? |
|--------|---------------------------|
| Listar/crear/configurar LXC-VM, start/stop, a menudo snapshot/backup según ACL | Sí |
| community-scripts | Solo en **shell del nodo** PVE |
| Bind mount `mp0` tipo bind | Solo **root@pam** → `pct set` en el nodo |
| `password` / `ssh-public-keys` en `PUT` config | No; solo en **POST create** (luego `pct exec`) |

---

## 4. Crear el LXC (o VM) de Hermes

### 4.1 Prioridad Hermes Homelab DevOps

1. Script **community-scripts** si existe (p. ej. *Hermes Agent*).  
2. Si no: LXC Debian limpio + install oficial de Hermes.  
3. VM solo si LXC no es viable.

### 4.2 Opción A — community-scripts (recomendado)

En el **nodo PVE** (root):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/hermesagent.sh)"
```

O desde el catálogo: [community-scripts.org](https://community-scripts.org) → buscar Hermes Agent.

En el asistente, usa **tus** valores (`HERMES_VMID`, cores, RAM, disco, bridge, DHCP o IP estática).

### 4.3 Opción B — LXC Debian manual (mínimos recomendados)

| Parámetro | Recomendación |
|-----------|----------------|
| OS | Debian 12/13 |
| cores | 2–4 |
| memory | 4096–8192 MB |
| disk | 20–40 G |
| features | `nesting=1` (y `fuse=1` si el script lo pide) |
| net | bridge que elijas, IP la que elijas |
| onboot | 1 |

Luego instala Hermes a mano (paso 5).

---

## 5. Instalar Hermes Agent dentro del guest

Si usaste community-scripts, el agente suele venir instalado. Si partiste de Debian limpio, sigue la documentación oficial:

- Docs: https://hermes-agent.nousresearch.com/docs  
- Repo: https://github.com/NousResearch/hermes-agent  

Comprobación:

```bash
hermes --version
# Usuario de trabajo típico del CT: hermes (uid 1000)
```

Genera una clave SSH del agente (para futuros guests):

```bash
ssh-keygen -t ed25519 -C "hermes-devops" -f ~/.ssh/id_ed25519 -N ""
```

La **pública** se podrá inyectar en creates LXC; la privada no se sube a git.

---

## 6. Clonar este repo e instalar la “compañía”

Dentro del guest Hermes, como usuario del agente:

> ⚠️ **ATENCIÓN: Ejecuta esto SOLO dentro del guest/contenedor de Hermes, usando el usuario del agente. Nunca lo ejecutes en el nodo Proxmox.**

```bash
cd ~
git clone https://github.com/<TU_USUARIO>/hermes-homelab-devops.git
cd hermes-homelab-devops

chmod +x scripts/*.sh
bash scripts/02-install-company-profiles.sh
```

El script:

1. Crea perfiles `devops`, `auditor`, `research` (si no existen).  
2. Crea aliases `~/.local/bin/{devops,auditor,research}`.  
3. Copia los **SOUL.md** exactos.  
4. Instala skills en:
   - `~/.hermes/profiles/devops/skills/homelab/...`
   - `~/.hermes/profiles/research/skills/research/homelab-research-agent/`  
5. Crea `.env` de ejemplo en devops **solo si no existe**.

---

## 7. Configurar `.env` de devops (Proxmox)

```bash
chmod 600 ~/.hermes/profiles/devops/.env
nano ~/.hermes/profiles/devops/.env
```

Plantilla: [`env/devops.env.example`](env/devops.env.example)

```bash
PROXMOX_HOST=<PVE_HOST>                 # el tuyo
PROXMOX_USER=devops@pve
PROXMOX_TOKEN_ID=devops@pve!hermes-devops
PROXMOX_TOKEN_SECRET=<secret del paso 3>
PROXMOX_VERIFY_SSL=false                # true si tienes cert válido
```

Smoke:

```bash
bash scripts/03-smoke-proxmox-api.sh
```

Esperado: JSON de `/version` y listado de nodos.  
- `401` → token/secret mal.  
- `403` o guests vacíos sospechosos → ACL/privsep (re-espejar user y token, SDN).

---

## 8. Auth del modelo LLM

En cada perfil (o al menos en devops):

```bash
hermes -p devops setup
# o el flujo de login OAuth/API key de tu provider
```

Recomendación de modelos (orientativa; cámbialos en `config.yaml` de cada perfil):

| Perfil | Rol del modelo | Sugerencia |
|--------|----------------|------------|
| devops | Razonamiento + tools largos | Modelo “strong” del provider |
| auditor | Revisiones estructuradas | Modelo rápido/barato válido |
| research | Búsqueda y síntesis | Strong o mid con buen web tool |

No hace falta copiar un `config.yaml` entero de otro lab: lo **imprescindible** es SOUL + skills + `.env` + auth. El resto de Hermes puede quedarse en defaults.

Opcional: revisa [`config-examples/README.md`](config-examples/README.md) para claves útiles (`approvals.mode`, `delegation.*`, `memory.*`).

---

## 9. SOUL exactos (identidad de cada agente)

Fuente de verdad en este repo (se copian al instalar):

| Archivo | Destino en el guest |
|---------|---------------------|
| [`souls/devops.SOUL.md`](souls/devops.SOUL.md) | `~/.hermes/profiles/devops/SOUL.md` |
| [`souls/auditor.SOUL.md`](souls/auditor.SOUL.md) | `~/.hermes/profiles/auditor/SOUL.md` |
| [`souls/research.SOUL.md`](souls/research.SOUL.md) | `~/.hermes/profiles/research/SOUL.md` |

### 9.1 DevOps — misión y reglas (resumen)

- Prioridad: community-scripts → LXC Debian → VM solo si hace falta.  
- **Snapshot first** en cambios importantes.  
- **Human Approval Gate:** no mutar infra sin `Sí, ejecuta` (exacta en SOUL; puedes acordar sinónimos inequívocos en tu lab y documentarlos en memoria del perfil).  
- **Quorum Light** vía skill `quorum-review` antes de: nuevo LXC/VM, updates mayores, red/storage/backups, recursos altos.  
- Conservar recursos; auditoría final con Auditor.  
- Colaborar con Research (JSON) y Auditor (`delegate_task`).

### 9.2 Research — misión y reglas (resumen)

Orden de búsqueda **obligatorio**:

1. https://tom-doerr.github.io/repo_posts/  
2. https://community-scripts.org/  
3. Repo oficial GitHub  
4. Docs oficiales si hace falta  

Presenta alternativas **sin elegir** por el usuario. Tras la opción elegida: deep-dive + **JSON** (schema en §11). No ejecuta ni cierra arquitectura.

### 9.3 Auditor — misión y reglas (resumen)

Revisa recursos, estado guest, servicios/logs/HTTP, red, persistencia/backups y buenas prácticas.  
**Formato de respuesta obligatorio** (ver §11).  
Honestidad: PASS / WARNING / FAIL con acciones concretas.

Lee los tres SOUL completos en `souls/` antes de personalizar idioma o frases de aprobación.

---

## 10. Skills obligatorias

| Skill | Perfil | Path en repo |
|-------|--------|--------------|
| `proxmox-lxc-manager` | devops | `skills/devops/proxmox-lxc-manager/` |
| `quorum-review` | devops | `skills/devops/quorum-review/` |
| `homelab-research-agent` | research | `skills/research/homelab-research-agent/` |

Tras `02-install-company-profiles.sh` quedan en el árbol de skills de cada perfil Hermes.

**Opcionales** (nombradas en el SOUL devops; créalas si las necesitas):

- `homelab-governance` — checklist de políticas  
- `human-approval` — recordatorio de la frase de gate  
- `backup-orchestrator` — vzdump/snapshot  
- `reverse-proxy-integrator` — exponer apps  

Sin ellas, el agente **igual** debe obedecer el SOUL (el SOUL manda).

---

## 11. Flujos, JSON y veredictos

### 11.1 Flujo de despliegue

```text
1. Usuario pide instalar X
2. Research: Tom Doerr + alternativas → usuario elige
3. Research: JSON handoff
4. DevOps: plan (VMID libre, IP libre, CPU/RAM/disk, método L1/L2, storage, riesgos)
5. Si importante → quorum-review → Auditor
6. DevOps muestra plan + informe
7. Usuario: Sí, ejecuta
8. Snapshot/vzdump
9. Ejecución (API y/o shell PVE)
10. Verificación
11. Auditoría final
```

### 11.2 JSON Research → DevOps (obligatorio tras deep-dive)

```json
{
  "application": "Nombre de la aplicación",
  "chosen_from_tom_doerr": true,
  "alternatives_considered": ["..."],
  "recommended_method": "community_script | lxc_debian_base | docker_in_lxc | vm",
  "community_script": {
    "exists": true,
    "name": "",
    "command": ""
  },
  "official_repository": "",
  "cpu": 2,
  "ram_mb": 4096,
  "storage_gb": 20,
  "ports": [],
  "dependencies": [],
  "installation_steps": [],
  "notes": [],
  "data_persistence_strategy": ""
}
```

### 11.3 Formato Auditor (Quorum y post-deploy)

```markdown
**VEREDICTO:** PASS / WARNING / FAIL

**Resumen:**
[2-4 líneas]

**Hallazgos importantes:**
- ...

**Acciones recomendadas:**
1. ...
```

| Veredicto | Acción DevOps |
|-----------|----------------|
| PASS | Pedir `Sí, ejecuta` si el plan sigue vigente |
| WARNING | Explicar en claro; pedir aprobación igual |
| FAIL | Replantear; no ejecutar ese plan |

Quorum **no** sustituye la aprobación humana.

### 11.4 Cuándo es “cambio importante” (Quorum Light)

- Nuevo LXC o VM  
- Updates mayores  
- Red, storage o backups  
- Despliegues grandes (orientativo: ≥ ~4 vCPU o ~8 GB RAM) u otro riesgo medio-alto  

---

## 12. Cómo arrancar cada chat/bot
Puedes usar los alias directos creados durante la instalación (recomendado):

```bash
# Asegura ~/.local/bin en PATH para la sesión actual
export PATH="$HOME/.local/bin:$PATH"

devops      # Equivalente a hermes -p devops
auditor     # Equivalente a hermes -p auditor
research    # Equivalente a hermes -p research
```

> **Nota:** Para no tener que exportar el PATH cada vez que inicies sesión por SSH, haz que el cambio sea permanente añadiéndolo a tu perfil:
> `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc`

O, si prefieres usar el binario de Hermes directamente sin configurar el PATH:

```bash
hermes -p devops
hermes -p auditor
hermes -p research
```

**Gateway** (Telegram/Discord/etc.): opcional. Configúralo por perfil con la doc de Hermes si quieres bots de mensajería. Esta plantilla asume **CLI** como mínimo viable.

Delegación: desde devops, `delegate_task` al “Auditor” o trabajo de research con **contexto auto-contenido** (el hijo no hereda el chat).

---

## 13. Smoke tests y checklist

### Checklist desde cero

- [ ] §3 Token + ACL user∩token (+ SDN si PVE9)  
- [ ] §4 Guest Hermes creado (VMID/IP **tuyos**)  
- [ ] §5 `hermes --version` OK  
- [ ] §6 `02-install-company-profiles.sh`  
- [ ] §7 `.env` con **tu** `PROXMOX_HOST` y secret  
- [ ] §8 Login LLM en perfiles  
- [ ] §13 Smoke API OK  
- [ ] Abrir `research`, pedir alternativas de una app de prueba (sin ejecutar)  
- [ ] Abrir `devops`, pedir un **plan** (sin `Sí, ejecuta`)  
- [ ] Abrir `auditor`, pedir revisión de un plan ficticio y validar formato PASS/WARNING/FAIL  

### Smoke API

```bash
bash scripts/03-smoke-proxmox-api.sh ~/.hermes/profiles/devops/.env
```

### Frases de control humano

| Frase | Efecto |
|-------|--------|
| `Sí, ejecuta` | Aprobación canónica (SOUL) |
| Otras | No mutar infra salvo que las documentes en la memoria del perfil |

---

## 14. Operación diaria y pits

1. **Hermes ≠ nodo PVE** → no esperes `pct`/`qm` dentro del CT.  
2. **privsep** → ACL incompleta = dolores raros; espeja siempre.  
3. **PVE 9 + bridge** → `SDN.Use`.  
4. **Binds** → `pct set` como root en el nodo.  
5. **rootfs raw en storage dir** → prefiere `vzdump` a snapshot nativo.  
6. **SSH Debian 13** → claves en el create; bootstrap one-liner con `pct exec`.  
7. **Secretos** → nunca al repo; rota token si se filtra y re-aplica ACL `-token`.  
8. **community-scripts** → solo shell PVE.  
9. **IPs/VMIDs** → convención tuya (documenta en `memories/MEMORY.md` del perfil devops).  
10. **Idioma** → SOUL en español; cambia el SOUL si quieres otro idioma, manteniendo reglas y formatos.

### Memoria operativa sugerida (devops)

Tras el primer inventario real, guarda en  
`~/.hermes/profiles/devops/memories/MEMORY.md` hechos estables: nodo, bridge, storages, convención de VMIDs, preferencias de aprobación. **No** guardes secrets.

---

## Estructura del repositorio

```text
homelab-devops-company/
├── README.md                          ← esta guía (pasos 1–14)
├── LICENSE
├── .gitignore
├── env/
│   └── devops.env.example
├── souls/
│   ├── devops.SOUL.md                 ← EXACTO identidad DevOps
│   ├── auditor.SOUL.md                ← EXACTO identidad Auditor
│   └── research.SOUL.md               ← EXACTO identidad Research
├── skills/
│   ├── devops/
│   │   ├── proxmox-lxc-manager/
│   │   │   ├── SKILL.md
│   │   │   └── references/proxmox-api-access.md
│   │   └── quorum-review/SKILL.md
│   └── research/
│       └── homelab-research-agent/SKILL.md
├── scripts/
│   ├── 01-pve-create-user-token-acl.sh   # root en PVE
│   ├── 02-install-company-profiles.sh    # usuario hermes en el CT
│   └── 03-smoke-proxmox-api.sh
└── config-examples/
    └── README.md
```

---

## 15. Ejemplo de Uso Esperado (Cómo se ve en la práctica)

Para que visualices el valor de este equipo de agentes, así fluye un despliegue real:

**👤 Usuario:** *"Quiero tener algo para gestionar fotos familiares en el homelab, algo moderno."*

**🔍 Research Agent:**
- Busca en sus fuentes (Tom Doerr, community-scripts).
- Te presenta 3 opciones (Immich, PhotoPrism, LibrePhotos) con pros/contras.
- **👤 Usuario:** *"Vamos con Immich."*
- *Research* realiza la investigación profunda, genera el JSON técnico y hace el handoff.

**⚙️ DevOps Agent:**
- Recibe el JSON de Immich.
- Propone el plan: *"Voy a crear un LXC con 4 vCPU, 8GB RAM y 50GB de almacenamiento usando el script oficial. Al ser un cambio importante, he pasado el Quorum Light y el Auditor ha dado un PASS."*
- **⚙️ DevOps:** *"¿Quieres que proceda con la creación? Responde 'Sí, ejecuta' para continuar."*

**👤 Usuario:** *"Sí, ejecuta"*

**⚙️ DevOps Agent:**
- Crea el snapshot preventivo.
- Ejecuta el despliegue de Immich vía API de Proxmox (o shell).
- Al terminar la instalación, delega la revisión al Auditor.

**🛡️ Auditor Agent:**
- Revisa el contenedor, los recursos asignados, los puertos (ej. 2283) y la persistencia de datos.
- Entrega el informe final: `**VEREDICTO: PASS**. Aplicación respondiendo correctamente.`

---

## Créditos y stack

- [Hermes Agent](https://github.com/NousResearch/hermes-agent) (Nous Research)  
- [Proxmox VE](https://www.proxmox.com/)  
- [community-scripts / ProxmoxVE](https://github.com/community-scripts/ProxmoxVE)  
- Fuentes de research: [Tom Doerr repo_posts](https://tom-doerr.github.io/repo_posts/), [community-scripts.org](https://community-scripts.org)

---

## Seguridad

- Este diseño gestiona infraestructura real. Un SOUL no es un sandbox perfecto: la **aprobación humana** y ACLs acotadas son parte del modelo de amenaza.  
- No des al token más privilegios de los necesarios.  
- No expongas el dashboard/API de Hermes a Internet sin autenticación y red adecuada.
