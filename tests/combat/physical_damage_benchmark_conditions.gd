class_name PhysicalDamageBenchmarkConditions
extends RefCounted

## TEST ONLY. Prepare approved full-charge and previous-round prerequisites
## without modifying any production ABI/EFF definition or combat calculation.
const FULL_CHARGE_EFF := {
	"ABI304":["EFF314","self"], "ABI308":["EFF314","self"],
	"ABI312":["EFF314","self"], "ABI316":["EFF314","self"],
	"ABI404":["EFF406","self"],
	"ABI407":["EFF408","self"], "ABI408":["EFF408","self"],
	"ABI410":["EFF401","target"], "ABI411":["EFF401","target"], "ABI412":["EFF401","target"],
	"ABI504":["EFF501","target"], "ABI508":["EFF501","target"],
	"ABI512":["EFF501","target"], "ABI515":["EFF501","target"],
	"ABI516":["EFF501","target"], "ABI608":["EFF601","target"]
}

static func prime_charges(ability_id: String, actor: CombatantState, target: CombatantState, effect_catalog: Dictionary, round_number: int) -> bool:
	if not FULL_CHARGE_EFF.has(ability_id):
		return true
	var pair: Array = FULL_CHARGE_EFF[ability_id]
	var effect_id := String(pair[0])
	var owner: CombatantState = actor if String(pair[1])=="self" else target
	if owner==null or actor==null:
		return false
	var definition: Dictionary = effect_catalog.get(effect_id,{})
	if definition.is_empty():
		return false
	var cap := int(definition.get("max_stacks",0))
	if cap <= 0:
		return false
	# Re-prime only the tracked EFF; unrelated active effects are retained.
	for record in owner.active_effects.duplicate():
		if String(Dictionary(record).get("effect_id",""))==effect_id and (
			owner==actor or String(Dictionary(record).get("source_id",""))==actor.combatant_id
		):
			owner.active_effects.erase(record)
	owner.active_effects.append({
		"effect_id":effect_id,
		"definition":definition.duplicate(true),
		"source_id":actor.combatant_id,
		"start_round":round_number,
		"remaining_rounds":maxi(2,int(definition.get("duration_rounds",2))),
		"stacks":cap,
		"active_stacks":cap,
		"revealed":true
	})
	return true

static func prime_previous_round(state: CombatState, actor_id: String, trigger: String) -> bool:
	if trigger.is_empty():
		return true
	if state.round_number < 2:
		return false
	var source := actor_id
	var target := actor_id
	var kind := CombatEvent.Kind.ATTACK
	var result: Dictionary = {}
	match trigger:
		"dodge":
			source = "benchmark_trigger_only"
			result = {"outcome":"dodge"}
		"block":
			source = "benchmark_trigger_only"
			result = {"outcome":"manual_block"}
		"crit":
			target = "benchmark_trigger_only"
			result = {"outcome":"connected","critical":true}
		"crit_or_block_crush":
			target = "benchmark_trigger_only"
			result = {"outcome":"connected","critical":true}
		"damage_dealt":
			target = "benchmark_trigger_only"
			kind = CombatEvent.Kind.DAMAGE
			result = {"final_damage":1}
		"damage_taken":
			source = "benchmark_trigger_only"
			kind = CombatEvent.Kind.DAMAGE
			result = {"final_damage":1}
		_:
			return false
	# Historical eligibility marker only; never queue as an actual attack.
	# This event has no is_weapon_attack, no dealt HP and no normal damage event.
	var marker := state.create_event(kind,source,target,{"benchmark_trigger":true})
	marker.payload["round"]=state.round_number-1
	marker.result=result
	state.record_event(marker)
	return true
