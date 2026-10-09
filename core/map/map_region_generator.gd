class_name MapRegionGenerator
extends RefCounted

const MAX_REGIONS_PER_400_CELLS := 3
const REGION_TYPES := [
	{"id":"bandit_camp", "chance":0.20, "priority":10},
	{"id":"graveyard", "chance":0.05, "priority":10},
	{"id":"beast_den", "chance":0.25, "priority":10},
	{"id":"ruins", "chance":0.15, "priority":10}
]
