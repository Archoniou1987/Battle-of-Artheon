extends SceneTree

# Regression: opening the Arena from the village must construct a visible screen.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	if packed == null:
		push_error("ARENA_OPEN_SMOKE=FAIL: main scene missing")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	main.call("_open_panel", "Арена")
	await process_frame
	var arena := main.get_node_or_null("ArenaScreen") as ArenaScreen
	if arena == null or not arena.visible or arena.square_content == null:
		push_error("ARENA_OPEN_SMOKE=FAIL: arena was not opened")
		quit(1)
		return
	# A11: diagnostic count is derived from the live PAR registry, not
	# a stale hardcoded "108" when new PAR identifiers are added.
	if not arena.par_report_dialog.title.contains(str(ParCalculationService.registry().size())):
		push_error("ARENA_OPEN_SMOKE=FAIL: PAR diagnostic header differs from registry")
		quit(1)
		return
	if arena.player_slots.size() != 14 or arena.enemy_slots.size() != 14:
		push_error("ARENA_OPEN_SMOKE=FAIL: equipment slots missing")
		quit(1)
		return
	# Capacity never preselects manual blocks: all four zones are chosen by player.
	arena.set_defense_capacity(4)
	if not arena.selected_block_zones().is_empty():
		push_error("ARENA_OPEN_SMOKE=FAIL: manual blocks unexpectedly preselected")
		quit(1)
		return
	for zone in ["chest", "arms", "waist", "legs"]:
		arena._select_zone(true, zone)
	if arena.selected_block_zones().size() != 4:
		push_error("ARENA_OPEN_SMOKE=FAIL: four-zone protection unavailable")
		quit(1)
		return
	arena._select_zone(true, "arms") # drop one explicitly selected zone
	arena._select_zone(true, "head") # choose a non-adjacent replacement
	if arena.selected_block_zones().size() != 4 or not arena.selected_block_zones().has("head") or arena.selected_block_zones().has("arms"):
		push_error("ARENA_OPEN_SMOKE=FAIL: independent block zone selection")
		quit(1)
		return
	if arena.ability_buttons.size() != 6:
		push_error("ARENA_OPEN_SMOKE=FAIL: expected exactly six ABI controls")
		quit(1)
		return
	# Avatar readout comes from real effective EFF, never the uneffected
	# CharacterStatsService snapshot. This test runs at a disclosure boundary.
	var actor := arena.combat_session.fighter(true)
	var baseline_crit := float(CombatModifierService.combat_readout(actor,arena.combat_session.state.round_number+1).get("crit_after_dr_pct",0.0))
	actor.active_effects.append({
		"effect_id":"EFF_UI_ACTIVE_CRIT",
		"definition":{"kind":"buff","name":"Боевое усиление","crit_chance_direct_pct":25.0,"physical_damage_outgoing_direct_pct":15.0},
		"start_round":1,"remaining_rounds":2,"revealed":true
	})
	arena._sync_combat_session()
	var displayed_crit := float(arena.published_player_readout.get("crit_after_dr_pct",0.0))
	if displayed_crit <= baseline_crit or not is_equal_approx(displayed_crit,CombatMath.effective_crit(
		CombatModifierService.effective_percent(actor,"crit_chance_rating",1),0.0)):
		push_error("ARENA_OPEN_SMOKE=FAIL: avatar readout ignores active ABI/EFF")
		quit(1)
		return
	arena._show_fighter_details(true)
	if not arena.fighter_popup_text.text.contains("%.2f%%" % displayed_crit) or not arena.fighter_popup_text.text.contains("+15.00%"):
		push_error("ARENA_OPEN_SMOKE=FAIL: avatar popup does not show effective buff values")
		quit(1)
		return
	arena.fighter_popup.hide()
	actor.active_effects.clear()
	# A11: negative EFF overlays must use the exact same COMBAT readout
	# as buffs. Neither the avatar nor inventory may invent a second formula.
	actor.active_effects.append({
		"effect_id":"EFF_UI_ACTIVE_DEBUFF",
		"definition":{"kind":"debuff","name":"Боевой штраф","crit_chance_direct_pct":-10.0,"physical_damage_outgoing_direct_pct":-12.0},
		"start_round":1,"remaining_rounds":2,"revealed":true
	})
	arena._sync_combat_session()
	var debuffed: Dictionary = arena.published_player_readout
	var effective_crit := CombatMath.effective_crit(
		CombatModifierService.effective_percent(actor,"crit_chance_rating",1),0.0)
	if not is_equal_approx(float(debuffed.get("crit_after_dr_pct",NAN)),effective_crit) or not is_equal_approx(float(debuffed.get("physical_outgoing_bonus_pct",NAN)),-12.0):
		push_error("ARENA_OPEN_SMOKE=FAIL: avatar readout ignores active debuff modifiers")
		quit(1)
		return
	arena._show_fighter_details(true)
	if not arena.fighter_popup_text.text.contains("%.2f%%" % effective_crit) or not arena.fighter_popup_text.text.contains("-12.00%"):
		push_error("ARENA_OPEN_SMOKE=FAIL: avatar popup omits effective debuff values")
		quit(1)
		return
	arena.fighter_popup.hide()
	actor.active_effects.clear()
	arena._sync_combat_session()
	# Use a canonical definition for UI selection; no fake combat damage.
	arena.combat_session.ability_scheduler.loadouts[arena.combat_session.player_id] = ["ABI301"]
	arena.combat_session.player_ability_slots[0] = "ABI301"
	# Keep the snapshot max pool canonical: press now writes spent mana back.
	arena.combat_session.fighter(true).mana = arena.combat_session.fighter(true).max_mana
	arena._refresh_ability_buttons()
	if arena.ability_buttons[0].disabled:
		push_error("ARENA_OPEN_SMOKE=FAIL: equipped ABI remains disabled")
		quit(1)
		return
	arena._select_ability(0)
	if arena.selected_ability != "" or arena.combat_session.locked_ability_id != "" or arena.pending_ability_id != "ABI301":
		push_error("ARENA_OPEN_SMOKE=FAIL: ABI activated before confirmation")
		quit(1)
		return
	arena._confirm_ability()
	if arena.selected_ability != "ABI301":
		push_error("ARENA_OPEN_SMOKE=FAIL: ABI selection does not reach Arena")
		quit(1)
		return
	# Confirmed action remains committed; second tap cannot deselect it.
	arena._select_ability(0)
	if arena.selected_ability != "ABI301" or arena.combat_session.locked_ability_id != "ABI301":
		push_error("ARENA_OPEN_SMOKE=FAIL: committed ABI could be canceled")
		quit(1)
		return
	if not arena.ability_buttons[0].disabled or arena.combat_session.active_round == null:
		push_error("ARENA_OPEN_SMOKE=FAIL: ABI press not locked by combat")
		quit(1)
		return
	# No permanent debug placeholders; only real EFF are rendered.
	var buff_row:=arena.effects_rows.get("player_Баффы") as HBoxContainer
	var debuff_row:=arena.effects_rows.get("player_Дебаффы") as HBoxContainer
	if buff_row==null or debuff_row==null or buff_row.visible or debuff_row.visible:
		push_error("ARENA_OPEN_SMOKE=FAIL: empty EFF rows should be hidden")
		quit(1)
		return
	var player:=arena.combat_session.fighter(true)
	for i in range(6):
		player.active_effects.append({
			"effect_id":"EFF_UI_TEST_%d" % i,
			"definition":{"kind":"buff","name":"Усиление %d" % i},
			"source_id":player.combatant_id,
			"start_round":arena.combat_session.state.round_number+1,
			"remaining_rounds":3,
			"stacks":2
		})
	arena._refresh_effect_display()
	if not buff_row.visible or debuff_row.visible:
		push_error("ARENA_OPEN_SMOKE=FAIL: EFF polarity rows")
		quit(1)
		return
	var first_effect := buff_row.get_child(0) as Button
	var stack_counter := first_effect.get_node_or_null("EFFStackCount") as Label
	if stack_counter == null or stack_counter.text != "2" or not stack_counter.visible:
		push_error("ARENA_OPEN_SMOKE=FAIL: EFF stack badge not visible on icon")
		quit(1)
		return
	var fifth:=buff_row.get_child(4) as Button
	if fifth==null or not fifth.visible or fifth.text!="+2":
		push_error("ARENA_OPEN_SMOKE=FAIL: EFF +N overflow")
		quit(1)
		return
	var label:=arena.effect_detail_labels.get("player_Баффы") as Label
	if label==null or not label.text.contains("×2") or label.text.contains("вступит"):
		push_error("ARENA_OPEN_SMOKE=FAIL: EFF details, stacks or delayed start")
		quit(1)
		return
	print("ARENA_OPEN_SMOKE=PASS")
	quit(0)
