class_name HexGrid
extends RefCounted

const DIRECTIONS:Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]

static func neighbors(hex:Vector2i)->Array[Vector2i]:
	var result:Array[Vector2i] = []
	for direction in DIRECTIONS:
		result.append(hex + direction)
	return result

static func distance(a:Vector2i, b:Vector2i)->int:
	var dq:=a.x - b.x
	var dr:=a.y - b.y
	var ds:=(-a.x - a.y) - (-b.x - b.y)
	return maxi(absi(dq), maxi(absi(dr), absi(ds)))
