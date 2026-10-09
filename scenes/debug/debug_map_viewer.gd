extends Control

var playable_map:TacticalMapState
var player_hex:=Vector2i(-1,-1)
var target_hex:=Vector2i(-1,-1)
var planned_path:Array[Vector2i]=[]
var move_status:Label
var _moving:=false
var _stop_requested:=false
var _step_elapsed:=0.0
var _step_duration:=0.0
var _next_hex:=Vector2i(-1,-1)
var zoom_level:float=3.0
var _map_base_size:=Vector2.ZERO
var map_scroll:Control
var mini_map:Control

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
	map_scroll.clip_contents=true
	map_scroll.mouse_filter=Control.MOUSE_FILTER_PASS
	mini_map=DebugMiniMap.new()
	mini_map.custom_minimum_size=Vector2.ZERO
	mini_map.size=Vector2(155,155)
	mini_map.mouse_filter=Control.MOUSE_FILTER_IGNORE
	$Root/MapPanel.add_child(mini_map)
	mini_map.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	mini_map.anchor_left=1.0
	mini_map.anchor_top=1.0
	mini_map.anchor_right=1.0
	mini_map.anchor_bottom=1.0
	mini_map.offset_left=-167.0
	mini_map.offset_top=-167.0
	mini_map.offset_right=-12.0
	mini_map.offset_bottom=-12.0
	mini_map.size_flags_horizontal=Control.SIZE_SHRINK_END
	mini_map.size_flags_vertical=Control.SIZE_SHRINK_END
	var controls:=HBoxContainer.new()
	$Root/Sidebar.add_child(controls)
	$Root/Sidebar.move_child(controls,1)
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
	_set_fixed_scale()
	playable_map=generated.map
	player_hex=generated.entrance
	playable_map.place_entity("PLAYER",player_hex)
	_moving=false
	_stop_requested=false
	_next_hex=Vector2i(-1,-1)
	target_hex=Vector2i(-1,-1)
	planned_path.clear()
	canvas.set_player_view(player_hex,target_hex,planned_path)
	mini_map.update_map(playable_map,player_hex)
	call_deferred("_center_on_player")
	get_tree().process_frame.connect(_center_on_player,CONNECT_ONE_SHOT)
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
	# Portrait: a square camera viewport, with UI below it rather than a full-height map.
	if portrait:
		map_panel.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
		map_panel.custom_minimum_size.y=maxf(200.0,minf(size.x-32.0,size.y*0.60))
	else:
		map_panel.size_flags_vertical=Control.SIZE_EXPAND_FILL
	$Root/Sidebar/LegendTitle.visible=not portrait
	$Root/Sidebar/Legend.visible=not portrait
	$Root/Sidebar/Hint.visible=not portrait
	$Root/Sidebar/SummaryTitle.visible=not portrait
	$Root/Sidebar/Summary.visible=not portrait
	call_deferred("_center_on_player")
	call_deferred("_position_minimap")

func _position_minimap()->void:
	if mini_map==null:
		return
	var rect:Rect2=$Root/MapPanel.get_global_rect()
	mini_map.position=rect.position-global_position+rect.size-Vector2(167,167)
	mini_map.size=Vector2(155,155)

func _visible_cells()->Dictionary:
	var result:Dictionary={}
	for pos in playable_map.cells.keys():
		if canvas._is_visible_hex(pos): result[pos]=true
	return result

func _route_to(destination:Vector2i)->Array[Vector2i]:
	return SafeMapNavigation.find_route(playable_map,canvas.explored_hexes,player_hex,destination,_visible_cells(),canvas._entity_roles)

