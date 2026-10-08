extends Control

var loot_expedition:ExpeditionState
var loot_player_id:String=""
var loot_character:CharacterState
var loot_repository:ItemRepository
var _loot_dialog:AcceptDialog
var _loot_list:VBoxContainer
var _selected_loot_cell:Vector2i
var _loot_refresh_timer:Timer

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

func set_loot_claim_context(expedition:ExpeditionState,character:CharacterState,repository:ItemRepository)->void:
	loot_character=character
	loot_repository=repository
	set_loot_context(expedition,character.character_id if character!=null else "")

func _on_loot_hex_selected(cell:Vector2i)->void:
	if loot_expedition==null or loot_character==null or loot_repository==null:
		return
	_selected_loot_cell=cell
	_rebuild_loot_dialog()
	if _loot_list.get_child_count()>0:
		_loot_dialog.popup_centered(Vector2i(340,300))

func _rebuild_loot_dialog()->void:
	for child in _loot_list.get_children():
		_loot_list.remove_child(child)
		child.queue_free()
	if loot_expedition==null or loot_character==null:
		return
	var now_unix:=int(Time.get_unix_time_from_system())
	for encounter_id in loot_expedition.loot_pools_for_player_at_hex(loot_character.character_id,_selected_loot_cell,now_unix):
		var pool:=loot_expedition.restore_loot_pool(encounter_id)
		for item_id in pool.available_for(loot_character.character_id):
			var button:=Button.new()
			button.text="Забрать: "+item_id
			button.pressed.connect(_claim_selected.bind(item_id))
			_loot_list.add_child(button)
	if _loot_list.get_child_count()>0:
		var all_button:=Button.new()
		all_button.text="Забрать всё"
		all_button.pressed.connect(_claim_all)
		_loot_list.add_child(all_button)

func _claim_selected(item_id:String)->void:
	if loot_expedition!=null:
		loot_expedition.claim_loot_at_hex(loot_character,_selected_loot_cell,item_id,loot_repository,int(Time.get_unix_time_from_system()))
	_update_loot_dialog()

func _claim_all()->void:
	if loot_expedition!=null:
		loot_expedition.claim_all_loot_at_hex(loot_character,_selected_loot_cell,loot_repository,int(Time.get_unix_time_from_system()))
	_update_loot_dialog()

func _update_loot_dialog()->void:
	refresh_loot_markers()
	_rebuild_loot_dialog()
	if _loot_list.get_child_count()==0:
		_loot_dialog.hide()

func _on_loot_refresh()->void:
	refresh_loot_markers()
	if _loot_dialog.visible:
		_update_loot_dialog()

@onready var seed_input:SpinBox=$Root/Sidebar/SeedRow/Seed
@onready var canvas:DebugMapCanvas=$Root/MapPanel/Scroll/Canvas
@onready var summary:Label=$Root/Sidebar/Summary

func _ready()->void:
	_loot_dialog=AcceptDialog.new()
	_loot_dialog.title="Добыча"
	add_child(_loot_dialog)
	_loot_list=VBoxContainer.new()
	_loot_dialog.add_child(_loot_list)
	canvas.loot_hex_selected.connect(_on_loot_hex_selected)
	_loot_refresh_timer=Timer.new()
	_loot_refresh_timer.wait_time=1.0
	_loot_refresh_timer.timeout.connect(_on_loot_refresh)
	add_child(_loot_refresh_timer)
	_loot_refresh_timer.start()
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
