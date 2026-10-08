class_name SquareMapState
extends RefCounted

var width:int
var height:int
var blocked_cells:Dictionary={}
var player_position:Vector2i=Vector2i.ZERO

func _init(map_width:int,map_height:int,start:Vector2i=Vector2i.ZERO)->void:
	width=maxi(1,map_width)
	height=maxi(1,map_height)
	player_position=start if in_bounds(start) else Vector2i.ZERO

func in_bounds(pos:Vector2i)->bool:
	return pos.x>=0 and pos.y>=0 and pos.x<width and pos.y<height

func is_passable(pos:Vector2i)->bool:
	return in_bounds(pos) and not blocked_cells.has(pos)

func set_blocked(pos:Vector2i,blocked:bool=true)->bool:
	if not in_bounds(pos):
		return false
	if blocked:
		blocked_cells[pos]=true
	else:
		blocked_cells.erase(pos)
	return true

func passable_neighbors(pos:Vector2i)->Array[Vector2i]:
	var result:Array[Vector2i]=[]
	for neighbor in SquareGrid.neighbors(pos):
		if is_passable(neighbor):
			result.append(neighbor)
	return result

func move_player(target:Vector2i)->Dictionary:
	if not in_bounds(target):
		return {"ok":false,"reason":"out_of_bounds","position":player_position}
	if SquareGrid.distance(player_position,target)!=1:
		return {"ok":false,"reason":"not_adjacent","position":player_position}
	if not is_passable(target):
		return {"ok":false,"reason":"blocked","position":player_position}
	player_position=target
	return {"ok":true,"position":player_position}

func to_dict()->Dictionary:
	var blocked:Array=[]
	for pos in blocked_cells.keys():
		blocked.append([pos.x,pos.y])
	return {"width":width,"height":height,"player_position":[player_position.x,player_position.y],"blocked_cells":blocked}

static func from_dict(data:Dictionary)->SquareMapState:
	var player:Array=data.get("player_position",[0,0])
	var state:=SquareMapState.new(int(data.get("width",1)),int(data.get("height",1)),Vector2i(int(player[0]),int(player[1])))
	for raw in data.get("blocked_cells",[]):
		state.set_blocked(Vector2i(int(raw[0]),int(raw[1])),true)
	return state
