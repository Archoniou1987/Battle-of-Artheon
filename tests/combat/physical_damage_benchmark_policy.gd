class_name PhysicalDamageBenchmarkPolicy
extends RefCounted

## Benchmark-only choice policy; ordinary Combat Engine rules stay untouched.
## AP generation is prioritised whenever its cooldown expires. Costly ABIs
## rotate in slot order, and the rotation advances only after a real cast.
static func choose(abilities: Array, definitions: Dictionary, cooldowns: Dictionary, round_number: int, ap: int, max_ap: int, spend_cursor: int) -> Dictionary:
	var generators: Array[String] = []
	var spenders: Array[String] = []
	for raw in abilities:
		var id := String(raw)
		var definition: Dictionary = definitions.get(id,{})
		if definition.is_empty():
			continue
		if int(definition.get("ap_gain",0)) > 0 or bool(definition.get("ap_gain_on_hit",false)) and int(definition.get("ap_cost",0))==0:
			generators.append(id)
		else:
			spenders.append(id)
	for id in generators:
		var def: Dictionary = definitions.get(id,{})
		if AbilityRuntime.can_use(id,cooldowns,round_number) and ap < max_ap and _can_pay(def,ap):
			return {"id":id,"cursor":spend_cursor,"mode":"gain"}
	if spenders.is_empty():
		return {"id":"","cursor":spend_cursor,"mode":"none"}
	# Sequential cost ABI selection, scanning forward only when the current
	# one is unavailable. A costly ABI never casts without sufficient AP.
	for n in range(spenders.size()):
		var index := (spend_cursor+n)%spenders.size()
		var id := spenders[index]
		var def: Dictionary = definitions.get(id,{})
		if AbilityRuntime.can_use(id,cooldowns,round_number) and _can_pay(def,ap):
			return {"id":id,"cursor":(index+1)%spenders.size(),"mode":"spend"}
	return {"id":"","cursor":spend_cursor,"mode":"none"}

static func _can_pay(definition: Dictionary, ap: int) -> bool:
	if bool(definition.get("consume_all_ap",false)):
		return ap >= int(definition.get("min_ap_cost",0))
	return ap >= int(definition.get("ap_cost",0))
