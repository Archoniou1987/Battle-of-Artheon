class_name PhysicalDamageBenchmarkPolicy
extends RefCounted

## BENCHMARK ONLY. Generator ABI (zero AP cost) is cast on cooldown when AP
## is not full. All other ABI form a STRICT cycle in their equipment order.
## Never skip the next spender for an affordable later spender. If the next
## one needs AP/CD, accumulate/wait; cursor advances only after a real cast.
static func choose(abilities: Array, definitions: Dictionary, cooldowns: Dictionary, round_number: int, ap: int, max_ap: int, spend_cursor: int) -> Dictionary:
	var generators: Array[String] = []
	var spenders: Array[String] = []
	for raw in abilities:
		var id := String(raw)
		var definition: Dictionary = definitions.get(id,{})
		if definition.is_empty():
			continue
		if int(definition.get("ap_cost",0)) == 0 and not bool(definition.get("consume_all_ap",false)) and (int(definition.get("ap_gain",0)) > 0 or bool(definition.get("ap_gain_on_hit",false))):
			generators.append(id)
		else:
			spenders.append(id)
	for id in generators:
		var def: Dictionary = definitions.get(id,{})
		if AbilityRuntime.can_use(id,cooldowns,round_number) and ap < max_ap and _can_pay(def,ap):
			return {"id":id,"cursor":spend_cursor,"mode":"gain"}
	if spenders.is_empty():
		return {"id":"","cursor":spend_cursor,"mode":"none"}
	var index := posmod(spend_cursor,spenders.size())
	var id := spenders[index]
	var def: Dictionary = definitions.get(id,{})
	if AbilityRuntime.can_use(id,cooldowns,round_number) and _can_pay(def,ap):
		return {"id":id,"cursor":(index+1)%spenders.size(),"mode":"spend"}
	return {"id":"","cursor":spend_cursor,"mode":"wait_next_spender","waiting_for":id}

static func _can_pay(definition: Dictionary, ap: int) -> bool:
	if bool(definition.get("consume_all_ap",false)):
		return ap >= int(definition.get("min_ap_cost",0))
	return ap >= int(definition.get("ap_cost",0))
