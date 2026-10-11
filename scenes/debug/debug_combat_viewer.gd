extends Control

var state:CombatState
var groups:GroupCombatState
var zones:CombatZoneState
var engine:CombatEngine
var orchestrator:RoundOrchestrator
var api:CombatApi
var commands:CombatCommandApi
var hero_id:="player"
const PROGRESSION_SAVE_PATH := "user://character_progression_v1.json"
const INVENTORY_SAVE_PATH := "user://character_inventory_v1.json"

@onready var round_label:Label=$Margin/VBox/Header/Round
@onready var outcome_label:Label=$Margin/VBox/Header/Outcome
@onready var block_zone:OptionButton=$Margin/VBox/Defence/BlockZone
@onready var zone_labels:Array[Label]=[$Margin/VBox/Zones/Zone1,$Margin/VBox/Zones/Zone2,$Margin/VBox/Zones/Zone3]
@onready var hero_label:Label=$Margin/VBox/Status/Hero
@onready var enemy_label:Label=$Margin/VBox/Status/Enemy
@onready var actions:HBoxContainer=$Margin/VBox/Actions
@onready var log_label:RichTextLabel=$Margin/VBox/Log
@onready var target_select:OptionButton=$Margin/VBox/Targeting/TargetSelect

func _ready()->void:
	_build_debug_combat()
	$Margin/VBox/Header/Back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main/main.tscn"))
	$Margin/VBox/Header/Reset.pressed.connect(_reset_combat)
	$Margin/VBox/Defence/SetBlock.pressed.connect(_set_block)
	target_select.item_selected.connect(_on_target_selected)
	for body_zone in ["head","chest","arms","waist","legs"]:
		block_zone.add_item(body_zone)
	_refresh()

func _build_debug_combat()->void:
	state=CombatState.new()
	var debug_character := _load_player_character()
	var player: CharacterState = debug_character["character"]
	var repository: ItemRepository = debug_character["repository"]
	var calculated := CharacterStatsService.combat_stats(player, repository)
	var hero := CharacterCombatBuilder.build(player, repository)
	enemy.combat_stats["main_hand_damage"]=7.0
	enemy.combat_stats["main_hand_damage_type"]="blunt"
	state.add_combatant(hero); state.add_combatant(enemy); state.add_combatant(enemy_two)
	groups=GroupCombatState.new(state)
	groups.add_member("A",hero_id); groups.add_member("B","enemy"); groups.add_member("B","enemy_two")
	groups.set_active_opponent(hero_id,"enemy"); groups.set_active_opponent("enemy",hero_id)
	zones=CombatZoneState.new(groups)
	zones.set_team_flag("A",CombatZoneState.ZONE_1); zones.set_team_flag("B",CombatZoneState.ZONE_3)
	zones.set_zone(hero_id,CombatZoneState.ZONE_2); zones.set_zone("enemy",CombatZoneState.ZONE_2); zones.set_zone("enemy_two",CombatZoneState.ZONE_3)
	engine=CombatEngine.new(state)
	orchestrator=RoundOrchestrator.new(state,engine,groups,zones)
	api=CombatApi.new(state,groups,zones)
	commands=CombatCommandApi.new(state,groups,zones,orchestrator)
	orchestrator.begin_round()

func _refresh()->void:
	var snap:=api.snapshot()
	round_label.text="Round %d" % int(snap.get("round",0))
	var outcome:=orchestrator.battle_outcome()
	outcome_label.text="ONGOING" if outcome=="ongoing" else "RESULT: %s" % outcome
	for i in range(3):
		var ids:Array=snap.get("zones",{}).get(str(i+1),[])
		var cards:Array[String]=[]
		for id in ids:
			var unit:=api.combatant(String(id))
			var marker:=" [TARGET]" if String(unit.id)==groups.active_opponent(hero_id) else ""
			cards.append("%s%s\nHP %d/%d" % [unit.name,marker,unit.hp,unit.max_hp])
		zone_labels[i].text="ZONE %d\n\n%s" % [i+1,"\n\n".join(cards) if not cards.is_empty() else "—"]
	var hero:=api.combatant(hero_id); var enemy:=api.combatant("enemy")
	var block_zones:Array=state.get_combatant(hero_id).combat_stats.get("manual_block_zones",[])
	hero_label.text="HERO  HP %d/%d   Mana %d/%d   Zone %d   Block: %s" % [hero.hp,hero.max_hp,hero.mana,hero.max_mana,hero.zone_id,", ".join(block_zones) if not block_zones.is_empty() else "—"]
	enemy_label.text="ACTIVE TARGET  %s  HP %d/%d   Zone %d" % [enemy.name,enemy.hp,enemy.max_hp,enemy.zone_id]
	_rebuild_targets()
	_rebuild_actions()
	var lines:Array[String]=[]
	for e in api.recent_events(maxi(0,state.event_log.size()-8)):
		lines.append("#%d  %s → %s  %s" % [e.id,e.source_id,e.target_id,e.outcome])
	log_label.text="\n".join(lines) if not lines.is_empty() else "Combat log is empty."

