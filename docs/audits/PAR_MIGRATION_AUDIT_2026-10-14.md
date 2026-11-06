# Battle of Artheon — аудит миграции PAR, 14.10.2026

Ветка: `feature/character-inventory-ui-v1`. Исходный SHA: `d72dda833c19d1d611172437f1199c39da8ee9c9`.

**Подтверждённые ошибки исправлены. Полное закрытие всех PAR требует согласования пяти рейтингов и поведения оружия только во второй руке.** Реестр и утверждённые коэффициенты не изменены.

## Исправления

| ID | Категория | Проблема и результат |
|---|---|---|
| PAR-01 | critical | ItemGenerator emits legacy primary IDs and ignored base_stats/final_stats. Generate PAR001–PAR006; put scaled contributions in par_stats and rolled contributions in par_bonuses. Each weapon contributes PAR057=1 exactly once. |
| PAR-02 | critical | Generated materialized items use template_id, colliding with the unrelated arena template resolver. Use generated_from_template as provenance; retain strict template_id resolution for linked arena instances. |
| PAR-03 | critical | Basic attacks can bypass PAR when snapshots are absent; simulator/counterattacks take old numeric profiles. ParAttackContract validates mandatory PAR052/PAR057/PAR073 and ranges; WeaponAttackProfile resolves basic damage only from PAR. Commands, simulation and counterattacks share it. Specialised non-basic profiles remain intact. |
| PAR-04 | critical | PAR057 is silently clamped, cached independently of totals, and does not prove two distinct weapons. Validate exact integer count 1 or 2, matching hand metadata, two distinct weapon instance IDs for dual wield, and one basic hit per weapon. Reject malformed sequences before queue mutation. |
| PAR-05 | critical | ParCalculationService and CharacterStatsService recalculate unarmed damage with hidden defaults. Only ParCalculationService reads mandatory unarmed configuration. Missing/invalid config or range rejects the snapshot; UI reads the canonical ranges. |
| PAR-06 | functional | MH/OH range ownership is inferred from preferred item.slot rather than actual equipment placement. Resolve actual equipped hand, deduplicate two-handed instances, and attach actual hand identity to runtime metadata. OH-only weapons fail explicitly pending a rule decision. |
| PAR-07 | functional | NPC primary IDs and resource reads retain END/WIS and the old six-key schema. Migrate explicit primary keys. Add explicit NPC PAR damage/count/block snapshots without recalculating NPC balance. Preserve configured NPC HP/mana/damage and existing resource coefficients. |
| PAR-08 | functional | Forced movement contests use STR/STA and an END compatibility fallback. Use PAR001/PAR006 and diagnose missing contest parameters; engine fixtures explicitly declare zero primary inputs. |
| PAR-09 | functional | Canonical PAR armour totals are not applied to combatant.armour. Aggregate structural armour once at PAR boundary and build combat armour from general PAR100–104 plus typed PAR105–124. Preserve low-level EquipmentBuilder structural support. |
| PAR-10 | functional | Registry armour_pen_flat/armour_pen_pct names do not match engine read names. Add explicit same-unit aliases for PAR125/PAR126; preserve existing mitigation math. |
| PAR-11 | functional | PAR071/PAR075 direct percentages can be hidden behind zero rating-derived percentages. Feed exact direct percentage contributions into the existing direct-percent overlays; no conversion to rating. |
| PAR-12 | functional | Arena primary popup uses old primary keys; item dialogs read guaranteed_stats/bonuses. Use canonical primary IDs, par_stats/par_bonuses and locked registry display names. |
| PAR-13 | functional | Character UI recomputes HP/mana with obsolete coefficients. Display existing canonical PAR resource contributions instead of duplicating formulas. |
| PAR-14 | functional | Mixed primary schemas can pass progression restore by carrying extra keys. Require exactly six canonical primary keys and retain the existing stat-point conservation checks; surface rejected progression loads. |
| PAR-15 | functional | Alternate ring slot equip succeeds, but saved equipment validation rejects ring2-only placement of a ring1-compatible item. Apply the same alternate ring-slot contract on restore; persistence smoke now saves and restores both rings. |
| PAR-16 | functional | Missing primary data, unknown PAR contributions and unresolved equipped instances can silently disappear from snapshots. Validate mandatory primary/schema/config data, reject unknown/non-finite contributions and unresolved equipped references. No compatibility translation is introduced. |
| PAR-17 | obsolete_test_data | Tests inject legacy primary stats and numeric weapon overrides into CharacterCombatBuilder. Builder rejects those overrides; character integration fixtures equip real canonical test weapons. Low-level engine fixture preparation is explicit in development-only TestFixtureLoader. |
| PAR-18 | obsolete_test_data | Generator, equipment, loot and UI fixtures assume removed fields, old template provenance or numeric aggregation by EquipmentBuilder. Migrate assertions and input data; use CharacterCombatBuilder for generated-item integration, explicit PAR in engine fixtures, canonical item fields, durability and valid provenance. |
| PAR-19 | obsolete_test_data | ABI001 fixture encodes two hits in a single basic weapon profile. Keep multi-hit AP-group coverage as an explicitly named specialised fixture profile; ordinary ABI001 remains one hit per weapon. |
| PAR-20 | functional | Two combat workflows run Godot 4.4.1 while target engine is 4.5.1. Align both to 4.5.1. Add manually dispatched PAR Migration Audit with log-error gates and isolated per-test save directories. No GitHub Actions were launched. |
| PAR-21 | critical | A declared weapon with missing damage may silently become an unarmed attack; generator omits weapon identity/reach metadata. Reject declared weapons without a mandatory damage range. Preserve generated weapon class, item type, specialised attack metadata, off-hand requirements and equip requirements using detached copies. Negative contract test verifies no unarmed substitution. |

