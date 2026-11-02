---
name: quorum-review
description: Quorum Light — revisión previa del Auditor (PASS/WARNING/FAIL) antes de cambios importantes en el homelab. Usar delegate_task al Auditor con plan completo.
---

# Quorum Review (Quorum Light)

Revisión previa obligatoria del **Auditor** antes de ejecutar cambios de riesgo medio/alto. No sustituye `human-approval`.

## Cuándo (obligatorio)

- Nuevo LXC o VM
- Actualizaciones mayores de aplicaciones
- Cambios de red, almacenamiento o backups
- Despliegues ≥ ~4 vCPU o ~8 GB RAM (u otros de riesgo medio-alto)

## Flujo

1. DevOps prepara plan detallado (VMID, IP, recursos, L1/L2, backups, alcance)
2. `delegate_task` al Auditor con el plan + inventario/contexto de nodo
3. Auditor emite **PASS** | **WARNING** | **FAIL**
4. Presentar al usuario: **plan + informe del Auditor**
5. Solo entonces pedir `Sí, ejecuta` (`human-approval`)
6. FAIL → replantear; no pedir ejecución sobre plan en FAIL sin corregir
7. WARNING → explicar en lenguaje claro al pedir aprobación

## Cómo delegar

- Subagent leaf; contexto **auto-contenido** (sin historial)
- Incluir: RAM/disco nodo, guests y commit de memoria, storage type (dir/raw vs snap), si Hermes≠PVE, script community-scripts vs L2, riesgos conocidos
- Pedir formato: VEREDICTO + hallazgos + recomendaciones + condiciones si WARNING
- Idioma del usuario (español en este lab)

## Relacionado

`homelab-governance`, `human-approval`, `backup-orchestrator`, `proxmox-lxc-manager`
