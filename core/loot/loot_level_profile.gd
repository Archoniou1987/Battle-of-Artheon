class_name LootLevelProfile
extends RefCounted

const PROFILES := {
	"normal":{"min_offset":-5,"max_offset":0},
	"elite":{"min_offset":-2,"max_offset":3},
	"boss":{"min_offset":0,"max_offset":5}
}

static func range_for(source_level:int, rank:String, override_rule:Dictionary={}) -> Dictionary:
	var rule:Dictionary=override_rule if not override_rule.is_empty() else PROFILES.get(rank,PROFILES["normal"])
	return {"min":maxi(1,source_level+int(rule.get("min_offset",0))),"max":maxi(1,source_level+int(rule.get("max_offset",0)))}
