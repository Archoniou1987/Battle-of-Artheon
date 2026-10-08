extends Control

var state:CombatState
var groups:GroupCombatState
var zones:CombatZoneState
var engine:CombatEngine
var orchestrator:RoundOrchestrator
var api:CombatApi
var commands:CombatCommandApi
var hero_id:="hero"

@onready var round_label:Label=$Margin/VBox/Header/Round
@onready var zone_labels:Array[Label]=[$Margin/VBox/Zones/Zone1,$Margin/VBox/Zones/Zone2,$Margin/VBox/Zones/Zone3]
@onready var hero_label:Label=$Margin/VBox/Status/Hero
@onready var enemy_label:Label=$Margin/VBox/Status/Enemy
@onready var actions:HBoxContainer=$Margin/VBox/Actions
@onready var log_label:RichTextLabel=$Margin/VBox/Log

func _ready()->void:
	_build_debug_combat()
	$Margin/VBox/Header/Back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main/main.tscn"))
	_refresh()

func _build_debug_combat()->void:
	state=CombatState.new()
	var hero:=CombatantState.new(hero_id,"Hero",1,100,30)
	var enemy:=CombatantState.new("enemy","Training Raider",1,80,0)
	hero.combat_stats["main_hand_damage"]=12.0
	hero.combat_stats["main_hand_damage_type"]="slashing"
	enemy.combat_stats["main_hand_damage"]=7.0
	enemy.combat_stats["main_hand_damage_type"]="blunt"
	state.add_combatant(hero); state.add_combatant(enemy)
	groups=GroupCombatState.new(state)
	groups.add_member("A",hero_id); groups.add_member("B","enemy")
	groups.set_active_opponent(hero_id,"enemy"); groups.set_active_opponent("enemy",hero_id)
	zones=CombatZoneState.new(groups)
	zones.set_team_flag("A",CombatZoneState.ZONE_1); zones.set_team_flag("B",CombatZoneState.ZONE_3)
	zones.set_zone(hero_id,CombatZoneState.ZONE_2); zones.set_zone("enemy",CombatZoneState.ZONE_2)
	engine=CombatEngine.new(state)
	orchestrator=RoundOrchestrator.new(state,engine,groups,zones)
	api=CombatApi.new(state,groups,zones)
	commands=CombatCommandApi.new(state,groups,zones,orchestrator)
	orchestrator.begin_round()

func _refresh()->void:
	var snap:=api.snapshot()
	round_label.text="Round %d" % int(snap.get("round",0))
	for i in range(3):
		var ids:Array=snap.get("zones",{}).get(str(i+1),[])
		zone_labels[i].text="ZONE %d\n%s" % [i+1,", ".join(ids) if not ids.is_empty() else "—"]
	var hero:=api.combatant(hero_id); var enemy:=api.combatant("enemy")
	hero_label.text="HERO  HP %d/%d   Mana %d/%d   Zone %d" % [hero.hp,hero.max_hp,hero.mana,hero.max_mana,hero.zone_id]
	enemy_label.text="ENEMY  HP %d/%d   Zone %d" % [enemy.hp,enemy.max_hp,enemy.zone_id]
	_rebuild_actions()
	var lines:Array[String]=[]
	for e in api.recent_events(maxi(0,state.event_log.size()-8)):
		lines.append("#%d  %s → %s  %s" % [e.id,e.source_id,e.target_id,e.outcome])
	log_label.text="\n".join(lines) if not lines.is_empty() else "Combat log is empty."

func _rebuild_actions()->void:
	for child in actions.get_children(): child.queue_free()
	var available:=commands.available_actions(hero_id)
	var attack:=Button.new(); attack.text="Base Attack"; attack.disabled=not bool(available.get("basic_attack",false)); attack.pressed.connect(_attack); actions.add_child(attack)
	for zone_id in available.get("navigation",[]):
		var move:=Button.new(); move.text="Move → Z%d" % int(zone_id); move.pressed.connect(_move.bind(int(zone_id))); actions.add_child(move)
	var end_round:=Button.new(); end_round.text="End Round"; end_round.pressed.connect(_end_round); actions.add_child(end_round)

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
