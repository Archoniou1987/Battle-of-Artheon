extends Control

var playable_map:TacticalMapState
var player_hex:=Vector2i(-1,-1)
var target_hex:=Vector2i(-1,-1)
var planned_path:Array[Vector2i]=[]
var move_status:Label
var movement_panel:PanelContainer
var movement_info:Label
var movement_progress:ProgressBar
var stop_button:Button
var game_nav:GridContainer
var reveal_map_toggle:CheckButton
var random_seed_button:Button
var _camera_ready:=false
var _moving:=false
var _stop_requested:=false
var _step_elapsed:=0.0
var _step_duration:=0.0
var _next_hex:=Vector2i(-1,-1)
var zoom_level:float=3.0
var _map_base_size:=Vector2.ZERO
var map_scroll:Control
var mini_map:Control
var patrol_runtime:=MapPatrolRuntime.new()
var battle_dialog:AcceptDialog
var battle_entity_id:String=""
var battle_group_ids:Array[String]=[]
var battle_group_state:GroupCombatState
var battle_combat_state:CombatState
var battle_active:=false
var battle_defeat_button:Button
var chase_entity_id:String=""

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
	$Root.resized.connect(_adapt_layout)
	canvas.visible=false
	call_deferred("_adapt_layout")
	var back_button:=Button.new()
	back_button.text="← Поселение"
	back_button.custom_minimum_size.y=44
	back_button.pressed.connect(func()->void: get_tree().change_scene_to_file("res://scenes/main/main.tscn"))
	$Root/Sidebar.add_child(back_button)
	$Root/Sidebar.move_child(back_button,0)
	battle_dialog=AcceptDialog.new()
	battle_dialog.title="Начался бой!"
	battle_dialog.dialog_text="Начался бой!"
	battle_dialog.ok_button_text="Закрыть"
	battle_defeat_button=battle_dialog.add_button("Поражение",true,"defeat")
	battle_dialog.custom_action.connect(_on_battle_custom_action)
	battle_dialog.confirmed.connect(_finish_test_battle)
	battle_dialog.close_requested.connect(_finish_test_battle)
	add_child(battle_dialog)
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
	mini_map.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var controls:=HBoxContainer.new()
	$Root/Sidebar.add_child(controls)
	$Root/Sidebar.move_child(controls,1)
	move_status=Label.new()
	move_status.text="Коснитесь гексагона"
	move_status.clip_text=true
	move_status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	controls.add_child(move_status)
	reveal_map_toggle=CheckButton.new()
	reveal_map_toggle.text="Открыть всю карту (тест)"
	reveal_map_toggle.button_pressed=true
	reveal_map_toggle.toggled.connect(func(enabled:bool)->void:
		canvas.set_debug_reveal_all(enabled)
		mini_map.set_reveal_all(enabled)
	)
	$Root/Sidebar.add_child(reveal_map_toggle)
	$Root/Sidebar.move_child(reveal_map_toggle,2)
	canvas.set_debug_reveal_all(true)
	_build_movement_panel()
	_build_game_navigation()
	_loot_refresh_timer=Timer.new()
	_loot_refresh_timer.wait_time=1.0
	_loot_refresh_timer.timeout.connect(_on_loot_refresh)
	add_child(_loot_refresh_timer)
	_loot_refresh_timer.start()
	$Root/Sidebar/SeedRow/Regenerate.pressed.connect(_regenerate)
	seed_input.custom_minimum_size=Vector2(115,54)
	seed_input.add_theme_font_size_override("font_size",21)
	var regenerate_button:Button=$Root/Sidebar/SeedRow/Regenerate
	regenerate_button.text="Создать"
	regenerate_button.custom_minimum_size=Vector2(110,54)
	regenerate_button.add_theme_font_size_override("font_size",19)
	random_seed_button=Button.new()
	random_seed_button.text="Случайная"
	random_seed_button.custom_minimum_size=Vector2(130,54)
	random_seed_button.add_theme_font_size_override("font_size",18)
	random_seed_button.pressed.connect(_random_seed)
	$Root/Sidebar.add_child(random_seed_button)
	$Root/Sidebar.move_child(random_seed_button,2)
	_regenerate()

func _random_seed()->void:
	var rng:=RandomNumberGenerator.new()
	rng.randomize()
	seed_input.value=rng.randi_range(1,999999)
	_regenerate()