func _select_destination(pos:Vector2i)->void:
	if playable_map==null: return
	if pos==player_hex:
		if _moving:
			_stop_requested=true
			move_status.text="Остановка после перехода"
		return
	if not canvas.explored_hexes.has(pos): return
	if _moving:
		_stop_requested=true
		move_status.text="Ожидание остановки"
		return
	if pos==target_hex and planned_path.size()>1:
		_moving=true
		_stop_requested=false
		_prepare_step()
		return
	target_hex=pos
	planned_path=_route_to(target_hex)
	if planned_path.size()>1:
		var seconds:=0.0
		for i in range(1,planned_path.size()):
			seconds+=SafeMapNavigation.terrain_seconds(playable_map.cell(planned_path[i]).terrain_id)
		move_status.text="Путь: %d гексов, %.0f сек. Нажмите ещё раз"%[planned_path.size()-1,seconds]
	else:
		move_status.text="Безопасный путь недоступен"
	canvas.set_player_view(player_hex,target_hex,planned_path)

func _prepare_step()->void:
	if _stop_requested or planned_path.size()<2:
		_moving=false
		_stop_requested=false
		_next_hex=Vector2i(-1,-1)
		move_status.text="Остановлено" if planned_path.size()>1 else "Прибытие"
		return
	var next:Vector2i=planned_path[1]
	if not playable_map.cell(next).is_passable() or (canvas._is_visible_hex(next) and SafeMapNavigation.static_npc_at(playable_map,canvas._entity_roles,next)):
		planned_path=_route_to(target_hex)
		canvas.set_player_view(player_hex,target_hex,planned_path)
		if planned_path.size()<2:
			_moving=false
			move_status.text="Препятствие: остановка"
			return
		next=planned_path[1]
	_next_hex=next
	_step_elapsed=0.0
	_step_duration=SafeMapNavigation.terrain_seconds(playable_map.cell(next).terrain_id)
	move_status.text="Движение: %.0f сек/гекс"%_step_duration

func _process(delta:float)->void:
	if not _moving or _next_hex.x<0: return
	_step_elapsed+=delta
	if _step_elapsed<_step_duration: return
	if not playable_map.entities_at(_next_hex).is_empty():
		_moving=false
		move_status.text="Столкновение: движение остановлено"
		return
	var result:Dictionary=playable_map.move_entity("PLAYER",_next_hex)
	if not bool(result.get("ok",false)):
		_moving=false
		move_status.text="Движение: "+str(result.get("reason","ошибка"))
		return
	player_hex=_next_hex
	planned_path.remove_at(0)
	canvas.set_player_view(player_hex,target_hex,planned_path)
	mini_map.update_map(playable_map,player_hex)
	_center_on_player()
	_prepare_step()

func _set_fixed_scale()->void:
	if canvas==null:
		return
	canvas.HEX_SIZE=60.0
	_map_base_size=canvas._map_pixel_size()
	canvas.custom_minimum_size=_map_base_size
	canvas.size=_map_base_size
	call_deferred("_center_on_player")
	canvas.queue_redraw()

func _center_on_player()->void:
	if canvas==null or map_scroll==null or player_hex.x<0:
		return
	var player_center:=canvas._hex_center(player_hex)
	var viewport_size:=map_scroll.size
	var desired:=viewport_size*0.5-player_center
	# Clamp camera to the real map edges. At a border the player moves off-center,
	# rather than allowing empty space beyond the map.
	var first:=canvas._hex_center(Vector2i(0,0))
	var last:=canvas._hex_center(Vector2i(playable_map.width-1,playable_map.height-1))
	var left_edge:=first.x-canvas.HEX_SIZE*0.8660254
	var right_edge:=last.x+canvas.HEX_SIZE*0.8660254
	var top_edge:=first.y-canvas.HEX_SIZE
	var bottom_edge:=last.y+canvas.HEX_SIZE
	var min_x:=viewport_size.x-right_edge
	var max_x:=-left_edge
	var min_y:=viewport_size.y-bottom_edge
	var max_y:=-top_edge
	if min_x>max_x:
		desired.x=(min_x+max_x)*0.5
	else:
		desired.x=clampf(desired.x,min_x,max_x)
	if min_y>max_y:
		desired.y=(min_y+max_y)*0.5
	else:
		desired.y=clampf(desired.y,min_y,max_y)
	canvas.position=desired.round()
	canvas.queue_redraw()
