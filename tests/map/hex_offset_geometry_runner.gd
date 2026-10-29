extends SceneTree

func _initialize()->void:
	var ok:=true
	for r in range(20):
		for q in range(20):
			var pos:=Vector2i(q,r)
			ok=ok and HexGrid.from_axial(HexGrid.to_axial(pos))==pos
			for next in HexGrid.neighbors(pos):
				ok=ok and HexGrid.distance(pos,next)==1
				ok=ok and HexGrid.neighbors(next).has(pos)
				var x0:=sqrt(3.0)*(float(q)+float(r & 1)*0.5)
				var y0:=1.5*float(r)
				var x1:=sqrt(3.0)*(float(next.x)+float(next.y & 1)*0.5)
				var y1:=1.5*float(next.y)
				ok=ok and absf(Vector2(x0,y0).distance_to(Vector2(x1,y1))-sqrt(3.0))<0.001
	var generated:=LocationGenerator.generate(20,20,777)
	var map:TacticalMapState=generated.map
	var path:Array=generated.guaranteed_path
	ok=ok and path.size()>1 and path.front()==generated.entrance and path.back()==generated.exit
	for i in range(1,path.size()):
		ok=ok and HexGrid.distance(path[i-1],path[i])==1
		ok=ok and map.neighbors(path[i-1]).has(path[i])
	print("HEX_OFFSET_GEOMETRY_TEST="+("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
