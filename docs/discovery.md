# Discovery notes (Phase 0)

Source: round 3 harvester output, kept local (not in this repo). Entries cite file
names and line numbers only. No LOUD source is reproduced here. Line numbers refer to
files inside LOUD's `lua.scd` archive, as extracted by `tools/discover_ai.sh`.

## Personality and AI identity

- LOUD's AI is selected by the lobby key `'loud'`, registered in
  `lua/AI/CustomAIs_v2/ExtrasAI.lua` (display name "AI: LOUD", version 8.23).
- `aipersonality.lua` defines `AverageJoe` and `Rommel` templates only. Neither is
  used by the `'loud'` AI, so their weights are not knobs for this milestone.
- Brains check `Personality == 'loud'` at `aiutilities.lua` lines 858 and 1041, and
  at `sim/ScenarioUtilities.lua` line 963. A style must keep this key.

## Builder registration (hook point)

- `BuilderGroups` is a global table. `AddGlobalBaseTemplate` in
  `lua/AI/aiaddbuildertable.lua` (line 21) defines a local `AddGlobalBuilderGroup`
  (line 27) that reads from it per brain.
- Builder groups are shared by all brains, so any change must apply per brain.
  See option 1 below.

## Candidate knobs (inside `lua/AI/AIBuilders/`)

- `Loud_AI_Formations_Land.lua`
  - `InstanceCount = 12` (line 59): concurrent instances of the artillery builder.
  - `UntMax = 45` (line 354): unit-count trigger ceiling for a formation.
  - `GuardTimer = 30` (line 359): guard time before a formation moves.
  - `AggressiveMove = true`: boolean; a strong `zerg_rush` candidate.
- `Loud_Expansion_Base_Templates.lua`
  - `ExpansionLayout` (line 7) and `ExpansionLayout_II` (line 1294): expansion schedule.
- `lua/AI/altaiutilities.lua`
  - `minimum_baserange = 180 + IMAPSize/4` (line 277 area): base spacing, with a
    map-size term. Deterministic for a given map.

## Decision: option 1 (per-brain copy)

1. At game init, build a QAI copy of each builder group, with style values applied.
2. Add one hook at the top of `AddGlobalBaseTemplate`: if the brain's personality is
   `'loud'` and a style is active, use the QAI copy. Otherwise use the stock table.
3. Stock brains keep the original `BuilderGroups`, so the stock slot stays stock.
4. The copy runs before any base is built, so the timing is deterministic.

## Open questions

- How LOUD's external mod system loads mods. Archives contain `mods/<name>/mod_info.lua`,
  which suggests QAI could ship as a mod folder. Confirm on the LOUD Discord.
- Whether the copy can be built from the global `BuilderGroups` at init without
  depending on load order. To check in the game.