func _regenerate()->void:
	var seed_value:int=int(seed_input.value)
	var generated:=LocationGenerator.generate(20,20,seed_value)
	canvas.set_generated(generated)
	canvas.set_debug_reveal_all(reveal_map_toggle.button_pressed if reveal_map_toggle!=null else true)
	_set_fixed_scale()
	playable_map=generated.map
	player_hex=generated.entrance
	playable_map.place_entity("PLAYER",player_hex)
	patrol_runtime.configure(playable_map,generated.patrols)
	battle_active=false
	battle_entity_id=""
	battle_group_ids.clear()
	battle_group_state=null
	battle_combat_state=null
	chase_entity_id=""
	if battle_dialog!=null: battle_dialog.hide()
	_moving=false
	_stop_requested=false
	_next_hex=Vector2i(-1,-1)
	target_hex=Vector2i(-1,-1)
	planned_path.clear()
	canvas.set_player_view(player_hex,target_hex,planned_path)
	mini_map.update_map(playable_map,player_hex)
	mini_map.set_regions(generated.get("regions",[]),reveal_map_toggle.button_pressed if reveal_map_toggle!=null else true)
	canvas.visible=false
	call_deferred("_adapt_layout")
	_camera_ready=false
	call_deferred("_finish_initial_camera")
	if move_status!=null:
		move_status.text="Выберите клетку"
	_update_movement_panel()
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
	summary.text="Seed: %d\nCandidates: %d\nPockets: %d\nRegions: %d\nAttempts: %d\nGeometry rejects: %d\nMap: %dx%d\nBlocked: %d\nResources: %d\nObjects: %d\nNPC: %d\nEncounters: %d\nObject Guards: %d\nRoute Guards: %d\nPatrols: %d\nBosses: %d\nBoss Guards: %d"%[
		seed_value,int(generated.get("region_candidates",0)),generated.get("pockets",[]).size(),generated.get("regions",[]).size(),int(generated.get("pocket_attempts",0)),int(generated.get("geometry_rejections",0)),
		map.width,map.height,blocked,
		generated.resource_cells.size(),generated.object_cells.size(),generated.npc_cells.size(),
		generated.encounter_cells.size(),generated.guarded_objects.size(),generated.route_guards.size(),
		generated.patrols.size(),boss_count,boss_guard_count
	]

func _adapt_layout()->void:
	# Explicit square map viewport: only the sidebar changes sides.
	var available:Vector2=$Root.size
	if available.x<=0.0 or available.y<=0.0: return
	var portrait:=available.y>=available.x
	var map_side:float
	var sidebar:VBoxContainer=$Root/Sidebar
	var map_panel:Control=$Root/MapPanel
	if portrait:
		map_side=available.x
		map_panel.position=Vector2.ZERO
		sidebar.position=Vector2(0.0,map_side+12.0)
		sidebar.size=Vector2(available.x,maxf(0.0,available.y-map_side-12.0))
	else:
		map_side=minf(available.y,maxf(120.0,available.x-260.0))
		map_panel.position=Vector2.ZERO
		sidebar.position=Vector2(map_side+12.0,0.0)
		sidebar.size=Vector2(maxf(0.0,available.x-map_side-12.0),available.y)
	map_panel.size=Vector2(map_side,map_side)
	map_scroll.position=Vector2.ZERO
	map_scroll.size=map_panel.size
	$Root/Sidebar/LegendTitle.visible=not portrait
	$Root/Sidebar/Legend.visible=not portrait
	$Root/Sidebar/Hint.visible=not portrait
	$Root/Sidebar/SummaryTitle.visible=not portrait
	$Root/Sidebar/Summary.visible=not portrait
	if game_nav!=null:
		game_nav.columns=2 if portrait else 4
	_position_minimap()
	_center_on_player()
	if not _camera_ready: call_deferred("_finish_initial_camera")

func _position_minimap()->void:
	if mini_map==null: return
	var side:=minf(155.0,$Root/MapPanel.size.x*0.24)
	mini_map.size=Vector2(side,side)
	mini_map.position=$Root/MapPanel.size-mini_map.size-Vector2(12.0,12.0)

func _visible_cells()->Dictionary:
	var result:Dictionary={}
	for pos in playable_map.cells.keys():
		if canvas._is_visible_hex(pos): result[pos]=true
	return result

func _route_to(destination:Vector2i,allow_target_npc:bool=false)->Array[Vector2i]:
	return SafeMapNavigation.find_route(playable_map,canvas.explored_hexes,player_hex,destination,_visible_cells(),canvas._entity_roles,allow_target_npc)

func _select_destination(pos:Vector2i)->void:
	if playable_map==null or battle_active: return
	if pos==player_hex:
		if _moving:
			_request_stop()
		return
	if not canvas.explored_hexes.has(pos): return
	if _moving:
		_request_stop()
		return
	if pos==target_hex and planned_path.size()>1:
		_moving=true
		_stop_requested=false
		_prepare_step()
		_update_movement_panel()
		return
	target_hex=pos
	chase_entity_id=_npc_at(pos) if canvas._is_visible_hex(pos) else ""
	planned_path=_route_to(target_hex,not chase_entity_id.is_empty())
	if planned_path.size()>1:
		var seconds:=0.0
		for i in range(1,planned_path.size()):
			seconds+=SafeMapNavigation.terrain_seconds(playable_map.cell(planned_path[i]).terrain_id)
		move_status.text="Путь: %d гексов, %.0f сек. Нажмите ещё раз"%[planned_path.size()-1,seconds]
	else:
		move_status.text="Безопасный путь недоступен"
	canvas.set_player_view(player_hex,target_hex,planned_path)
	_update_movement_panel()

