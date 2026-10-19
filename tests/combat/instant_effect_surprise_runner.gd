extends SceneTree

## Regression for manually timed instant ABI:
## mechanics immediately; hidden until end_round; cleanse next round only.
## Test BOTH sealed ordering variants, for BUFF and DEBUFF.
const HIDDEN_BUFF := "EFF_SURPRISE_GUARD"
const HIDDEN_DEBUFF := "EFF_SURPRISE_WEAKEN"
const OLD_BUFF := "EFF_SURPRISE_PREEXISTING"
const SHARED_BUFF := "EFF_SURPRISE_SHARED_BUFF"
const SHARED_DEBUFF := "EFF_SURPRISE_SHARED_DEBUFF"

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
	for kind in ["buff","debuff"]:
		for cast_first in [true,false]:
			var result: bool = _test_shared_surprise_cleanse(kind,cast_first)
			print("INSTANT_SURPRISE_SHARED_CLEANSE=",kind," cast_first=",cast_first," ", "PASS" if result else "FAIL")
			success = success and result
		var disclosure: bool = _test_shared_stack_disclosure(kind)
		print("INSTANT_SURPRISE_SHARED_DISCLOSURE=",kind," ", "PASS" if disclosure else "FAIL")
		success = success and disclosure
	var capped: bool = _test_shared_cap_refresh()
	print("INSTANT_SURPRISE_SHARED_CAP=", "PASS" if capped else "FAIL")
	success = success and capped
	print("INSTANT_EFFECT_SURPRISE_TEST=", "PASS" if success else "FAIL")
	quit(0 if success else 1)

func _session() -> ArenaCombatSession:
	var character := CharacterState.new("SURPRISE_PLAYER","Surprise Player",5)
	var session := ArenaCombatSession.new(character,ItemRepository.new())
	var definitions: Dictionary = {}
	definitions[HIDDEN_BUFF]={"kind":"buff","damage_reduction":0.25,"duration_rounds":2}
	definitions[HIDDEN_DEBUFF]={"kind":"debuff","damage_reduction":-0.10,"duration_rounds":2}
	definitions[SHARED_BUFF]={"kind":"buff","damage_reduction":0.10,"duration_rounds":3,"stacking":"shared_duration","max_stacks":3}
	definitions[SHARED_DEBUFF]={"kind":"debuff","damage_reduction":-0.10,"duration_rounds":3,"stacking":"shared_duration","max_stacks":3}
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
	var cleanser: String = ArenaCombatSession.ENEMY_ID
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

func _shared_setup(kind:String,stacks:int=1) -> ArenaCombatSession:
	var session:=_session()
	var target:=_target(session,kind)
	var id:String=SHARED_BUFF if kind=="buff" else SHARED_DEBUFF
	var definition:Dictionary=Dictionary(session.engine.physical_balance["effects"][id])
	target.active_effects.append({
		"effect_id":id,
		"definition":definition.duplicate(true),
		"source_id":session.player_id,
		"start_round":1,
		"remaining_rounds":2,
		"stacks":stacks,
		"active_stacks":stacks,
		"revealed":true,
		"dispel_available_round":1
	})
	return session

func _shared_cast(session:ArenaCombatSession,kind:String) -> CombatEvent:
	var id:String=SHARED_BUFF if kind=="buff" else SHARED_DEBUFF
	var definition:Dictionary={
		"application_timing":"instant",
		"target_team":"ALLY" if kind=="buff" else "ENEMY",
		"components":[{"kind":"effect","effect_id":id,"base_chance":100}]
	}
	return AbilityRuntime.build_action_event(session.state,session.player_id,_target(session,kind).combatant_id,"ABI_SHARED_SURPRISE",definition)

