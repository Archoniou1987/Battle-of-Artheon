class_name SquareGrid
extends RefCounted

const DIRECTIONS:Array[Vector2i] = [
	Vector2i(1,0),
	Vector2i(0,1),
	Vector2i(-1,0),
	Vector2i(0,-1)
]

static func neighbors(cell:Vector2i)->Array[Vector2i]:
	var result:Array[Vector2i]=[]
	for direction in DIRECTIONS:
		result.append(cell+direction)
	return result

static func distance(a:Vector2i,b:Vector2i)->int:
	return absi(a.x-b.x)+absi(a.y-b.y)
