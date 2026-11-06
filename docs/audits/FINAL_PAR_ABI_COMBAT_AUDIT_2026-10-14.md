# FINAL PAR / ABI / COMBAT AUDIT — 2026-10-14

Репозиторий: `Archoniou1987/Battle-of-Artheon`, ветка `feature/character-inventory-ui-v1`. Проверенный исходный HEAD: `ae840220f5e7a45092680e1c6f92e3ca1d7f3cd6`. Последний коммит кода аудита: `106d5601ef2706bd10c72ec5cc7a852976633904`; за ним следует отдельный коммит этого отчёта.

Аудит выявил подтверждённые дефекты за пределами зелёного CI. Исправления выполнены в существующей ветке. Полное закрытие всех вопросов боевых правил не заявляется: открытые решения и новый CI перечислены ниже.

## Проверки

Godot 4.5.1.stable.official.f62fdbde1. Базовая ветка: 77 отдельных runners, 74 PASS, 3 FAIL. Текущий код: 79 runners, 79 PASS, 0 FAIL. Combat regression runner дополнительно объединяет 17 наборов кейсов. Каждый runner выполнялся с отдельным XDG_DATA_HOME; учитывались exit status и ERROR/SCRIPT ERROR.

Полный набор из 78 runners выполнен на последнем runtime-коммите; после изменения только отладочной сцены отдельно выполнен новый 79-й interaction runner (включён в Combat workflow). Повтор полного набора после debug-only изменения не выполнялся. Импорт и headless debug combat scene прошли. Адресные тесты покрывают A–E, broken MH/OH, fist+dagger identity/on-hit, PAR052 один раз, общий hit/crit, PAR035, PAR150 один раз и отсутствие flat packet, отсутствие каждого обязательного PAR/cache, PAR073, source mismatch, неверные overlay, NPC level100 и stun без списания маны/зависания Arena. RatingMatrix: концы/середина интервала, нулевые/отрицательные/большие рейтинги, неверные уровни/конфигурации/числа.

Все tracked JSON синтаксически корректны; YAML workflows разобран; git diff --check чист. Wrapper отрицательно проверен: SCRIPT ERROR с exit0 приводит к отказу. Ручная визуальная игровая сессия не выполнена.

