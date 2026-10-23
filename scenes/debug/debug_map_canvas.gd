class_name DebugMapCanvas
extends Control

var HEX_SIZE:=20.0
var map_offset:=Vector2.ZERO
var visibility_radius:int=3 # Gameplay visibility, independent of viewport and camera scale.
var debug_reveal_all:bool=false
var vision_talent_bonus:int=0
var vision_equipment_bonus:int=0
var vision_effect_bonus:int=0

func effective_visibility_radius()->int:
	return maxi(0,visibility_radius+vision_talent_bonus+vision_equipment_bonus+vision_effect_bonus)

const SQRT3:=1.7320508075688772

var generated:Dictionary={}
var _entity_roles:Dictionary={}
signal loot_hex_selected(cell:Vector2i)
signal hex_selected(cell:Vector2i)
var player_hex:=Vector2i(-1,-1)
var selected_hex:=Vector2i(-1,-1)
var preview_path:Array[Vector2i]=[]
var explored_hexes:Dictionary={}

func remember_visible()->void:
	if generated.is_empty() or player_hex.x<0: return
	var map:TacticalMapState=generated.map
	for pos in map.cells.keys():
		if _is_visible_hex(pos):
			explored_hexes[pos]=true
			map.cell(pos).discovered=true
	queue_redraw()


func set_player_view(pos:Vector2i,selected:Vector2i,path:Array[Vector2i])->void:
	player_hex=pos
	selected_hex=selected
	preview_path=path.duplicate()
	remember_visible()
	queue_redraw()
var loot_markers:Array[Vector2i]=[]

func set_loot_markers(cells:Array[Vector2i])->void:
	loot_markers=cells.duplicate()
	queue_redraw()

func set_debug_reveal_all(enabled:bool)->void:
	debug_reveal_all=enabled
	remember_visible()
	queue_redraw()

func set_generated(value:Dictionary)->void:
	generated=value
	explored_hexes.clear()
	player_hex=Vector2i(-1,-1)
	_build_entity_roles()
	custom_minimum_size=_map_pixel_size()
	queue_redraw()

## Optional live-world role mapping. The same renderer is used by the
## diagnostic viewer and the real Solo map without inventing NPC state.
func set_live_entity_roles(roles: Dictionary) -> void:
	for raw_id in roles.keys():
		_entity_roles[String(raw_id)] = String(roles[raw_id])
	queue_redraw()

func _gui_input(event:InputEvent)->void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:
		return
	for cell in loot_markers:
		if not _is_visible_hex(cell):
			continue
		var center:=_hex_center(cell)+Vector2(HEX_SIZE*0.48,-HEX_SIZE*0.42)
		if event.position.distance_to(center)<=14.0:
			loot_hex_selected.emit(cell)
			accept_event()
			return
	if generated.is_empty():
		return
	var map:TacticalMapState=generated.map
	for r in range(map.height):
		for q in range(map.width):
			var pos:=Vector2i(q,r)
			if explored_hexes.has(pos) and Geometry2D.is_point_in_polygon(event.position,_hex_points(_hex_center(pos))):
				hex_selected.emit(pos)
				accept_event()
				return

func _build_entity_roles()->void:
	_entity_roles.clear()
	for i in range(generated.get("npc_cells",[]).size()):
		_entity_roles["GEN_NPC_%02d"%i]="NPC"
	for region_npc in generated.get("region_npcs",[]):
		_entity_roles[region_npc["entity_id"]]=({"bandit_camp":"BD","graveyard":"UD","beast_den":"BT","ruins":"RN"}).get(str(region_npc["region_type"]),"NPC")
	for route_guard in generated.get("route_guards",[]):
		_entity_roles[route_guard.guard_id]="RG"
	for patrol in generated.get("patrols",[]):
		_entity_roles[patrol.patrol_id]="P"
	for guarded in generated.get("guarded_objects",[]):
		_entity_roles[guarded.guard_id]="OG"
	for boss_group in generated.get("boss_groups",[]):
		_entity_roles[boss_group.boss_id]="B"
		for guard_id in boss_group.guard_ids:
			_entity_roles[guard_id]="BG"

