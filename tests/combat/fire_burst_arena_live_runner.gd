extends SceneTree

# Real item -> equipment -> arena -> immediate dual ABI lock -> sealed combat round.
func _initialize() -> void:
	var repo := ItemRepository.new()
	var hero := CharacterState.new("FIRE_ARENA_HERO","Fire Arena Hero",40)
	# The live equip check must use a character that meets the staff requirements.
	hero.progression.base_stats["PAR003"]=100
	hero.progression.base_stats["PAR004"]=100
	var staff := ItemV12InstanceFactory.generate_weapon("STAFF_FIRE_BURST",40,"blue",442,"2H")
	if staff.is_empty():
		_finish(false,"staff_empty")
		return
	if not repo.add_item(staff):
		_finish(false,"repo_add")
		return
	if not hero.receive_item(String(staff.get("instance_id","")),repo):
		_finish(false,"bag_receive")
		return
	if not hero.equip("main_hand",String(staff.get("instance_id","")),repo):
		_finish(false,"equip_failed_"+JSON.stringify(staff.get("requirements",{}))+" slots="+JSON.stringify(staff.get("equip_slots",[])))
		return
	var session := ArenaCombatSession.new(hero,repo)
	if Array(session.player_ability_slots).slice(0,4)!=["ABI801","ABI802","ABI803","ABI804"]:
		_finish(false,"four_real_weapon_slots")
		return
	var actor := session.fighter(true)
	actor.mana=500
	actor.max_mana=500
	var profiles: Array=actor.combat_stats.get("weapon_profiles",[])
	if profiles.is_empty() or String(Dictionary(profiles[0]).get("weapon_class",""))!="staff" or int(Dictionary(profiles[0]).get("item_level",0))!=40:
		_finish(false,"staff_level_in_combat")
		return
	var options:=session.player_ability_options()
	if options.size()<4 or not bool(Dictionary(options[0]).get("available",false)) or not bool(Dictionary(options[1]).get("available",false)):
		_finish(false,"four_abi_available")
		return
	var first:=session.activate_ability("ABI801")
	if not bool(first.get("ok",false)) or actor.mana!=465:
		_finish(false,"fireball_immediate_spend_"+str(actor.mana))
		return
	options=session.player_ability_options()
	if bool(Dictionary(options[2]).get("available",false)) or not bool(Dictionary(options[1]).get("available",false)) or int(Dictionary(options[1]).get("mana_cost",-1))!=38:
		_finish(false,"second_selection_ui_price")
		return
	var second:=session.activate_ability("ABI802")
	if not bool(second.get("ok",false)) or actor.mana!=427:
		_finish(false,"blast_immediate_spend_"+str(actor.mana))
		return
	var third:=session.activate_ability("ABI803")
	if bool(third.get("ok",true)) or actor.mana!=427:
		_finish(false,"third_abi_rejected")
		return
	var blocks:Array[String]=[]
	var block_count:=CombatModifierService.manual_block_zone_capacity(actor)
	for zone in ["head","chest","arms","waist"]:
		if blocks.size()<block_count:
			blocks.append(zone)
	var result:=session.play_round(["chest"],blocks)
	if not bool(result.get("ok",false)):
		_finish(false,"round_rejected_"+String(result.get("reason","")))
		return
	var casts:Array[String]=[]
	var direct_damage := 0
	var effect_count := 0
	for event in session.state.event_log:
		if int(event.payload.get("round",-1))!=1 or event.source_id!=session.player_id:
			continue
		if event.kind==CombatEvent.Kind.ACTION and String(event.payload.get("source_kind",""))=="ability":
			casts.append(String(event.payload.get("ability_id","")))
		if event.kind==CombatEvent.Kind.DAMAGE and String(event.payload.get("source",""))=="ability":
			direct_damage+=1
		if event.kind==CombatEvent.Kind.EFFECT and String(event.payload.get("effect_id",""))=="EFF003":
			effect_count+=1
	var ok := casts==["ABI801","ABI802"] and direct_damage==2 and effect_count>=1
	_finish(ok,"casts="+JSON.stringify(casts)+" direct="+str(direct_damage)+" effects="+str(effect_count))

func _finish(ok:bool,detail:String)->void:
	print("FIRE_BURST_ARENA_LIVE=",("PASS" if ok else "FAIL")," detail=",detail)
	quit(0 if ok else 1)
