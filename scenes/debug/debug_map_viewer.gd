extends Control

var playable_map:TacticalMapState
var player_hex:=Vector2i(-1,-1)
var target_hex:=Vector2i(-1,-1)
var planned_path:Array[Vector2i]=[]
var move_status:Label
var move_button:Button
var zoom_level:float=1.8
var _map_base_size:=Vector2.ZERO
const MIN_ZOOM:=0.8
const MAX_ZOOM:=3.0
const ZOOM_STEP:=0.25
var map_scroll:ScrollContainer
var zoom_label:Label

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
	get_viewport().size_changed.connect(_adapt_layout)
	call_deferred("_adapt_layout")
	var back_button:=Button.new()
	back_button.text="← Поселение"
	back_button.custom_minimum_size.y=44
	back_button.pressed.connect(func()->void: get_tree().change_scene_to_file("res://scenes/main/main.tscn"))
	$Root/Sidebar.add_child(back_button)
	$Root/Sidebar.move_child(back_button,0)
	_loot_dialog=AcceptDialog.new()
	_loot_dialog.title="Добыча"
	add_child(_loot_dialog)
	_loot_list=VBoxContainer.new()
	_loot_dialog.add_child(_loot_list)
	canvas.loot_hex_selected.connect(_on_loot_hex_selected)
	canvas.hex_selected.connect(_select_destination)
	map_scroll=$Root/MapPanel/Scroll
	map_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_SHOW_NEVER
	map_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_SHOW_NEVER
	map_scroll.follow_focus=false
	var camera_controls:=HBoxContainer.new()
	$Root/Sidebar.add_child(camera_controls)
	$Root/Sidebar.move_child(camera_controls,1)
	for caption in ["−","+","Центр"]:
		var control:=Button.new()
		control.text=caption
		control.custom_minimum_size=Vector2(75,46)
		camera_controls.add_child(control)
		if caption=="−":
			control.pressed.connect(func()->void: _set_zoom(zoom_level-ZOOM_STEP))
		elif caption=="+":
			control.pressed.connect(func()->void: _set_zoom(zoom_level+ZOOM_STEP))
		else:
			control.pressed.connect(_center_on_player)
	zoom_label=Label.new()
	camera_controls.add_child(zoom_label)
	var controls:=HBoxContainer.new()
	$Root/Sidebar.add_child(controls)
	$Root/Sidebar.move_child(controls,1)
	move_button=Button.new()
	move_button.text="Шаг →"
	move_button.custom_minimum_size=Vector2(110,48)
	move_button.pressed.connect(_move_one_step)
	controls.add_child(move_button)
	move_status=Label.new()
	move_status.text="Коснитесь гексагона"
	move_status.clip_text=true
	move_status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	controls.add_child(move_status)
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
	_set_zoom(zoom_level)
	call_deferred("_center_on_player")
	playable_map=generated.map
	player_hex=generated.entrance
	playable_map.place_entity("PLAYER",player_hex)
	target_hex=Vector2i(-1,-1)
	planned_path.clear()
	canvas.set_player_view(player_hex,target_hex,planned_path)
	if move_status!=null:
		move_status.text="Выберите клетку"
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

func _adapt_layout()->void:
	var portrait:=size.y>size.x
	var root_grid:GridContainer=$Root
	root_grid.columns=1 if portrait else 2
	var sidebar:VBoxContainer=$Root/Sidebar
	sidebar.custom_minimum_size.x=0.0 if portrait else 270.0
	var map_panel:PanelContainer=$Root/MapPanel
	map_panel.custom_minimum_size.y=0.0
	map_panel.size_flags_vertical=Control.SIZE_EXPAND_FILL
	$Root/Sidebar/LegendTitle.visible=not portrait
	$Root/Sidebar/Legend.visible=not portrait
	$Root/Sidebar/Hint.visible=not portrait
	$Root/Sidebar/SummaryTitle.visible=not portrait
	$Root/Sidebar/Summary.visible=not portrait
	call_deferred("_refresh_map_extent")

func _select_destination(pos:Vector2i)->void:
	if playable_map==null:
		return
	target_hex=pos
	var result:=HexPathfinder.new().find_path(playable_map,player_hex,target_hex)
	planned_path.clear()
	if bool(result.get("ok",false)):
		for step in result.get("path",[]):
			planned_path.append(step)
		move_status.text="Путь: %d шагов"%(planned_path.size()-1)
	else:
		move_status.text="Недоступно: "+str(result.get("reason",""))
	canvas.set_player_view(player_hex,target_hex,planned_path)

func _move_one_step()->void:
	if playable_map==null or planned_path.size()<2:
		return
	var next:Vector2i=planned_path[1]
	if not playable_map.entities_at(next).is_empty():
		move_status.text="Клетка занята NPC"
		return
	var result:=playable_map.move_entity("PLAYER",next)
	if not bool(result.get("ok",false)):
		move_status.text="Движение: "+str(result.get("reason",""))
		return
	player_hex=next
	planned_path.remove_at(0)
	move_status.text="Прибытие" if planned_path.size()==1 else "Осталось: %d"%(planned_path.size()-1)
	canvas.set_player_view(player_hex,target_hex,planned_path)

func _set_zoom(value:float)->void:
	var next_zoom:=clampf(value,MIN_ZOOM,MAX_ZOOM)
	if canvas==null:
		return
	var old_zoom:=zoom_level
	var old_center:=Vector2(map_scroll.scroll_horizontal,map_scroll.scroll_vertical)+map_scroll.size*0.5-canvas.map_offset
	zoom_level=next_zoom
	canvas.HEX_SIZE=20.0*zoom_level
	_map_base_size=canvas._map_pixel_size()
	_refresh_map_extent()
	canvas.queue_redraw()
	if zoom_label!=null:
		zoom_label.text="%d%%"%roundi(zoom_level*100.0)
	var new_center:=old_center*zoom_level/maxf(old_zoom,0.01)+canvas.map_offset
	call_deferred("_scroll_to",new_center-map_scroll.size*0.5)

func _refresh_map_extent()->void:
	if canvas==null or map_scroll==null:
		return
	var viewport_size:=map_scroll.size
	if viewport_size.x<=0.0 or viewport_size.y<=0.0:
		return
	canvas.custom_minimum_size=Vector2(maxf(_map_base_size.x,viewport_size.x),maxf(_map_base_size.y,viewport_size.y))
	canvas.map_offset=Vector2(maxf(0.0,(viewport_size.x-_map_base_size.x)*0.5),maxf(0.0,(viewport_size.y-_map_base_size.y)*0.5))
	canvas.queue_redraw()

func _scroll_to(pos:Vector2)->void:
	map_scroll.scroll_horizontal=maxi(0,roundi(pos.x))
	map_scroll.scroll_vertical=maxi(0,roundi(pos.y))

func _center_on_player()->void:
	if canvas==null or map_scroll==null or player_hex.x<0:
		return
	_refresh_map_extent()
	var center:=canvas._hex_center(player_hex)
	_scroll_to(center-map_scroll.size*0.5)
