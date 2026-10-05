class_name BalanceCurve
extends RefCounted

## Small interpolation helper for data-driven balance curves.

static func sample(points: Array, input: float) -> float:
	if points.is_empty():
		return 0.0
	if input <= float(points[0][0]):
		return float(points[0][1])
	for i in range(1, points.size()):
		var x1 := float(points[i][0])
		if input <= x1:
			var x0 := float(points[i - 1][0])
			var y0 := float(points[i - 1][1])
			var y1 := float(points[i][1])
			if is_equal_approx(x0, x1):
				return y1
			return lerpf(y0, y1, (input - x0) / (x1 - x0))
	return float(points[-1][1])