| Workflow | Проверенный результат на ae84022 | Новый код |
|---|---|---|
| Combat Tests | [SUCCESS run 38576852661](https://github.com/Archoniou1987/Battle-of-Artheon/actions/runs/38576852661) | NOT RUN |
| ABI Branch Tests | [SUCCESS run 38576323704](https://github.com/Archoniou1987/Battle-of-Artheon/actions/runs/38576323704) | NOT RUN |
| PAR Migration Audit | [SUCCESS run 38576023787](https://github.com/Archoniou1987/Battle-of-Artheon/actions/runs/38576023787) | NOT RUN |

Новые Actions не запускались: доступный GitHub connector не предоставляет dispatch, gh/авторизованный CLI отсутствует. Старые три успеха не относятся к новым коммитам. Следующий workflow — PAR Migration Audit, затем ABI Branch Tests и Combat Tests, по одному запуску на итоговой ветке:

```bash
gh workflow run par-migration-audit.yml -R Archoniou1987/Battle-of-Artheon --ref feature/character-inventory-ui-v1
gh workflow run abi-branch-tests.yml -R Archoniou1987/Battle-of-Artheon --ref feature/character-inventory-ui-v1
gh workflow run combat-tests.yml -R Archoniou1987/Battle-of-Artheon --ref feature/character-inventory-ui-v1
```

## Найденные несовместимости

| ID / критичность | Файл и строки (база → текущие) | Причина и исправление |
|---|---|---|
| C01 / critical | `core/combat/combat_engine.gd` 192 → 548 | **Разные контракты попадания физической и магической атаки**. Физический путь добавлял базу попадания по уровням; магический использовал отдельный путь и мог терять PAR030. Старый combat_chance принимал устаревшие поля. Единая _common_hit_chance с PAR030; обязательные исходные PAR и конечные проценты, без старых hit/magic_hit. |
| C02 / critical | `core/combat/combat_engine.gd` 192 → 279 | **Магическая атака обходила фазу крита и PAR035**. Ветка нефизического урона завершалась до общей фазы критического удара. Общий PAR033/PAR035 для ATTACK; сохранена существующая формула 1.5 + PAR035_percent/100. |
| C03 / critical | `core/combat/combat_engine.gd` 150 → 276 | **PAR150 не применялся одинаково к оружию и ABI**. Магическое оружие обходило множитель рейтинга; дочерние ABI-события теряли маршрутизацию попадания и могли повторно масштабироваться после исправления. Процент PAR150 на магический базовый урон; флаги hit_already_resolved и magic_rating_applied исключают повторный hit/бонус. Нулевой базовый пакет остаётся нулём. |
| C04 / critical | `core/combat/par_combat_contract.gd` новый файл → 12 | **Неполные обязательные PAR могли использовать fallback**. Потребители принимали старые ключи/нулевые отсутствующие рейтинги; прямой ATTACK не проверял полный общий контракт. ParCombatContract проверяет 8 raw PAR, 8 семантических raw и 8 percent, согласованность PAR/source, PAR073, числовые значения и runtime overlays. Отказ до создания дочерних событий. |
| C05 / critical | `core/character/character_combat_builder.gd` 5 → 58 | **MH fist + OH dagger терял удар кулаком и владельца on-hit**. Наличие любого оружия исключало виртуальную MH; индексы эффектов могли привязываться к кулаку после вставки профиля. Сломанная MH ошибочно считалась занятой активным оружием. Сначала активная/виртуальная MH, затем OH; identity и эффекты сопоставлены по instance_id; PAR057 согласован с итоговыми профилями. |
| C06 / critical | `core/combat/combat_engine.gd` 18 → 21 | **Arena не загружала существующий физический баланс**. Arena создаёт CombatEngine.new(state), а _init сохранял пустой Dictionary. Это давало hit95 при любой разнице уровней и нулевую кривую брони. Пустой аргумент движка загружает data/balance/physical_combat.json. Отсутствие/повреждение обязательной структуры даёт invalid_balance_config. Явные тестовые конфигурации сохраняются как инъекция. Таблицы не изменены. |
| C07 / critical | `core/abilities/ability_scheduler.gd` 8 → 17 | **Stun обходился командами, scheduler и прямыми событиями**. Путь API/ABI мог потратить ману/поставить атаку при effective Tempo <= -100. Простой отказ команды мог остановить раунды Arena навсегда. Проверка action_status до очереди и затрат, проверка движка; Arena пропускает действия stunned участника и завершает раунд. |
| F01 / functional | `core/parameters/rating_matrix.gd` 6 → 13 | **RatingMatrix принимала некорректные данные и уровни**. Конверсия не обеспечивала строгий отказ на отсутствующую конфигурацию, нечисловые/нефинитные значения и уровни вне 1–100. Единственный владелец конверсии: RatingMatrix v1. NAN + диагностика на ошибке; нет универсального cap. |
| F02 / functional | `core/parameters/par_calculation_service.gd` 8 → 132 | **Дублирующая формула первичных характеристик и неиспользуемый rating_curve**. ParCalculationService повторял коэффициентный расчёт PrimaryStatEffects. rating_curve уже не имел потребителей. PrimaryStatEffects.calculate — одна реализация коэффициентов; ParCalculationService агрегирует PAR. Удалена только неиспользуемая старая настройка/аргументы. Все coefficients effects сохранены. |
| F03 / functional | `core/character/character_stats_service.gd` 7 → 62 | **PAR075 смешивался с прямым процентом**. Адаптер старого counterattack мог дублировать вклад и обходить RatingMatrix. PAR075 -> counterattack_rating -> RatingMatrix -> counterattack_rating_percent; прямой процент отдельным overlay. |
| F04 / functional | `core/character/character_stats_service.gd` 7 → 34 | **Постоянные прямые бонусы предметов не доходили до конверсии**. combat_stats *_direct_pct терялись между ItemRepository и CharacterStatsService. Старые fixtures записывали неканонические chance поля. Прямые проценты активных предметов суммируются один раз после конверсии суммарного raw рейтинга. Фикстуры приведены к explicit direct_pct. |
| F05 / functional | `core/character/character_stats_service.gd` 31 → 45 | **Некорректный direct_effects приводился к числу до проверки**. float("bad") мог превращать ошибочные входные данные в скрытый нулевой бонус. Валидация типа/finite каждого direct_effects значения перед сложением. |
| F06 / functional | `core/combat/combat_modifier_service.gd` 78 → 87 | **PAR073 имел запасной ручной блок вне ABI001**. Общий боевой вход не требовал PAR073, а getter давал 1 и clamp при отсутствии par_totals. PAR073 обязателен в общем контракте; существующая целая область 0–5 сохранена; fallback удалён. Также удалены неиспользуемые aliases flat_armour_pen/percent_armour_reduction. |
| F07 / functional | `core/npc/npc_combat_builder.gd` 3 → 3 | **NPC теряли рейтинги и использовали уровень шаблона**. NPC builder не обеспечивал canonical rating cache; encounter менял уровень после конверсии. Явные raw PAR в данных NPC, прежний direct dodge сохранён. Конверсия CharacterStatsService на фактическом instance.level до боя, без выдуманного player-derived NPC баланса. |
| F08 / functional | `core/character/character_state.gd` 66 → 66 | **Off-hand могла вытеснить занятую двуручным оружием руку**. CharacterState.equip не отсекал попытку OH при одном активном экземпляре в обеих руках. Отказ до мутации; для замены явно снять двуручное оружие. |
| F09 / functional | `ui/character/character_screen.gd` 49 → 49 | **UI показывал старые ключи и неверные единицы**. Остались magic_hit_rating/magic_crit_rating/magic_damage_flat, armour_penetration_rating/block_penetration_rating. Не реализованные значения отображались как 0%, OH range оставался после снятия. UI использует тот же snapshot; direct armour penetration/block crush правильных единиц, отсутствующее значение — тире, OH очищается. Визуальный дизайн сохранён. |
| T01 / obsolete_test_data | `tests/combat/magic_abi_scaling_runner.gd` 17 → 16 | **Старая проверка плоского магического бонуса вне зелёных workflows**. magic_abi_scaling ожидал 36/51 вместо процентных 30/42.5 и не запускался в трёх целевых workflows. Ожидания приведены к утверждённому PAR150, тест включён в PAR/ABI workflows. |
| T02 / obsolete_test_data | `core/data/test_fixture_loader.gd` 13 → 69 | **Fixtures перезаписывали обязательные боевые snapshots**. Прямые chance поля и замены целого combat_stats скрывали отсутствие PAR; weapon profile mutations не синхронизировали PAR057/ranges. Явные complete canonical fixture inputs, explicit percent caches, helper для профилей. Production fallback не добавлялся. |
| T03 / obsolete_test_data | `tests/map/hex_offset_geometry_runner.gd` 12 → 12 | **Ошибочная чётность отрицательных строк в hex-тесте**. %2 в GDScript даёт отрицательный остаток; сосед за границей имеет отрицательный y. Production использует &1. Только тест: одинаковая проверка чётности &1. Карта не менялась. |
| T04 / obsolete_test_data | `tests/ui/starting_village_runner.gd` 24 → 24 | **Village smoke ожидал прежнее имя кнопки**. Утверждённая сцена уже использует «Арена», тест ожидал «Тренировочное поле». Изменено ожидание теста; UI не менялся. |
| T05 / functional | `tools/run_godot_check.sh` новый файл → 22 | **Godot process exit0 мог маскировать ошибки в CI**. ABI/Combat workflow полагались на exit code, хотя Godot может вывести SCRIPT ERROR и выйти0; общие user saves загрязняли проверки. tools/run_godot_check.sh: exit status + diagnostic scan + timeout + отдельный XDG_DATA_HOME. Импорт/scene/tests ABI и Combat используют wrapper. PAR сохраняет свои проверки логов. |
| T06 / obsolete_test_data | `scenes/debug/debug_combat_viewer.gd` 41 → 192 | **Отладочная боевая сцена создавала NPC без PAR**. Debug scene использовала CombatantState.new и неполный weapon_profiles. Строгая валидация PAR073 выявила дефект при запуске реальной сцены после полного набора runners. Отладочные враги строятся каноническим CharacterCombatBuilder; explicit zero primary fixtures сохраняют прежний урон7 blunt. Добавлен standalone interaction runner и шаг Combat workflow. |

Строки относятся к указанным base/code commits, не к историческим отчётам. Дополнительные места изменения и повторное участие файлов в коммитах перечислены ниже.

## Архитектура и неизменённые решения

- **CharacterProgression**: base_stats/pending_stats PAR001..006, validation of restored primary keys.
- **CharacterState / ItemRepository / EquipmentState**: instance IDs, owner/inventory/equipment slots, canonical par_stats/par_bonuses/requirements; active durability filtering.
- **ParCalculationService + PrimaryStatEffects.calculate**: single PAR aggregate and coefficient implementation; canonical attack_ranges PAR050/051, PAR052/PAR057/PAR073.
- **CharacterStatsService + RatingMatrix**: registry source-key adapter, permanent raw rating sum, single level conversion plus direct overlays; same snapshot for UI and combat.
- **CharacterCombatBuilder / NpcCombatBuilder**: detached runtime snapshot, raw totals, percent caches, profiles identity and effects; NPC actual combat level.
- **ParCombatContract / ParAttackContract**: mandatory raw/cache validation and ABI001 count/profile/range validation before queue.
- **CombatModifierService / CombatEngine**: runtime EFF/TRA direct overlays, common hit and crit, magic percentage, physical mitigation and effects.
- **RoundOrchestrator / ArenaCombatSession / UI**: end-round death, stun-safe advancement; UI consumes same snapshot units; no visual redesign.

- Locked registry unchanged byte-for-byte from verified base; 108 sparse IDs, maximum PAR231. Never infer IDs from row index.
- Existing approved PAR035=crit_damage_rating; PAR075=counterattack_rating; PAR150=magic_damage_rating. Primary locked source_key metadata STR/DEX/... is not executable storage.
- RatingMatrix v1: rating/100 * lerp(20,2.5,(level-1)/99), integer levels1..100. Sum primary+equipment rating before conversion, direct percentage points after. No new universal cap.
- ABI001: A fists1, B MH1, C fist MH+OH2, D dual2, E two-hand1. Fist uses canonical PAR050 with configured2–4 blunt; PAR052 once per attack; instance identity controls on-hit. Latest request C explicitly supersedes earlier two-real-weapons-only wording.
- Existing crit formula 1.5 + crit_damage_rating_percent/100 retained. PAR150 multiplies magic base damage and never creates a flat packet.
- Existing physical hit table/armour curve wired to default engine without changing coefficients. Death finalization only end of round.
- No main changes, merge, PR or new branch. Logical commits on existing feature branch.

Реестр: 108 разреженных записей до PAR231, SHA256 `d263795762dbf0fe99f647f54c346b94ae66db53f9af3f6ec8568aa91fd3fc26`. Byte-for-byte равен исходному HEAD. Матрица всех PAR/source_key/ссылок находится в JSON отчёта. Общий адаптер не означает, что каждая объявленная игровая формула реализована.

Поиск старых обозначений в активных core/ui/data оставил только locked source_key metadata, явные проверки отказа старых полей и косметический текст END TURN. guaranteed_stats существует как запрет старого формата, не как источник бонусов. uses_magic_hit/magic_hit_roll/rolls.magic_hit оставлены как routing/roll metadata события, а не отдельные характеристики персонажа.

Сохранение игрока/предметов и канонических характеристик проверяется existing progression/ownership/exploit/map tests. Это не доказательство полного сохранения NPC instance: см. R03. Порядок ATTACK: Hit → Tempo → Dodge → Manual Block → Auto Block → Block Crush → Crit → Damage; end-round death сохранён. Delivery DIRECT/AREA/CHAIN имеет отдельную существующую модель, см. R02.

## Коммиты и изменённые файлы

| SHA | Назначение |
|---|---|
| [6567008ccb496614a6be03d8c6e7101de2919ac1](https://github.com/Archoniou1987/Battle-of-Artheon/commit/6567008ccb496614a6be03d8c6e7101de2919ac1) | fix(combat): unify canonical PAR ratings, magic attacks and weapon ownership |
| [9a7623862432f7e8f83cf4b92aedacf7f01b0eff](https://github.com/Archoniou1987/Battle-of-Artheon/commit/9a7623862432f7e8f83cf4b92aedacf7f01b0eff) | test(combat): cover canonical PAR paths and reject false-green Godot checks |
| [8975369d11a11d7aee30329e4da33fc740b2e529](https://github.com/Archoniou1987/Battle-of-Artheon/commit/8975369d11a11d7aee30329e4da33fc740b2e529) | fix(combat): enforce runtime balance, block capacity and numeric overlays |
| [106d5601ef2706bd10c72ec5cc7a852976633904](https://github.com/Archoniou1987/Battle-of-Artheon/commit/106d5601ef2706bd10c72ec5cc7a852976633904) | fix(debug): construct combat scene enemies with canonical PAR inputs |

| Файл | SHA |
|---|---|
| `core/abilities/ability_scheduler.gd` | `6567008ccb496614a6be03d8c6e7101de2919ac1` |
| `core/character/character_combat_builder.gd` | `6567008ccb496614a6be03d8c6e7101de2919ac1` |
| `core/character/character_state.gd` | `6567008ccb496614a6be03d8c6e7101de2919ac1` |
| `core/character/character_stats_service.gd` | `6567008ccb496614a6be03d8c6e7101de2919ac1` |
| `core/character/primary_stat_effects.gd` | `6567008ccb496614a6be03d8c6e7101de2919ac1` |
| `core/combat/combat_command_api.gd` | `6567008ccb496614a6be03d8c6e7101de2919ac1` |
| `core/combat/combat_damage_payload.gd` | `6567008ccb496614a6be03d8c6e7101de2919ac1` |
| `core/combat/combat_engine.gd` | `6567008ccb496614a6be03d8c6e7101de2919ac1` |
| `core/combat/combat_modifier_service.gd` | `6567008ccb496614a6be03d8c6e7101de2919ac1` |
| `core/combat/par_attack_contract.gd` | `6567008ccb496614a6be03d8c6e7101de2919ac1` |
| `core/combat/par_combat_contract.gd` | `6567008ccb496614a6be03d8c6e7101de2919ac1` |
| `core/map/map_encounter_combat_service.gd` | `6567008ccb496614a6be03d8c6e7101de2919ac1` |
| `core/npc/npc_combat_builder.gd` | `6567008ccb496614a6be03d8c6e7101de2919ac1` |
| `core/parameters/par_calculation_service.gd` | `6567008ccb496614a6be03d8c6e7101de2919ac1` |
| `core/parameters/rating_matrix.gd` | `6567008ccb496614a6be03d8c6e7101de2919ac1` |
| `data/character/primary_stat_effects.json` | `6567008ccb496614a6be03d8c6e7101de2919ac1` |
| `data/npc/starting_region_npcs.json` | `6567008ccb496614a6be03d8c6e7101de2919ac1` |
| `ui/arena/arena_combat_session.gd` | `6567008ccb496614a6be03d8c6e7101de2919ac1` |
| `ui/arena/arena_screen.gd` | `6567008ccb496614a6be03d8c6e7101de2919ac1` |
| `ui/character/character_screen.gd` | `6567008ccb496614a6be03d8c6e7101de2919ac1` |
| `.github/workflows/abi-branch-tests.yml` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `.github/workflows/combat-tests.yml` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `.github/workflows/par-migration-audit.yml` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `core/data/test_fixture_loader.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `data/test/bot_equipment_templates.json` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `data/test/item_generator_eff001_template.json` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `data/test/item_generator_template.json` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `data/test/items.json` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/character/character_combat_builder_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/character/ten_player_stats_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/combat/action_resolver_cases.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/combat/aoe_cases.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/combat/combat_api_cases.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/combat/combat_command_api_cases.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/combat/combat_modifier_service_cases.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/combat/combat_stress_cases.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/combat/delivery_defence_cases.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/combat/duel_smoke_cases.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/combat/effect_stacking_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/combat/engagement_cases.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/combat/equipment_fixture_cases.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/combat/group_combat_ability_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/combat/group_combat_cases.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/combat/group_combat_simulator_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/combat/magic_abi_scaling_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/combat/opportunity_action_cases.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/combat/physical_attack_cases.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/combat/resist_effect_cases.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/combat/round_orchestrator_cases.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/combat/zone_combat_cases.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/items/combat_defeat_consequence_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/items/generated_eff001_combat_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/items/hundred_bot_durability_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/items/item_abi_combat_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/loot/combat_loot_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/loot/dagger_level_drop_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/loot/npc_worn_loot_chain_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/map/hex_map_group_encounter_e2e_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/map/hex_offset_geometry_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/map/map_encounter_combat_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/map/square_map_encounter_bridge_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/map/square_map_group_encounter_e2e_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/parameters/final_par_combat_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/parameters/par_migration_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/parameters/rating_matrix_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/ui/character_screen_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tests/ui/starting_village_runner.gd` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `tools/run_godot_check.sh` | `9a7623862432f7e8f83cf4b92aedacf7f01b0eff` |
| `core/character/character_stats_service.gd` | `8975369d11a11d7aee30329e4da33fc740b2e529` |
| `core/combat/combat_engine.gd` | `8975369d11a11d7aee30329e4da33fc740b2e529` |
| `core/combat/combat_modifier_service.gd` | `8975369d11a11d7aee30329e4da33fc740b2e529` |
| `core/combat/par_combat_contract.gd` | `8975369d11a11d7aee30329e4da33fc740b2e529` |
| `tests/parameters/final_par_combat_runner.gd` | `8975369d11a11d7aee30329e4da33fc740b2e529` |
| `.github/workflows/combat-tests.yml` | `106d5601ef2706bd10c72ec5cc7a852976633904` |
| `scenes/debug/debug_combat_viewer.gd` | `106d5601ef2706bd10c72ec5cc7a852976633904` |
| `tests/ui/debug_combat_scene_runner.gd` | `106d5601ef2706bd10c72ec5cc7a852976633904` |

## Оставшиеся задачи и риски

- **R01 / P0** — На новом HEAD три GitHub Actions ещё не запускались. Следующий шаг: Запустить PAR Migration Audit, затем ABI Branch Tests и Combat Tests на этой ветке; проверять head_sha. Connector не имеет dispatch, gh/credentials отсутствуют.
- **R02 / P1** — DIRECT/AREA/CHAIN создают DAMAGE после cast-level hit и не проходят ATTACK crit phase. MELEE/PROJECTILE/weapon ATTACK используют общий PAR033/PAR035. Следующий шаг: Утвердить, должны ли DIRECT/AREA/CHAIN (включая прямые physical и heal компоненты) критовать; затем добавить delivery-specific тесты. Не менять баланс на предположении.
- **R03 / P1** — NpcInstance не имеет полного persistence-контракта; encounter бой строится из template, а не из изменяемого instance inventory/equipment. Следующий шаг: Согласовать владение состоянием NPC, сериализацию и влияние instance equipment на combat; не объявлять template rebuild проверкой NPC save roundtrip.
- **R04 / P1** — Tempo -1..-99: CPU scheduler и командный API не полностью одинаково принимают probabilistic action availability. Hard stun <=-100 исправлен. Следующий шаг: Утвердить единое правило частичного отрицательного Tempo до изменения расписания/очередей.
- **R05 / P2** — Не все 108 записей реестра реализованы в runtime: например PAR076 не заменяет coefficient0.8; часть typed damage/penetration/regen параметров декларативна. Следующий шаг: Составить отдельные утверждённые формулы/контракты для неиспользуемых параметров; таблица reference evidence не равна доказательству реализации.
- **R06 / P2** — NOTICE/policy требуют неизменности, но metadata фиксирует согласованное исключение для PAR035/PAR075/PAR150; отдельные provisional notes/status не отражают все новые реализации. Следующий шаг: Согласовать отдельный policy changelog/обновление метаданных; текущий locked registry не изменён.
- **R07 / P2** — UI проверен headless construction/smoke, не выполнен ручной визуальный playthrough или visual_capture. Явная непустая balance-инъекция остаётся caller-owned для тестов. Следующий шаг: Ручной бой в Godot Editor: Character -> Inventory -> Arena, A–E, UI percentages, two-hand locks; production callers должны использовать default approved balance.

## Артефакты

- `FINAL_PAR_ABI_COMBAT_AUDIT_2026-10-14.json`: findings, строки, изменённые файлы/SHA, все результаты и PAR reference matrix.
- `BATTLE_OF_ARTHEON_HANDOFF_2026-10-14.json`: самодостаточная передача в новый чат.
- `final_par_abi_combat_logs_2026-10-14.zip`: исходные baseline/current результаты и логи, import/debug scene и отрицательная проверка CI wrapper.
