extends Control

var loot_expedition:ExpeditionState
var loot_player_id:String=""

func set_loot_context(expedition:ExpeditionState,player_id:String)->void:
	loot_expedition=expedition
	loot_player_id=player_id
	refresh_loot_markers()

func refresh_loot_markers()->void:
	if canvas==null:
		return
	if loot_expedition==null:
		canvas.set_loot_markers([])
	else:
		canvas.set_loot_markers(loot_expedition.loot_hexes_for_player(loot_player_id,int(Time.get_unix_time_from_system())))

@onready var seed_input:SpinBox=$Root/Sidebar/SeedRow/Seed
@onready var canvas:DebugMapCanvas=$Root/MapPanel/Scroll/Canvas
@onready var summary:Label=$Root/Sidebar/Summary

func _ready()->void:
	$Root/Sidebar/SeedRow/Regenerate.pressed.connect(_regenerate)
	_regenerate()

func _regenerate()->void:
	var seed_value:int=int(seed_input.value)
	var generated:=LocationGenerator.generate(20,20,seed_value)
	canvas.set_generated(generated)
	refresh_loot_markers()
	var map:TacticalMapState=generated.map
	var blocked:=0
	for pos in map.cells.keys():
		if not map.cell(pos).is_passable():
			blocked+=1
	var boss_count:int=generated.boss_groups.size()
	var boss_guard_count:=0
	for group in generated.boss_groups:
		boss_guard_count+=group.guard_ids.size()
	summary.text="Map: %dx%d\nBlocked: %d\nResources: %d\nObjects: %d\nNPC: %d\nEncounters: %d\nObject Guards: %d\nRoute Guards: %d\nPatrols: %d\nBosses: %d\nBoss Guards: %d"%[
		map.width,map.height,blocked,
		generated.resource_cells.size(),generated.object_cells.size(),generated.npc_cells.size(),
		generated.encounter_cells.size(),generated.guarded_objects.size(),generated.route_guards.size(),
		generated.patrols.size(),boss_count,boss_guard_count
	]