func _prepare_step()->void:
	if _stop_requested or planned_path.size()<2:
		_moving=false
		_stop_requested=false
		_next_hex=Vector2i(-1,-1)
		move_status.text="Остановлено" if planned_path.size()>1 else "Прибытие"
		_update_movement_panel()
		return
	# Only chase mode recalculates a moving target, at step boundaries.
	if not chase_entity_id.is_empty():
		if not playable_map.entity_positions.has(chase_entity_id):
			_moving=false
			move_status.text="Цель исчезла"
			_update_movement_panel()
			return
		var observed:Vector2i=playable_map.entity_positions[chase_entity_id]
		if canvas._is_visible_hex(observed):
			target_hex=observed
			planned_path=_route_to(target_hex,true)
			canvas.set_player_view(player_hex,target_hex,planned_path)
		else:
			chase_entity_id=""
			# Last known destination only; never use hidden NPC coordinates.
			planned_path=_route_to(target_hex,true)
		if planned_path.size()<2:
			_moving=false
			move_status.text="Цель недоступна"
			_update_movement_panel()
			return
	var next:Vector2i=planned_path[1]
	if not playable_map.cell(next).is_passable():
		_moving=false
		move_status.text="Маршрут заблокирован"
		_update_movement_panel()
		return
	_next_hex=next
	_step_elapsed=0.0
	_step_duration=SafeMapNavigation.terrain_seconds(playable_map.cell(next).terrain_id)
	move_status.text="Движение: %.0f сек/гекс"%_step_duration

func _process(delta:float)->void:
	if battle_active: return
	if patrol_runtime.advance(delta):
		canvas.queue_redraw()
	if not patrol_runtime.collision_entity_id.is_empty():
		_start_test_battle(patrol_runtime.collision_entity_id)
		patrol_runtime.collision_entity_id=""
		return
	if not _moving or _next_hex.x<0: return
	_step_elapsed+=delta
	_update_movement_panel()
	if _step_elapsed<_step_duration: return
	var result:Dictionary=playable_map.move_entity("PLAYER",_next_hex)
	if not bool(result.get("ok",false)):
		_moving=false
		move_status.text="Движение: "+str(result.get("reason","ошибка"))
		_update_movement_panel()
		return
	player_hex=_next_hex
	planned_path.remove_at(0)
	var encountered_id:=_npc_at(player_hex)
	if not encountered_id.is_empty():
		canvas.set_player_view(player_hex,target_hex,planned_path)
		mini_map.update_map(playable_map,player_hex)
		_center_on_player()
		_start_test_battle(encountered_id)
		return
	canvas.set_player_view(player_hex,target_hex,planned_path)
	mini_map.update_map(playable_map,player_hex)
	_center_on_player()
	_prepare_step()
	_update_movement_panel()

func _set_fixed_scale()->void:
	if canvas==null:
		return
	canvas.HEX_SIZE=40.0
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

func _build_movement_panel()->void:
	# Movement HUD belongs to GameUI, never to the map viewport.
	movement_panel=PanelContainer.new()
	movement_panel.name="MovementPanel"
	movement_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	$Root/Sidebar.add_child(movement_panel)
	$Root/Sidebar.move_child(movement_panel,2)
	var row:=HBoxContainer.new()
	movement_panel.add_child(row)
	var info_column:=VBoxContainer.new()
	info_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(info_column)
	movement_info=Label.new()
	movement_info.text="Движение"
	movement_info.clip_text=true
	info_column.add_child(movement_info)
	movement_progress=ProgressBar.new()
	movement_progress.min_value=0.0
	movement_progress.max_value=100.0
	movement_progress.show_percentage=false
	movement_progress.custom_minimum_size.y=10.0
	info_column.add_child(movement_progress)
	stop_button=Button.new()
	stop_button.text="Стоп"
	stop_button.custom_minimum_size=Vector2(64,40)
	stop_button.pressed.connect(_request_stop)
	row.add_child(stop_button)
	movement_panel.visible=false

func _build_game_navigation()->void:
	# These are layout probes only; game screens are not connected yet.
	game_nav=GridContainer.new()
	game_nav.name="GameNavigation"
	game_nav.columns=2
	game_nav.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	game_nav.add_theme_constant_override("h_separation",8)
	game_nav.add_theme_constant_override("v_separation",8)
	$Root/Sidebar.add_child(game_nav)
	$Root/Sidebar.move_child(game_nav,3)
	for title in ["Персонаж","Инвентарь","Квесты","Карта"]:
		var button:=Button.new()
		button.name=title
		button.text=title
		button.custom_minimum_size.y=48.0
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.tooltip_text="Раздел будет подключён позже"
		game_nav.add_child(button)

