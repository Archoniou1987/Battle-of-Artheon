class_name ArenaTestEquipment
extends RefCounted

## Test instances store only identity, template link and mutable condition.
## Template-owned PAR values live exclusively in data/items/arena_templates.json.
const TEMPLATE_IDS := ["sword_mh", "dagger_oh", "ring_attributes", "ring_defense", "shield"]

static func seed(character: CharacterState, repository: ItemRepository) -> bool:
	var changed := false
	var templates := ItemTemplateService.load_templates()
	for template_id in TEMPLATE_IDS:
		if not templates.has(template_id):
			push_error("ArenaTestEquipment: missing template " + template_id)
			return changed
		var instance_id := "combat_test_v1_" + template_id
		if repository.has_item(instance_id):
			# Existing items keep their individual wear, quality and ownership.
			# No duplicate grants or template-stat copies.
			continue
		var item := {
			"instance_id": instance_id,
			"template_id": template_id,
			"rarity": "green"
		}
		ItemDurabilityService.initialize_item(item, 100)
		if repository.add_item(item):
			character.receive_item(instance_id, repository)
			changed = true
	return changed
