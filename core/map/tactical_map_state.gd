class_name TacticalMapState
extends RefCounted
var width:int
var height:int
var cells:Dictionary = {}
var areas:Dictionary = {}
var entity_positions:Dictionary = {}
func _init(p_width:int,p_height:int,default_terrain:String="grass",default_cost:float=1.0)->void:
	width=maxi(1,p_width); height=maxi(1,p_height)
	for r in range(height):
		for q in range(width):
			var c:=MapCell.new(q,r,default_terrain,default_cost); cells[c.key()]=c
func in_bounds(pos:Vector2i)->bool:
	return pos.x>=0 and pos.y>=0 and pos.x<width and pos.y<height
func cell(pos:Vector2i)->MapCell:
	return cells.get(pos,null)
func neighbors(pos:Vector2i,passable_only:bool=false)->Array[Vector2i]:
	var result:Array[Vector2i]=[]
	for candidate in HexGrid.neighbors(pos):
		if in_bounds(candidate) and (not passable_only or cell(candidate).is_passable()): result.append(candidate)
	return result
func set_terrain(pos:Vector2i,terrain_id:String,movement_cost:float)->bool:
	var target:=cell(pos)
	if target==null: return false
	target.terrain_id=terrain_id; target.movement_cost=maxf(0.0,movement_cost); return true
func set_obstacle(pos:Vector2i,obstacle_id:String,is_blocked:bool=true)->bool:
	var target:=cell(pos)
	if target==null: return false
	target.obstacle_id=obstacle_id; target.blocked=is_blocked; return true
func add_area(area:MapArea,positions:Array[Vector2i])->bool:
	if area==null or area.area_id.is_empty() or areas.has(area.area_id): return false
	for pos in positions:
		if not in_bounds(pos): return false
	areas[area.area_id]=area
	for pos in positions: cell(pos).area_ids.append(area.area_id)
	return true
func place_entity(entity_id:String,pos:Vector2i)->bool:
	if entity_id.is_empty() or not in_bounds(pos) or not cell(pos).is_passable(): return false
	entity_positions[entity_id]=pos; return true
func move_entity(entity_id:String,to:Vector2i)->Dictionary:
	if not entity_positions.has(entity_id): return {"ok":false,"reason":"unknown_entity"}
	if not in_bounds(to): return {"ok":false,"reason":"out_of_bounds"}
	var target:=cell(to)
	if not target.is_passable(): return {"ok":false,"reason":"blocked"}
	var from:Vector2i=entity_positions[entity_id]
	if HexGrid.distance(from,to)!=1: return {"ok":false,"reason":"not_adjacent"}
	entity_positions[entity_id]=to; target.discovered=true; target.visited=true
	return {"ok":true,"from":from,"to":to,"movement_cost":target.movement_cost,"areas":target.area_ids.duplicate(),"objects":target.object_ids.duplicate(),"effects":target.effects.duplicate(),"triggers":target.triggers.duplicate()}
