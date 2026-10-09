class_name DebugMiniMap
extends Control

var map_data:TacticalMapState
var player_cell:=Vector2i(-1,-1)
const RADIUS:=7

func update_map(map:TacticalMapState,player:Vector2i)->void:
	map_data=map
	player_cell=player
	queue_redraw()

func _draw()->void:
	if map_data==null:
		return
	var pad:=8.0
	var cell_size:=Vector2((size.x-pad*2.0)/float(map_data.width),(size.y-pad*2.0)/float(map_data.height))
	for y in range(map_data.height):
		for x in range(map_data.width):
			var cell:=Vector2i(x,y)
			var data:MapCell=map_data.cell(cell)
			var color:=Color(0.22,0.45,0.27) if data.is_passable() else Color(0.12,0.13,0.17)
			if HexGrid.distance(player_cell,cell)>RADIUS:
				color=color.darkened(0.55)
			draw_rect(Rect2(Vector2(pad,pad)+Vector2(x,y)*cell_size,cell_size-Vector2.ONE),color)
	if player_cell.x>=0:
		var center:=Vector2(pad,pad)+(Vector2(player_cell)+Vector2(0.5,0.5))*cell_size
		draw_circle(center,maxf(3.0,minf(cell_size.x,cell_size.y)*0.5),Color(0.22,0.88,1.0))
