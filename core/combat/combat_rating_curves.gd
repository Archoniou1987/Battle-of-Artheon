class_name CombatRatingCurves
extends RefCounted

## Canonical mathematical curves shared by Combat Engine and item generator v1.2.
## Armour is an absolute rating with level-based ageing; ordinary PAR ratings
## use RatingMatrix. Diminishing applies after all relevant reductions.
const DR_RULES := {
	"armour":{"threshold":30.0,"cap":85.1,"smooth":1.5},
	"dodge":{"threshold":15.0,"cap":80.0,"smooth":1.5},
	"crit":{"threshold":20.0,"cap":100.0,"smooth":1.5},
	"crit_damage":{"threshold":50.0,"cap":250.0,"smooth":1.0},
	"reduce":{"threshold":5.0,"cap":35.0,"smooth":1.0},
	"magic_res":{"threshold":30.0,"cap":85.1,"smooth":1.5},
	"block":{"threshold":20.0,"cap":75.0,"smooth":1.5},
	"attack":{"threshold":75.0,"cap":250.0,"smooth":1.0}
}

static func diminishing(raw_pct: float, category: String) -> float:
	var cfg: Dictionary = DR_RULES.get(category,{})
	if cfg.is_empty() or not is_finite(raw_pct):
		return raw_pct
	var threshold := float(cfg["threshold"])
	if raw_pct <= threshold:
		return raw_pct
	var width := float(cfg["cap"]) - threshold
	var smooth := float(cfg["smooth"])
	var x := (raw_pct-threshold)/width
	return threshold + width*x/pow(1.0+pow(x,smooth),1.0/smooth)

## v1.2 100 rating -> 20% (Lv1), 4% (Lv100); keep signed ratings.
static func rating_to_pct(rating: float, level: int) -> float:
	var fraction := float(clampi(level,1,100)-1)/99.0
	return rating/100.0*lerpf(20.0,4.0,fraction)

static func armour_raw_pct(armour_rating: float, level: int) -> float:
	var age := 1.0 + 3.0*float(clampi(level,1,100)-1)/99.0
	return maxf(0.0,armour_rating)/(2.0*age)