func _rebuild_targets()->void:
	target_select.clear()
	var options:=api.target_options(hero_id)
	var target_ids:Array=[String(options.get("active",""))]
	target_ids.append_array(options.get("alternatives",[]))
	for target_id in target_ids:
		if target_id.is_empty(): continue
		var unit:=api.combatant(target_id)
		target_select.add_item("%s — Z%d — HP %d/%d" % [unit.name,unit.zone_id,unit.hp,unit.max_hp])
		target_select.set_item_metadata(target_select.item_count-1,target_id)
	if target_select.item_count>0:
		target_select.select(0)

func _rebuild_actions()->void:
	for child in actions.get_children(): child.queue_free()
	var available:=commands.available_actions(hero_id)
	var attack:=Button.new(); attack.text="Base Attack"; attack.disabled=not bool(available.get("basic_attack",false)); attack.pressed.connect(_attack); actions.add_child(attack)
	for zone_id in available.get("navigation",[]):
		var move:=Button.new(); move.text="Move → Z%d" % int(zone_id); move.pressed.connect(_move.bind(int(zone_id))); actions.add_child(move)
	var end_round:=Button.new(); end_round.text="End Round"; end_round.pressed.connect(_end_round); actions.add_child(end_round)

func _on_target_selected(index:int)->void:
	var target_id:=String(target_select.get_item_metadata(index))
	commands.select_active_opponent(hero_id,target_id)
	_refresh()

func _set_block()->void:
	if block_zone.item_count==0: return
	commands.set_manual_block(hero_id,[block_zone.get_item_text(block_zone.selected)])
	_refresh()

func _reset_combat()->void:
	_build_debug_combat()
	_refresh()

func _attack()->void:
	var result:=commands.queue_basic_attack(hero_id,{"hit":1,"crit":100})
	if bool(result.get("ok",false)): engine.resolve_pending_events()
	_refresh()

func _move(zone_id:int)->void:
	commands.request_navigation(hero_id,zone_id,1)
	_end_round()

func _end_round()->void:
	orchestrator.end_round()
	if orchestrator.battle_outcome()=="ongoing": orchestrator.begin_round()
	_refresh()

## The debug encounter consumes the saved player state without mutating it.
## If there is no save, use a fresh level-1 character with bare fists.
func _load_player_character() -> Dictionary:
	var player := CharacterState.new("player", "Герой")
	var repository := ItemRepository.new()
	if FileAccess.file_exists(PROGRESSION_SAVE_PATH):
		var progression_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROGRESSION_SAVE_PATH))
		if progression_data is Dictionary:
			player.restore_progression(progression_data)
	if FileAccess.file_exists(INVENTORY_SAVE_PATH):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(INVENTORY_SAVE_PATH))
		if saved is Dictionary and int(saved.get("schema_version", 0)) == 1:
			var repository_data: Variant = saved.get("repository", {})
			var inventory_data: Variant = saved.get("inventory", {})
			var equipment_data: Variant = saved.get("equipment", {})
			if repository_data is Dictionary and inventory_data is Dictionary and equipment_data is Dictionary:
				if String(inventory_data.get("owner_id", "")) == player.character_id:
					var loaded_repository := ItemRepository.from_dict(repository_data)
					var loaded_inventory := InventoryState.from_dict(inventory_data, loaded_repository)
					var valid := true
					for slot in player.equipment.slots:
						var instance_id: Variant = equipment_data.get(slot, null)
						if instance_id != null and (not instance_id is String or not loaded_inventory.owns(String(instance_id))):
							valid = false
							break
					if valid:
						repository = loaded_repository
						player.inventory = loaded_inventory
						for slot in player.equipment.slots:
							player.equipment.slots[slot] = equipment_data.get(slot, null)
	return {"character": player, "repository": repository}
