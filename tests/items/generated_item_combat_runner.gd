extends SceneTree
func _init()->void:
	var file:=FileAccess.open("res://data/test/item_generator_template.json",FileAccess.READ); var template:Dictionary=JSON.parse_string(file.get_as_text())
	template["damage_type"]="slashing"; template["manual_block_zones_added"]=1
	var generator:=ItemGenerator.new(5050); var item:=generator.generate(template,"purple")
	var hero:=CombatantState.new("GEN_HERO","Generated Sword Hero",50,100,25); var enemy:=CombatantState.new("GEN_ENEMY","Training Enemy",50,100,25)
	EquipmentBuilder.equip(hero,item)
	var dummy:Dictionary={"damage":{"min":1,"max":1,"type":"slashing"},"manual_block_zones_added":1}; EquipmentBuilder.equip(enemy,dummy)
	var state:=CombatState.new(); state.add_combatant(hero); state.add_combatant(enemy)
	var simulator:=CombatSimulator.new(state,{},5050); simulator.max_rounds=100; var result:=simulator.run_duel(hero.combatant_id,enemy.combatant_id)
	var equipped_ok:=int(hero.combat_stats.get("main_hand_damage_min",0))==int(item.damage_min) and int(hero.combat_stats.get("main_hand_damage_max",0))==int(item.damage_max)
	var stats_ok:=hero.stats==item.final_stats
	var damage_events:=0
	for event in state.event_log:
		if event.kind==CombatEvent.Kind.DAMAGE and event.source_id==hero.combatant_id:damage_events+=1
	var ok:=equipped_ok and stats_ok and damage_events>0 and int(result.second_hp)<100
	print("GENERATED_ITEM_COMBAT_TEST=", "PASS" if ok else "FAIL")
	print(JSON.stringify({"item":item,"equipped_damage":[hero.combat_stats.get("main_hand_damage_min"),hero.combat_stats.get("main_hand_damage_max")],"equipped_stats":hero.stats,"hero_damage_events":damage_events,"combat_result":result}))
	quit(0 if ok else 1)
