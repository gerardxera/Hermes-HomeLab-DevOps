# Proxmox API access (Hermes devops host)

## Auth header

Env (`~/.hermes/profiles/devops/.env`):

- `PROXMOX_TOKEN_ID` is typically already `user@realm!tokenname`
- Do **not** prefix `PROXMOX_USER` again when building the header

```http
Authorization: PVEAPIToken={TOKEN_ID}={SECRET}
```

```python
token_id = env["PROXMOX_TOKEN_ID"]  # may already contain "!"
secret = env["PROXMOX_TOKEN_SECRET"]
headers = {"Authorization": f"PVEAPIToken={token_id}={secret}"}
base = f"https://{env['PROXMOX_HOST']}:8006/api2/json"
# PROXMOX_VERIFY_SSL=false → ssl._create_unverified_context()
```

## Useful endpoints

| Path | Use |
|------|-----|
| `GET /version` | Auth smoke test |
| `GET /nodes` | Node names + online |
| `GET /cluster/resources?type=vm` | All qemu+lxc (needs rights) |
| `GET /nodes/{node}/qemu` | VMs on node |
| `GET /nodes/{node}/lxc` | LXCs on node |
| `GET /cluster/status` | Needs `Sys.Audit` |
| `GET /nodes/{node}/status` | Node stats; needs `Sys.Audit` |
| `GET /nodes/{node}/lxc/{vmid}/config` | Full guest config |
| `GET /nodes/{node}/lxc/{vmid}/status/current` | Live resources |
| `GET /nodes/{node}/lxc/{vmid}/snapshot` | Snapshot list |
| `GET /access/permissions` | Effective privs for this token |

## Privilege separation (critical)

When the token has **privsep=1**:

```text
effective_privileges = ACL(user) ∩ ACL(token)
```

- ACLs only on the token + empty user → **403 Sys.Audit**, empty guest lists, while `/version` still works.
- ACLs only on the user + privsep token without token ACL → same class of failure.
- Fix: mirror needed roles on **both** `-user` and `-token`.

Check on PVE node as root:

```bash
pveum user token list devops@pve
pveum acl list
```

Expect rows for `devops@pve` (type=user) **and** `devops@pve!hermes-devops` (type=token).

## Permission matrix (minimum)

**Read inventory**

- `VM.Audit` on `/` or `/nodes/{node}`
- Recommended: `Sys.Audit`, `Datastore.Audit`
- Built-in: `PVEAuditor` on `/` (user **and** token)

**Mutate guests (Hermes devops profile)**

- `PVEVMAdmin` on `/` or `/nodes/{node}` (+ pool if used)
- Datastore: at least `PVEDatastoreUser` on `/storage` and concrete storages; disk allocate may need `PVEDatastoreAdmin` / `Datastore.AllocateSpace`

Lab pattern that works (user ∩ token):

```bash
# USER
pveum acl modify / -user 'devops@pve' -role PVEAuditor
pveum acl modify / -user 'devops@pve' -role PVEVMAdmin
pveum acl modify /storage -user 'devops@pve' -role PVEDatastoreUser

# TOKEN (same roles)
pveum acl modify / -token 'devops@pve!hermes-devops' -role PVEAuditor
pveum acl modify / -token 'devops@pve!hermes-devops' -role PVEVMAdmin
pveum acl modify /storage -token 'devops@pve!hermes-devops' -role PVEDatastoreUser
```

Optional: mirror pool paths (e.g. `/pool/Infrastructure`) the same way on user and token.

### Proxmox 9: SDN.Use required for vmbr0

`PVEVMAdmin` alone is **not enough** for `POST .../lxc` with `net0 ... bridge=vmbr0`:

```text
403 Permission check failed (/sdn/zones/localnetwork/vmbr0, SDN.Use)
```

Fix on PVE root (user **and** token, privsep∩):

```bash
pveum acl modify /sdn -user 'devops@pve' -role PVESDNUser
pveum acl modify /sdn -token 'devops@pve!hermes-devops' -role PVESDNUser
pveum acl modify /sdn/zones/localnetwork/vmbr0 -user 'devops@pve' -role PVESDNUser
pveum acl modify /sdn/zones/localnetwork/vmbr0 -token 'devops@pve!hermes-devops' -role PVESDNUser
# If role missing: pveum role add HermesSDN -privs SDN.Use
pveum acl list | grep -i sdn
```

Hermes: `GET /access/permissions` must include `SDN.Use`.

## Token rotation

```bash
pveum user token remove devops@pve hermes-devops
pveum user token add devops@pve hermes-devops --privsep 1 --comment "Hermes devops"
# RE-apply all -token ACL lines (user ACL usually kept)
# On Hermes only: ~/.hermes/profiles/devops/.env → PROXMOX_TOKEN_SECRET=<new>
```

| HTTP | Meaning |
|------|---------|
| 401 | Bad/stale secret or token id |
| 403 + `Sys.Audit` / `VM.*` | Auth OK; ACL/privsep intersection incomplete |
| 200 + `data: []` guests after Audit 403s | Do **not** assume empty cluster |

Never paste token secrets into chat. Compare by prefix/sha256 only from Hermes. After exposure, rotate.

## Empty list checklist

1. `GET /version` → 200?
2. `GET /cluster/status` → 403 Sys.Audit?
3. privsep=1 and missing **user** or **token** half of the intersection?
4. Stale secret (401) after rotation?
5. Only then treat `[]` as possibly empty cluster

Scripts: `scripts/perm-check.py`, `scripts/list-guests.py`

## Create LXC (API)

Requires `VM.Allocate`, `VM.Config.*`, `VM.PowerMgmt`, `Datastore.AllocateSpace`, and on PVE9 **`SDN.Use`** for bridges (user ∩ token).

```text
POST /nodes/{node}/lxc   → { "data": "<UPID>" }
GET  /nodes/{node}/tasks/{upid}/status  until status=stopped
GET  /cluster/nextid
GET  /nodes/{node}/storage/{storage}/content?content=vztmpl
```

Template lab: `almacen4tb:vztmpl/debian-13-standard_*_amd64.tar.zst`. Rootfs often `local` dir/raw (vzdump later).

### WARNINGS task ≠ automatic failure

`vzcreate`/`vzstart` may return `exitstatus: "WARNINGS: 1"` (*Systemd 257… nesting*) while CT is **running**. Confirm status/list. Prefer `features=nesting=1` on Debian 13 unprivileged.

### Bind mp0: root@pam only

```text
403 Permission check failed (mount point type bind is only allowed for root@pam)
```

Create **without** mp0 via API; on PVE: `pct set <vmid> -mp0 /mnt/almacen4tb,mp=/mnt/almacen4tb,backup=0`.

### password / ssh-public-keys only at create

`PUT .../config` rejects `password` and `ssh-public-keys`. After create bootstrap via PVE `pct exec` (chpasswd, PermitRootLogin, authorized_keys). Debian 13 often blocks root password SSH until then.

Media playbook: `references/media-lxc-jellyfin-swingmusic.md`.

## Remote host reality

Hermes ≠ PVE node:

- No local `pct`/`qm` — expected
- API for create/power; on PVE (user paste): `pveum`, community-scripts, **`pct set` binds**, **`pct exec` SSH bootstrap**
- No PVE shell → L2: API create + install inside guest once SSH works
