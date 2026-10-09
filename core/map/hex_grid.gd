class_name HexGrid
extends RefCounted

const DIRECTIONS:Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]

static func to_axial(offset:Vector2i)->Vector2i:
	return Vector2i(offset.x - int(floor(float(offset.y - (offset.y & 1))/2.0)), offset.y)

static func from_axial(axial:Vector2i)->Vector2i:
	return Vector2i(axial.x + int(floor(float(axial.y - (axial.y & 1))/2.0)), axial.y)

static func neighbors(hex:Vector2i)->Array[Vector2i]:
	var result:Array[Vector2i] = []
	for direction in DIRECTIONS:
		result.append(from_axial(to_axial(hex) + direction))
	return result

static func distance(a:Vector2i, b:Vector2i)->int:
	var aa:=to_axial(a)
	var bb:=to_axial(b)
	var dq:=aa.x - bb.x
	var dr:=aa.y - bb.y
	var ds:=(-a.x - a.y) - (-b.x - b.y)
	return maxi(absi(dq), maxi(absi(dr), absi(ds)))
