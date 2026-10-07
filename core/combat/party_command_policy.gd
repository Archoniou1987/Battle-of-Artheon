class_name PartyCommandPolicy
extends RefCounted

## Commands bias companion AI without bypassing combat rules.
## The AI still resolves actions through the same ATTACK/ACTION pipelines.

enum Command { AUTO, ATTACK_TARGET, NEED_HEAL, PROTECT }

var commands:Dictionary={}

func clear(companion_id:String)->void:
	commands.erase(companion_id)

func set_auto(companion_id:String)->void:
	commands[companion_id]={"command":Command.AUTO}

func attack_target(companion_id:String,target_id:String)->void:
	commands[companion_id]={"command":Command.ATTACK_TARGET,"target_id":target_id}

func need_heal(companion_id:String,ally_id:String)->void:
	commands[companion_id]={"command":Command.NEED_HEAL,"target_id":ally_id}

func protect(companion_id:String,ally_id:String)->void:
	commands[companion_id]={"command":Command.PROTECT,"target_id":ally_id}

func command_for(companion_id:String)->Dictionary:
	return commands.get(companion_id,{"command":Command.AUTO}).duplicate(true)

func ability_priority_bonus(companion_id:String,ability:Dictionary,target_id:String)->int:
	var command:=command_for(companion_id)
	var kind:=int(command.get("command",Command.AUTO))
	var requested:=String(command.get("target_id",""))
	if kind==Command.NEED_HEAL and requested==target_id and String(ability.get("ai_role",""))=="HEAL":
		return 1000
	if kind==Command.PROTECT and requested==target_id and String(ability.get("ai_role",""))=="PROTECT":
		return 1000
	if kind==Command.ATTACK_TARGET and requested==target_id and String(ability.get("ai_role","")) in ["DAMAGE","CONTROL"]:
		return 1000
	return 0
