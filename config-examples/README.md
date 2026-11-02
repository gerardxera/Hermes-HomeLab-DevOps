# config-examples

No es obligatorio copiar un `config.yaml` completo de otro lab.

Lo **crítico** para replicar Homelab DevOps Company:

1. `SOUL.md` de cada perfil (`souls/`)
2. Skills (`skills/`)
3. `~/.hermes/profiles/devops/.env` (Proxmox)
4. Auth LLM (`hermes setup` / `auth.json` local, **nunca en git**)

## Claves útiles (editar en cada perfil)

Ruta: `~/.hermes/profiles/<perfil>/config.yaml`

```yaml
model:
  default: <tu-modelo>
  provider: <tu-provider>
  base_url: <si aplica>

# Tools CLI (Hermes ya trae defaults amplios)
# Asegura que existan: terminal, web, delegation, skills, memory, file, ...

memory:
  memory_enabled: true
  user_profile_enabled: true
  memory_char_limit: 2200

delegation:
  max_concurrent_children: 3
  max_spawn_depth: 1
  subagent_auto_approve: false   # no auto-aprobar hijos destructivos

approvals:
  mode: smart
  timeout: 60

security:
  redact_secrets: true
```

## Modelos

Elige según presupuesto. Patrón razonable:

| Perfil | Objetivo |
|--------|----------|
| devops | Mejor razonamiento + muchas tool calls |
| auditor | Barato/rápido, buena instrucción de formato |
| research | Buen uso de web + síntesis |

## Gateway (Telegram, etc.)

Opcional. Ver docs Hermes. Si activas bots:

- Restringe `allowed_chats` / IDs
- Un bot o un perfil por rol (recomendado) para no mezclar SOUL
- Sigue exigiendo aprobación humana para mutaciones

## No versionar

- `auth.json`
- `.env` con secrets
- `state.db*`
- claves SSH privadas