func _draw()->void:
	if generated.is_empty():
		return
	var map:TacticalMapState=generated.map
	for r in range(map.height):
		for q in range(map.width):
			var pos:=Vector2i(q,r)
			var center:=_hex_center(pos)
			var cell:MapCell=map.cell(pos)
			var tint:=Color(0.12,0.13,0.17)
			if _is_visible_hex(pos): tint=_cell_color(cell)
			elif explored_hexes.has(pos): tint=_cell_color(cell).lerp(Color(0.30,0.32,0.36),0.55)
			draw_colored_polygon(_hex_points(center),tint)
			draw_polyline(_closed_hex_points(center),Color(0.16,0.20,0.27),1.0,true)
	_draw_region_outlines()
	for patrol in generated.get("patrols",[]):
		var points:=PackedVector2Array()
		for pos in patrol.path:
			if _is_visible_hex(pos):
				if points.size()>=2:
					draw_polyline(points,Color(0.95,0.72,0.20),3.0,true)
				points.clear()
				points.append(_hex_center(pos))
			elif points.size()>=2:
				draw_polyline(points,Color(0.95,0.72,0.20),3.0,true)
				points.clear()
			else:
				points.clear()
		if points.size()>=2:
			draw_polyline(points,Color(0.95,0.72,0.20),3.0,true)
		for pause in patrol.get("pause_points",[]):
			var pause_index:int=int(pause.get("path_index",-1))
			if pause_index>=0 and pause_index<patrol.path.size() and _is_visible_hex(patrol.path[pause_index]):
				draw_circle(_hex_center(patrol.path[pause_index]),5.0,Color(1.0,0.90,0.35),false,2.0,true)
	_draw_markers(map)
	_draw_region_props()
	_draw_loot_markers()
	if preview_path.size()>1:
		var line:=PackedVector2Array()
		for pos in preview_path:
			if explored_hexes.has(pos): line.append(_hex_center(pos))
		draw_polyline(line,Color(0.20,0.85,1.0),3.0,true)
	if selected_hex.x>=0 and explored_hexes.has(selected_hex):
		draw_polyline(_closed_hex_points(_hex_center(selected_hex)),Color(0.30,0.90,1.0),3.0,true)
	if player_hex.x>=0:
		_draw_badge(_hex_center(player_hex),"YOU",Color(0.35,0.80,1.0))

func _draw_region_outlines()->void:
	# The six sides follow the odd-row offset hex geometry.
	# A region boundary is drawn only when the adjacent hex is outside its cells.
	for region in generated.get("regions",[]):
		var owned:Dictionary={}
		for pos in region["cells"]:
			owned[pos]=true
		for pos in region["cells"]:
			if not _is_visible_hex(pos) and not explored_hexes.has(pos):
				continue
			var vertices:=_hex_points(_hex_center(pos))
			for side in range(6):
				var a:Vector2=vertices[side]
				var b:Vector2=vertices[(side+1)%6]
				var midpoint:Vector2=(a+b)*0.5
				var adjacent:=Vector2i(-1,-1)
				var nearest_distance:=INF
				for neighbor in HexGrid.neighbors(pos):
					var d:float=midpoint.distance_squared_to(_hex_center(neighbor))
					if d<nearest_distance:
						nearest_distance=d
						adjacent=neighbor
				if not owned.has(adjacent):
					draw_line(a,b,Color(0.08,0.06,0.01,1.0),8.0,true)
					draw_line(a,b,Color(1.0,0.90,0.02,1.0),5.0,true)
		# Debug identifier confirms the region exists even when only part is on screen.
		if debug_reveal_all and not region["cells"].is_empty():
			var label_pos:Vector2i=region["cells"][0]
			var center:=_hex_center(label_pos)
			var title:String=str(region["region_type"])
			var font:=ThemeDB.fallback_font
			draw_string(font,center+Vector2(-18.0,-22.0),title,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color(1.0,0.93,0.15))

