# MVP Execution Notes

## Core vs Scene
- Scene is orchestration only.
- Core is the source of truth via `GameSessionState`.
- Scene must trigger actions and re-render from the new state.

## GameSessionState fields
- carryAmount
- processedInventory
- coins
- unlockedZoneIDs
- upgrades
- processingQueue
- guidanceState

## Collision strategy
Layers:
- player
- resourceNodes
- interactionZones
- blockingGeometry

Rules:
- Only `blockingGeometry` blocks movement.
- `resourceNodes` and `interactionZones` are non-blocking.
- `interactionZones` are contact/proximity only, never push/block.

## Interaction highlight
- Show highlight on interaction-radius enter.
- Hide highlight on action complete or radius exit.
- Keep exactly one primary target.
- Primary target order: guidance match -> shortest distance -> stable zoneID tie-break.

## HUD guidance transitions
- carry == 0 -> collect resource.
- carry > 0 and processor waiting -> go processor input.
- processed ready in processor -> collect output.
- processed in inventory -> go sell zone.
- coins >= next zone price -> unlock gate.

## Scene responsibility guardrails
Scene does:
- entity lifecycle
- input handling
- rendering and feedback
- dispatching gameplay actions

Scene does not:
- own economy source-of-truth
- own progression source-of-truth
- own upgrade formulas
- own pricing logic

## Roadmap
1. Bootstrap + scene + movement + collision masks
2. Collect + carry limit
3. Process input/output
4. Sell + coins
5. Zone unlock
6. Upgrades
7. Debug panel runtime tuning
8. Economy config unification
9. HUD guidance state-based
10. Stabilization pass
11. v0.2 analytics SDK + rewarded ads

## Setting decision for v0.1
Use **Box Processing Yard** as default prototype theme for readability and faster placeholder art production.
