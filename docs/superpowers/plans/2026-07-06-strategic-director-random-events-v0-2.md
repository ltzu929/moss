# Strategic Director And Random Events v0.2 Plan

## Macro Direction

This slice upgrades MOSS from a fixed event spine into a campaign layer:

- Fixed main events remain historical anchors.
- Strategic Director reads current state and turns it into pressure, goals, warnings, and forecasts.
- Random Event Director turns existing docs into constrained pressure events between anchors.
- Every new random event must carry a source reference and design role.

This is the first v0.2 system slice, not the full campaign simulation endpoint.

## Implemented Slice

### Strategic Director

- Added `scripts/systems/strategic_director.gd`.
- Inputs: year, month, average order, average hope, average authority, energy, CPU, max CPU, decision tags, event states, technology tags.
- Outputs: `pressure_score`, `pressure_band`, `dominant_axis`, `active_goal`, `warnings`, and `forecasts`.
- Integrated a right-side main UI panel with pressure, goal, warning, and forecast text.

### Random Event Director

- Added `scripts/resources/random_event.gd`.
- Added `scripts/systems/random_event_director.gd`.
- Added `data/random_events/` as a separate pool from fixed date events.
- Random events are filtered by year, pressure score, pressure axis, and cooldown, then selected by deterministic weighted RNG.

### Source-Constrained Event Pool

Added four random events based on existing docs:

- Underground city lottery petitions.
- Engine maintenance fatigue.
- Digital life public appeal.
- Temporary authorization audit.

Each event declares `source_reference` and `design_role`, and every option writes `event_state.random_*`.

### Runtime Integration

- `MainOS` loads random events from disk.
- `MainOS` exposes `get_strategic_director_snapshot()`, `update_strategic_director_ui()`, `get_random_event_candidates()`, `set_random_seed()`, and `try_trigger_random_event()`.
- Automatic random events only run during live Timer ticks, not stopped manual test ticks.
- Triggered random events reuse the existing event popup, consequence application, logs, and state writes.

## Next Big-Version Epics

1. Campaign Objective Chains
   - Convert active goals into multi-year objectives with success/failure consequences.

2. Route-Specific Crisis Windows
   - Let technology route and core history alter random event weights and available responses.

3. Strategic Forecast Interaction
   - Make forecasted risks visible as actionable entries that can be reduced before they fire.

4. Random Event Memory
   - Add ending or mid-event reads for representative `event_state.random_*` outcomes.

5. Balancing Telemetry
   - Record pressure bands and triggered random event IDs for deterministic test routes.

6. Save Snapshot Readiness
   - Make strategic snapshots and random event cooldowns exportable for future save/load.

## Verification Targets

- `tests/strategic_director_test.tscn`
- `tests/random_event_director_test.tscn`
- `tools/run_godot_tests.py` full suite

## Known Risks

- Random event pacing is intentionally conservative and source-constrained.
- The current UI is text-first; future work should make forecasts actionable without turning the panel into a modal.
- Random events currently write lightweight states but do not yet affect ending explanation.
