extends SceneTree

## Regression for manually timed instant ABI:
## mechanics immediately; hidden until end_round; cleanse next round only.
## Test BOTH sealed ordering variants, for BUFF and DEBUFF.
const HIDDEN_BUFF := "EFF_SURPRISE_GUARD"
const HIDDEN_DEBUFF := "EFF_SURPRISE_WEAKEN"
const OLD_BUFF := "EFF_SURPRISE_PREEXISTING"

func _init() -> void:
	var success: bool = true
	for kind in ["buff","debuff"]:
		for cast_first in [true,false]:
			var result: bool = _test_one_round_surprise(kind,cast_first)
			print("INSTANT_SURPRISE_CASE=",kind,"_cast_first_",cast_first," ", "PASS" if result else "FAIL")
			success = success and result
	for cast_first in [true,false]:
		var result: bool = _test_existing_visible_effect(cast_first)
		print("INSTANT_SURPRISE_OLD_VISIBLE=",cast_first," ", "PASS" if result else "FAIL")
		success = success and result
	print("INSTANT_EFFECT_SURPRISE_TEST=", "PASS" if success else "FAIL")
	quit(0 if success else 1)

func _session() -> ArenaCombatSession:
	var character := CharacterState.new("SURPRISE_PLAYER","Surprise Player",5)
	var session := ArenaCombatSession.new(character,ItemRepository.new())
	var definitions: Dictionary = {}
	definitions[HIDDEN_BUFF]={"kind":"buff","damage_reduction":0.25,"duration_rounds":2}
	definitions[HIDDEN_DEBUFF]={"kind":"debuff","damage_reduction":-0.10,"duration_rounds":2}
	session.engine.physical_balance["effects"]=definitions
	return session

func _cast(session:ArenaCombatSession,kind:String) -> CombatEvent:
	var is_buff: bool = kind=="buff"
	var effect_id: String = HIDDEN_BUFF if is_buff else HIDDEN_DEBUFF
	var caster_id: String = session.player_id
	var target_id: String = session.player_id if is_buff else ArenaCombatSession.ENEMY_ID
	var definition:Dictionary={
		"application_timing":"instant",
		"target_team":"ALLY" if is_buff else "ENEMY",
		"components":[{"kind":"effect","effect_id":effect_id,"base_chance":100}]
	}
	return AbilityRuntime.build_action_event(session.state,caster_id,target_id,"ABI_SURPRISE_CAST",definition)

func _cleanse(session:ArenaCombatSession,kind:String) -> CombatEvent:
	var is_buff: bool = kind=="buff"
	var cleanser: String = ArenaCombatSession.ENEMY_ID if is_buff else ArenaCombatSession.ENEMY_ID
	var target_id: String = session.player_id if is_buff else ArenaCombatSession.ENEMY_ID
	var definition:Dictionary={
		"application_timing":"instant",
		"target_team":"ENEMY" if is_buff else "ALLY",
		"components":[{"kind":"cleanse","dispel_polarity":"BUFF" if is_buff else "DEBUFF","max_effects":3}]
	}
	return AbilityRuntime.build_action_event(session.state,cleanser,target_id,"ABI_SURPRISE_CLEANSE",definition)

func _target(session:ArenaCombatSession,kind:String) -> CombatantState:
	return session.fighter(kind=="buff")

func _view_count(session:ArenaCombatSession,kind:String) -> int:
	var view:Dictionary=session.effect_view(kind=="buff")
	var key:String="buffs" if kind=="buff" else "debuffs"
	return Array(view.get(key,[])).size()

func _test_one_round_surprise(kind:String,cast_first:bool) -> bool:
	var session:=_session()
	var state:CombatState=session.state
	var target:CombatantState=_target(session,kind)
	var round:=session.orchestrator.begin_round()
	var baseline:float=CombatModifierService.damage_reduction(target,state.round_number)
	var cast:=_cast(session,kind)
	var cleanse:=_cleanse(session,kind)
	if cast_first:
		round.lock_action(cast)
		round.lock_action(cleanse)
	else:
		round.lock_action(cleanse)
		round.lock_action(cast)
	session.orchestrator.resolve_locked_actions(round)
	var delta:float=0.25 if kind=="buff" else -0.10
	if not is_equal_approx(CombatModifierService.damage_reduction(target,state.round_number),clampf(baseline+delta,0.0,1.0)):
		print("SURPRISE_NOT_ACTIVE_NOW=",kind)
		return false
	if target.active_effects.size()!=1 or _view_count(session,kind)!=0:
		print("SURPRISE_VISIBLE_EARLY=",kind," count=",target.active_effects.size())
		return false
	var active:Dictionary=target.active_effects[0]
	if bool(active.get("revealed",true)) or int(active.get("dispel_available_round",-1))!=2 or int(active.get("start_round",-1))!=1:
		print("SURPRISE_BAD_HIDDEN_METADATA=",active)
		return false
	if _removed(state,cleanse.event_id)!=0:
		print("SURPRISE_CLEANSED_IN_SAME_ROUND=",kind)
		return false
	session.orchestrator.end_round()
	if _view_count(session,kind)!=1 or not bool(target.active_effects[0].get("revealed",false)):
		print("SURPRISE_NOT_REVEALED_AT_ROUND_END=",kind)
		return false
	# A next-round cleanse can now remove the revealed effect.
	var round_two:=session.orchestrator.begin_round()
	var later_cleanse:=_cleanse(session,kind)
	round_two.lock_action(later_cleanse)
	session.orchestrator.resolve_locked_actions(round_two)
	if _removed(state,later_cleanse.event_id)!=1 or not target.active_effects.is_empty():
		print("SURPRISE_NOT_DISPELLED_NEXT_ROUND=",kind)
		return false
	session.orchestrator.end_round()
	return true

func _test_existing_visible_effect(cast_first:bool) -> bool:
	var session:=_session()
	var player:CombatantState=session.fighter(true)
	# Prior-round, already-known positive effect remains a valid cleanse
	# target even if a NEW surprise buff appears this round.
	player.active_effects.append({
		"effect_id":OLD_BUFF,
		"definition":{"kind":"buff","damage_reduction":0.05,"duration_rounds":3},
		"source_id":player.combatant_id,
		"start_round":1,
		"remaining_rounds":3,
		"stacks":1
	})
	var round:=session.orchestrator.begin_round()
	var new_buff:=_cast(session,"buff")
	var enemy_cleanse:=_cleanse(session,"buff")
	if cast_first:
		round.lock_action(new_buff)
		round.lock_action(enemy_cleanse)
	else:
		round.lock_action(enemy_cleanse)
		round.lock_action(new_buff)
	session.orchestrator.resolve_locked_actions(round)
	if _removed(session.state,enemy_cleanse.event_id)!=1:
		return false
	if player.active_effects.size()!=1 or String(player.active_effects[0].get("effect_id",""))!=HIDDEN_BUFF:
		return false
	if _view_count(session,"buff")!=0:
		return false
	session.orchestrator.end_round()
	return _view_count(session,"buff")==1

func _removed(state:CombatState,parent_id:int) -> int:
	var total:int=0
	for event in state.event_log:
		if event.kind==CombatEvent.Kind.EFFECT and event.parent_event_id==parent_id:
			total+=int(event.result.get("removed_count",0))
	return total
