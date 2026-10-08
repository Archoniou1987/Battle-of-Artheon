class_name ExpeditionProfile
extends RefCounted

const LIFETIME_PERSISTENT:="persistent"
const LIFETIME_TIME_LIMITED:="time_limited"
const DEATH_STANDARD:="standard"
const EXIT_FREE:="free_exit"
const EXPIRATION_CLOSE:="close"

var profile_id:String
var width:int
var height:int
var energy_cost:int
var difficulty_id:String
var lifetime_policy:String
var death_policy:String
var exit_policy:String
var grace_period_seconds:int
var expiration_outcome:String

func _init(
	p_profile_id:String="standard",
	p_width:int=20,
	p_height:int=20,
	p_energy_cost:int=10,
	p_difficulty_id:String="normal",
	p_lifetime_policy:String=LIFETIME_PERSISTENT,
	p_death_policy:String=DEATH_STANDARD,
	p_exit_policy:String=EXIT_FREE,
	p_grace_period_seconds:int=0,
	p_expiration_outcome:String=EXPIRATION_CLOSE
)->void:
	profile_id=p_profile_id
	width=maxi(1,p_width)
	height=maxi(1,p_height)
	energy_cost=maxi(0,p_energy_cost)
	difficulty_id=p_difficulty_id
	lifetime_policy=p_lifetime_policy
	death_policy=p_death_policy
	exit_policy=p_exit_policy
	grace_period_seconds=maxi(0,p_grace_period_seconds)
	expiration_outcome=p_expiration_outcome

func to_dict()->Dictionary:
	return {
		"profile_id":profile_id,
		"width":width,
		"height":height,
		"energy_cost":energy_cost,
		"difficulty_id":difficulty_id,
		"lifetime_policy":lifetime_policy,
		"death_policy":death_policy,
		"exit_policy":exit_policy,
		"grace_period_seconds":grace_period_seconds,
		"expiration_outcome":expiration_outcome
	}

static func from_dict(data:Dictionary)->ExpeditionProfile:
	return ExpeditionProfile.new(
		String(data.get("profile_id","standard")),
		int(data.get("width",20)),
		int(data.get("height",20)),
		int(data.get("energy_cost",10)),
		String(data.get("difficulty_id","normal")),
		String(data.get("lifetime_policy",LIFETIME_PERSISTENT)),
		String(data.get("death_policy",DEATH_STANDARD)),
		String(data.get("exit_policy",EXIT_FREE)),
		int(data.get("grace_period_seconds",0)),
		String(data.get("expiration_outcome",EXPIRATION_CLOSE))
	)