func _request_stop()->void:
	if not _moving: return
	_stop_requested=true
	move_status.text="Остановка после перехода"
	_update_movement_panel()

func _update_movement_panel()->void:
	if movement_panel==null: return
	movement_panel.visible=_moving
	if not _moving: return
	var remaining:=maxf(0.0,_step_duration-_step_elapsed)
	for i in range(2,planned_path.size()):
		remaining+=SafeMapNavigation.terrain_seconds(playable_map.cell(planned_path[i]).terrain_id)
	movement_info.text="%d гексов · ~%.0f сек%s"%[maxi(0,planned_path.size()-1),remaining," · остановка" if _stop_requested else ""]
	movement_progress.value=100.0*clampf(_step_elapsed/maxf(0.001,_step_duration),0.0,1.0)
	stop_button.disabled=_stop_requested

func _finish_initial_camera()->void:
	if _camera_ready or playable_map==null: return
	if map_scroll.size.x<=0.0 or map_scroll.size.y<=0.0:
		call_deferred("_finish_initial_camera")
		return
	_center_on_player()
	_camera_ready=true
	canvas.visible=true

func _npc_at(pos:Vector2i)->String:
	for entity_id in playable_map.entities_at(pos):
		if entity_id!="PLAYER": return entity_id
	return ""

func _start_test_battle(entity_id:String)->void:
	if battle_active or entity_id.is_empty() or not playable_map.entity_positions.has(entity_id): return
	battle_group_ids.clear()
	var contact_pos:Vector2i=playable_map.entity_positions[entity_id]
	for candidate in playable_map.entities_at(contact_pos):
		if candidate!="PLAYER":
			battle_group_ids.append(candidate)
	if battle_group_ids.is_empty(): return
	battle_combat_state=CombatState.new()
	battle_combat_state.add_combatant(CombatantState.new("PLAYER","Hero",1,100,30))
	battle_group_state=GroupCombatState.new(battle_combat_state)
	battle_group_state.add_member("A","PLAYER")
	for candidate in battle_group_ids:
		battle_combat_state.add_combatant(CombatantState.new(candidate,candidate,1,80,0))
		battle_group_state.add_member("B",candidate)
	battle_group_state.set_active_opponent("PLAYER",battle_group_ids[0])
	battle_active=true
	battle_entity_id=battle_group_ids[0]
	battle_defeat_button.visible=canvas._entity_roles.get(entity_id,"") in ["B","BG"]
	_moving=false
	_stop_requested=false
	_next_hex=Vector2i(-1,-1)
	planned_path.clear()
	chase_entity_id=""
	target_hex=Vector2i(-1,-1)
	move_status.text="Начался бой!"
	_update_movement_panel()
	canvas.set_player_view(player_hex,target_hex,planned_path)
	battle_dialog.dialog_text="Тестовое столкновение: %d противников.\nПодключён GroupCombatState; реальное разрешение раундов пока в отладочном бою."%battle_group_ids.size()
	battle_dialog.popup_centered(Vector2i(380,180))

func _finish_test_battle()->void:
	if not battle_active: return
	battle_active=false
	# Placeholder victory removes all members of the contacted hex, never just one.
	for defeated_id in battle_group_ids:
		playable_map.remove_entity(defeated_id)
	battle_group_ids.clear()
	battle_group_state=null
	battle_combat_state=null
	battle_entity_id=""
	battle_dialog.hide()
	move_status.text="Тестовый бой завершён"
	canvas.set_player_view(player_hex,target_hex,planned_path)
	mini_map.update_map(playable_map,player_hex)

func _on_battle_custom_action(action:StringName)->void:
	if action==&"defeat":
		_finish_test_defeat()

func _finish_test_defeat()->void:
	if not battle_active: return
	battle_active=false
	battle_entity_id=""
	battle_group_ids.clear()
	battle_group_state=null
	battle_combat_state=null
	battle_dialog.hide()
	# Test defeat: retain boss/guard and move player to the safe entrance.
	playable_map.entity_positions["PLAYER"]=canvas.generated.entrance
	player_hex=canvas.generated.entrance
	_moving=false
	_stop_requested=false
	_next_hex=Vector2i(-1,-1)
	planned_path.clear()
	chase_entity_id=""
	target_hex=Vector2i(-1,-1)
	move_status.text="Поражение: возвращение ко входу"
	_update_movement_panel()
	canvas.set_player_view(player_hex,target_hex,planned_path)
	mini_map.update_map(playable_map,player_hex)
	_center_on_player()