func _test_shared_surprise_cleanse(kind:String,cast_first:bool) -> bool:
	var session:=_shared_setup(kind)
	var target:=_target(session,kind)
	var round:=session.orchestrator.begin_round()
	var cast:=_shared_cast(session,kind)
	var cleanse:=_cleanse(session,kind)
	if cast_first:
		round.lock_action(cast)
		round.lock_action(cleanse)
	else:
		round.lock_action(cleanse)
		round.lock_action(cast)
	session.orchestrator.resolve_locked_actions(round)
	# Only the old known stack may be removed. A newly added instant stack
	# survives regardless of which instant ABI was locked first.
	if _removed(session.state,cleanse.event_id)!=1 or target.active_effects.size()!=1 or _view_count(session,kind)!=0:
		return false
	var active:Dictionary=target.active_effects[0]
	if int(active.get("stacks",-1))!=1 or int(active.get("active_stacks",-1))!=0 or bool(active.get("revealed",true)):
		return false
	if int(active.get("dispel_available_round",-1))!=2:
		return false
	session.orchestrator.end_round()
	var view:Dictionary=session.effect_view(kind=="buff")
	var key:String="buffs" if kind=="buff" else "debuffs"
	var entry:Array=Array(view.get(key,[]))
	if entry.size()!=1 or int(Dictionary(entry[0]).get("stacks",-1))!=1:
		return false
	var second:=session.orchestrator.begin_round()
	var next_cleanse:=_cleanse(session,kind)
	second.lock_action(next_cleanse)
	session.orchestrator.resolve_locked_actions(second)
	if _removed(session.state,next_cleanse.event_id)!=1 or not target.active_effects.is_empty():
		return false
	session.orchestrator.end_round()
	return true

func _test_shared_stack_disclosure(kind:String) -> bool:
	var session:=_shared_setup(kind)
	var target:=_target(session,kind)
	var round:=session.orchestrator.begin_round()
	round.lock_action(_shared_cast(session,kind))
	session.orchestrator.resolve_locked_actions(round)
	if target.active_effects.size()!=1:
		return false
	var record:Dictionary=target.active_effects[0]
	if int(record.get("stacks",-1))!=2 or int(record.get("undisclosed_stacks",-1))!=1 or int(record.get("active_stacks",-1))!=1:
		return false
	var view:Dictionary=session.effect_view(kind=="buff")
	var key:String="buffs" if kind=="buff" else "debuffs"
	var entries:Array=Array(view.get(key,[]))
	if entries.size()!=1 or int(Dictionary(entries[0]).get("stacks",-1))!=1 or int(Dictionary(entries[0]).get("remaining_rounds",-1))!=2:
		return false
	session.orchestrator.end_round()
	if record.has("undisclosed_stacks") or record.has("visible_remaining_rounds"):
		return false
	var disclosed:Dictionary=session.effect_view(kind=="buff")
	var final:Array=Array(disclosed.get(key,[]))
	return final.size()==1 and int(Dictionary(final[0]).get("stacks",-1))==2 and int(Dictionary(final[0]).get("remaining_rounds",-1))==3

func _test_shared_cap_refresh() -> bool:
	var session:=_shared_setup("buff",3)
	var target:=_target(session,"buff")
	var round:=session.orchestrator.begin_round()
	round.lock_action(_shared_cast(session,"buff"))
	session.orchestrator.resolve_locked_actions(round)
	var active:Dictionary=target.active_effects[0]
	if int(active.get("stacks",-1))!=3 or int(active.get("undisclosed_stacks",0))!=0:
		return false
	var visible:Array=Array(session.effect_view(true).get("buffs",[]))
	if visible.size()!=1 or int(Dictionary(visible[0]).get("stacks",-1))!=3 or int(Dictionary(visible[0]).get("remaining_rounds",-1))!=2:
		return false
	session.orchestrator.end_round()
	var revealed:Array=Array(session.effect_view(true).get("buffs",[]))
	return revealed.size()==1 and int(Dictionary(revealed[0]).get("stacks",-1))==3 and int(Dictionary(revealed[0]).get("remaining_rounds",-1))==3

func _removed(state:CombatState,parent_id:int) -> int:
	var total:int=0
	for event in state.event_log:
		if event.kind==CombatEvent.Kind.EFFECT and event.parent_event_id==parent_id:
			total+=int(event.result.get("removed_count",0))
	return total
