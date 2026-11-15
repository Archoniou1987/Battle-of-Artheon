extends SceneTree

## Arena's NPC must select physical block zones via the same command path as
## the player, and CombatEngine must resolve a real blocked attack.
var failures: Array[String] = []

func _check(ok: bool, name: String) -> void:
	if not ok:
		failures.append(name)
		print("ARENA_ENEMY_BLOCK_FAIL=",name)

func _initialize() -> void:
	var repo := ItemRepository.new()
	var hero := CharacterState.new("ARENA_NPC_BLOCK_HERO","Block test",1)
	var sword := {"instance_id":"BLOCK_TEST_SWORD","equip_slots":["main_hand"],"slot_usage":["main_hand"],"par_stats":{"PAR057":1},"damage":{"min":3.0,"max":4.0,"type":"slashing"}}
	ItemDurabilityService.initialize_item(sword,100)
	_check(repo.add_item(sword),"item_registered")
	_check(hero.receive_item("BLOCK_TEST_SWORD",repo),"item_owned")
	_check(hero.equip("main_hand","BLOCK_TEST_SWORD",repo),"sword_equipped")
	var arena := ArenaCombatSession.new(hero,repo)
	var npc := arena.fighter(false)
	var player := arena.fighter(true)
	var capacity := CombatModifierService.manual_block_zone_capacity(npc)
	_check(capacity>=1 and capacity<=4,"npc_par073_capacity")
	var first := ArenaCombatSession.enemy_manual_block_plan(npc,1)
	var second := ArenaCombatSession.enemy_manual_block_plan(npc,2)
	_check(first.size()==capacity and second.size()==capacity,"npc_plan_respects_capacity")
	_check(first!=second,"npc_plan_changes_between_rounds")
	_check(first.has("waist"),"npc_first_round_waist_guard")
	_check(CombatModifierService.manual_block_zones(npc).is_empty(),"npc_has_no_pre_round_guard")
	var blocks: Array[String] = []
	for z in ["chest","arms","waist","legs"]:
		if blocks.size()<CombatModifierService.manual_block_zone_capacity(player):
			blocks.append(z)
	var result := arena.play_round(["waist"],blocks)
	_check(bool(result.get("ok",false)),"round_executes")
	if bool(result.get("ok",false)):
		_check(CombatModifierService.manual_block_zones(npc)==first,"npc_guard_selected_in_real_round")
		# Check a block through the unmodified shared CombatEngine with
		# deterministic hit/dodge/block-crush rolls (no made-up NPC damage).
		var event := arena.state.create_event(CombatEvent.Kind.ATTACK,arena.player_id,ArenaCombatSession.ENEMY_ID,{
			"zone":"waist","damage_type":"slashing","raw_damage":10.0,
			"rolls":{"hit":1,"dodge":100,"auto_block":100,"block_crush":100,"crit":100,"damage":0.5}
		})
		arena.engine.resolve_event(event)
		_check(String(event.result.get("outcome",""))=="manual_block","npc_real_manual_block_outcome")
		var lines := ArenaCombatLog.lines_for_round(arena.state.event_log,arena.state.round_number,arena.player_id,arena.ability_scheduler.definitions)
		_check(" ".join(PackedStringArray(lines)).contains("ручной блок"),"npc_block_visible_in_arena_log")
		var miss := arena.state.create_event(CombatEvent.Kind.ATTACK,arena.player_id,ArenaCombatSession.ENEMY_ID,{
			"zone":"head" if not first.has("head") else "legs",
			"damage_type":"slashing","raw_damage":10.0,
			"rolls":{"hit":1,"dodge":100,"auto_block":100,"block_crush":100,"crit":100,"damage":0.5}
		})
		arena.engine.resolve_event(miss)
		_check(String(miss.result.get("outcome",""))!="manual_block","npc_guard_only_selected_zones")
	print("ARENA_ENEMY_MANUAL_BLOCK=",("PASS" if failures.is_empty() else "FAIL")," failures=",failures)
	quit(0 if failures.is_empty() else 1)
