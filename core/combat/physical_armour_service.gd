class_name PhysicalArmourService
extends RefCounted

## Materialise the complete 5-zone x 4-type physical armour matrix.
## The caller provides structural/base armour; canonical PAR totals already
## include item armour_by_zone and armour_all_zones_all_physical exactly once.
## PAR127-130 are global typed armour, added to every zone here.
static func assemble(base_armour: Dictionary, totals: Dictionary) -> Dictionary:
	var result := base_armour.duplicate(true)
	var zones := EquipmentBuilder.HIT_ZONES
	var types := EquipmentBuilder.PHYSICAL_TYPES
	for zone_index in range(zones.size()):
		var zone: String = zones[zone_index]
		var zone_armour: Dictionary = Dictionary(result.get(zone, {})).duplicate(true)
		var general_id := "PAR%03d" % (100 + zone_index)
		for type_index in range(types.size()):
			var damage_type: String = types[type_index]
			var zoned_id := "PAR%03d" % (105 + zone_index * types.size() + type_index)
			var global_id := "PAR%03d" % (127 + type_index)
			zone_armour[damage_type] = (
				float(zone_armour.get(damage_type, 0.0))
				+ float(totals.get(general_id, 0.0))
				+ float(totals.get(zoned_id, 0.0))
				+ float(totals.get(global_id, 0.0))
			)
		result[zone] = zone_armour
	return result