Исходные файлы и точные номера строк каждого совпадения перечислены в JSON (`baseline_locations`). Полный перечень изменённых файлов — `changed_files`.

## Проверки

Godot 4.5.1, импорт без ошибок. Финальный изолированный прогон: 74 PASS, 2 FAIL, всего 76 самостоятельных тестовых сценариев. Два сбоя карты/деревни воспроизведены на исходном SHA; это не ошибки миграции. CI не запускался.

Новый PAR-тест проверяет безоружную атаку, оба диапазона, бонусы ровно один раз, фактические слоты, броню, сохранение, два разных оружия, отсутствие обязательных данных, запрет многократного basic-hit одного оружия и атомарный отказ всей последовательности.

## Открытые вопросы

1. Нет точных PAR для: `counterattack_rating`, `crit_damage_rating`, `magic_crit_rating`, `magic_damage_rating`, `magic_hit_rating`. Назначать им процентные параметры без согласования нельзя. Действующие формулы сохранены; эти значения явно перечислены в `unmapped_derived`.
2. Только оружие во второй руке: сборка отклоняется с диагностикой. Нужен утверждённый вариант поведения; запасной расчёт не добавлен.
3. `hex_offset_geometry_runner.gd` падает также на исходном коммите.
4. `starting_village_runner.gd` ожидает «Тренировочное поле» и падает также на исходном коммите.
5. Не каждый параметр реестра уже реализован в бою. Например, PAR035 и существующий множитель критического урона требуют явного согласования семантики перед подключением. Аудит не меняет баланс для заполнения таких пробелов.

## Коммиты

- `2ec41c3089875c60100fff049b43864e3ff112e8`
- `9b280c829afefef73b617a39d3d70f3d52582500`
- `60b414174ee90b8c37758cfa9ce416b3fa66687e`
- `0437e717250684779a1d2066d49ef330aff5e1a5`

## Следующий запуск

[PAR Migration Audit](https://github.com/Archoniou1987/Battle-of-Artheon/actions/workflows/par-migration-audit.yml), ветка `feature/character-inventory-ui-v1`. Он проверяет профильную цепочку, использует Godot 4.5.1 и отдельные сохранения для каждого сценария. PR и merge не выполнялись.
