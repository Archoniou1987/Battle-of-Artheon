# Mind Game / Elixir / ABI timing contract v1 (2026-10-20)

## Interaction model

- **Mind Game:** Pressing an elixir immediately applies its HP, Mana, BUFF/EFF or Cleanse components through CombatEngine. Pressing a hand-authored **instant** ABI immediately resolves its whole action and effect children. The first such press opens the current round. No damage roll is executed by a preparatory elixir.
- **Combat resolution:** Pressing End Turn locks physical attacks and resolves committed **standard** ABI together with the established CombatRound and end_round EFF phases.
- **Finalization:** Resolve damage, periodic effects and healing, finalize death and one-shot only at end_round, tick effect durations, reveal previously concealed instant EFF.

## ABI contract

- Every ABI has explicitly authored `application_timing: "instant" | "standard"`. No automatic timing inference or deferral of components.
- ABI with direct damage, direct HP healing, DoT or HoT EFF **must** be `standard`. A mixed ABI is **all standard**, not split.
- Pure protective, stat-altering and cleansing ABI may be `instant`.
- One ABI per fighter per round, tracked by AbilityScheduler (including a sealed standard action). Instant presses cannot be canceled or followed by a second ABI.
- Validation rejects an instant ABI containing damaging or healing components. It does not silently rewrite timing.

## Elixir contract

- An active waist equipment item grants `elixir_slots` 1..4 (a legacy waist item defaults to 1). No active belt means zero usable slots.
- `CharacterState.elixir_slots` holds four persistent item-instance IDs, restored from the existing inventory save `elixirs` property. Ownership is verified at both UI and gameplay entry points.
- Consumable items require `type: consumable`, `charges`, `max_charges`, optional `cooldown_rounds` (default 1) and one or more `elixir_components`.
- Components are `{"kind":"heal","amount":100}`, `{"kind":"mana","amount":30}`, `{"kind":"effect","effect_id":"EFF005"}`, `{"kind":"cleanse","dispel_polarity":"DEBUFF","max_effects":2}`.
- HP/Mana recovery is immediate, capped at max pools (overheal is lost). The engine's normal EFFECT healing path is reused, with a consumable-specific clamp; standard ABI healing keeps existing semantics.
- EFF buffs and defensive effects use the same modifiers as every other EFF. Elixirs cannot deal direct damage or apply DoT; HoT can be applied immediately but obeys the normal delayed periodic tick timing.
- Only one elixir per round. All elixir slots share one cooldown; a charge is removed on successful activation, not on button hover or failed preflight. No item mutation on rejected action.
- Elixirs do not consume the ABI allowance. Stun prevents use.

## Information separation / hidden defense

- An instant EFF is mechanically active immediately but hidden from the opponent and player EFF panel until end_round. Known old and undisclosed new shared-duration stacks stay separate for cleansing.
- An elixir granting fire resistance is allowed to protect against a later fire spell in the SAME round without revealing the prediction ahead of time.
- The core mitigation equation remains unchanged: effective damage uses the existing resistance/reduction pipeline; protective EFF only adds its modifier overlay.

## Verification

- New regression: `tests/combat/elixir_mind_game_runner.gd` added to manually triggered `ABI Branch Tests`.
- Prior ABI/death/instant-surprise tests remain in the same workflow.
- **CI pending for the implementation changes**; passing previous commits does not validate this new integration.
- Test-only demo equipment and consumables use `ArenaTestElixirs` and a separate one-time grant marker. Values are samples, **not finalized game balance**.