func _draw_markers(map:TacticalMapState)->void:
	if _is_visible_hex(generated.entrance): _draw_badge(_hex_center(generated.entrance),"IN",Color(0.20,0.80,0.45))
	if _is_visible_hex(generated.exit): _draw_badge(_hex_center(generated.exit),"OUT",Color(0.25,0.60,1.0))
	for pos in generated.get("resource_cells",[]):
		if not _is_visible_hex(pos): continue
		_draw_badge(_hex_center(pos),"R",Color(0.25,0.75,0.55))
	for pos in generated.get("object_cells",[]):
		if not _is_visible_hex(pos): continue
		_draw_badge(_hex_center(pos),"O",Color(0.70,0.48,0.22))
	for pos in generated.get("encounter_cells",[]):
		if not _is_visible_hex(pos): continue
		_draw_badge(_hex_center(pos),"E",Color(0.75,0.35,0.75))
	var grouped:Dictionary={}
	for entity_id in map.entity_positions.keys():
		var pos:Vector2i=map.entity_positions[entity_id]
		if entity_id=="PLAYER":
			continue
		if not grouped.has(pos):
			grouped[pos]=[]
		grouped[pos].append(entity_id)
	for pos in grouped.keys():
		if not _is_visible_hex(pos):
			continue
		var occupants:Array=grouped[pos]
		var role:String=_entity_roles.get(occupants[0],"?")
		var color:=Color(0.88,0.88,0.90)
		if role=="B": color=Color(0.90,0.18,0.20)
		elif role=="BG": color=Color(0.82,0.32,0.25)
		elif role=="P": color=Color(0.95,0.72,0.20)
		elif role=="RG": color=Color(0.45,0.60,0.95)
		elif role=="OG": color=Color(0.72,0.52,0.30)
		_draw_badge(_hex_center(pos),role,color)
		if occupants.size()>1:
			draw_string(ThemeDB.fallback_font,_hex_center(pos)+Vector2(10.0,-12.0),"x%d"%occupants.size(),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color(1.0,0.95,0.75))

func _draw_region_props()->void:
	for prop in generated.get("region_objects",[]):
		var pos:Vector2i=prop["pos"]
		if not _is_visible_hex(pos):
			continue
		var symbol:String=({"tent":"T","grave":"G","bones":"X","relic":"A"}).get(str(prop["kind"]),"O")
		var center:=_hex_center(pos)+Vector2(10.0,10.0)
		draw_circle(center,9.0,Color(0.08,0.08,0.09))
		draw_circle(center,7.0,Color(0.95,0.82,0.46))
		draw_string(ThemeDB.fallback_font,center+Vector2(-4.0,4.0),symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color(0.10,0.09,0.06))

func _draw_loot_markers()->void:
	for cell in loot_markers:
		if not _is_visible_hex(cell): continue
		var center:=_hex_center(cell)+Vector2(HEX_SIZE*0.48,-HEX_SIZE*0.42)
		draw_circle(center,11.0,Color(0.98,0.77,0.25))
		draw_arc(center,10.0,0.0,TAU,20,Color(0.48,0.28,0.07),1.4,true)
		draw_line(center+Vector2(-4.0,0.0),center+Vector2(4.0,0.0),Color(0.48,0.28,0.07),1.5,true)

func _is_visible_hex(pos:Vector2i)->bool:
	if debug_reveal_all and not generated.is_empty():
		return true
	if player_hex.x<0:
		return false
	# Odd-row offset coordinates -> axial coordinates, then hex distance.
	return HexGrid.distance(pos,player_hex)<=effective_visibility_radius()

func _cell_color(cell:MapCell)->Color:
	if cell.blocked:
		return Color(0.16,0.17,0.20)
	if cell.terrain_id=="swamp":
		return Color(0.18,0.32,0.26)
	if cell.terrain_id=="rough":
		return Color(0.35,0.30,0.22)
	return Color(0.20,0.38,0.24)

func _draw_badge(center:Vector2,label:String,color:Color)->void:
	draw_circle(center,17.0,Color(0.035,0.045,0.06))
	draw_circle(center,15.0,color)
	var font:=ThemeDB.fallback_font
	var size:=17 if label.length()<=2 else 13
	var width:=font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	draw_string(font,center+Vector2(-width*0.5,float(size)*0.34),label,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color(0.04,0.05,0.07))

func _hex_center(pos:Vector2i)->Vector2:
	var stagger:=0.5 if pos.y%2!=0 else 0.0
	return map_offset+Vector2(HEX_SIZE*SQRT3*(float(pos.x)+stagger)+HEX_SIZE*1.1,HEX_SIZE*1.5*float(pos.y)+HEX_SIZE*1.1)

func _hex_points(center:Vector2)->PackedVector2Array:
	var points:=PackedVector2Array()
	for i in range(6):
		var angle:=deg_to_rad(60.0*float(i)-30.0)
		points.append(center+Vector2(cos(angle),sin(angle))*HEX_SIZE)
	return points

func _closed_hex_points(center:Vector2)->PackedVector2Array:
	var points:=_hex_points(center)
	points.append(points[0])
	return points

func _map_pixel_size()->Vector2:
	if generated.is_empty():
		return Vector2(900,680)
	var map:TacticalMapState=generated.map
	return Vector2(HEX_SIZE*SQRT3*(float(map.width)+0.5)+HEX_SIZE*2.5,HEX_SIZE*1.5*float(map.height)+HEX_SIZE*2.5)
