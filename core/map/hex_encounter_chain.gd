class_name HexEncounterChain
extends RefCounted

static func resolve_events(events:Array[Dictionary], map:TacticalMapState, service:HexEncounterService)->Dictionary:
	var resolved:Array[Dictionary] = []
	var failed:Array[Dictionary] = []
	for event in events:
		var result:=HexEncounterResolver.resolve(event,map)
		if bool(result.get("ok",false)):
			resolved.append(result)
			var payload:Dictionary=event.get("payload",{})
			var set_flags:Array=payload.get("set_flags",[])
			for flag in set_flags:
				service.set_flag(str(flag),true)
			var clear_flags:Array=payload.get("clear_flags",[])
			for flag in clear_flags:
				service.set_flag(str(flag),false)
		else:
			failed.append(result)
	return {"ok":failed.is_empty(),"resolved":resolved,"failed":failed}
