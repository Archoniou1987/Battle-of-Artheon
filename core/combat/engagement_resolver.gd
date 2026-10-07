class_name EngagementResolver
extends RefCounted

const LOCK_PROTECTED_ROUNDS:=2

var group:GroupCombatState
var pending_requests:Array[Dictionary]=[]
var lock_until_round:Dictionary={}

func _init(group_state:GroupCombatState)->void:
	group=group_state

func request_change(owner_id:String,target_id:String,requester_id:String,requester_kind:String,contest_roll:int=100)->bool:
	if owner_id.is_empty() or requester_id.is_empty():
		return false
	pending_requests.append({
		"owner_id":owner_id,
		"target_id":target_id,
		"requester_id":requester_id,
		"requester_kind":requester_kind.to_upper(),
		"contest_roll":contest_roll
	})
	return true

func request_from_action(event:CombatEvent,owner_id:String,requester_kind:String,contest_roll:int=100)->bool:
	var engagement:Dictionary=event.payload.get("engagement",{})
	if engagement.is_empty() or String(engagement.get("timing","END_ROUND")).to_upper()!="END_ROUND":
		return false
	var target_id:=String(engagement.get("target_id",event.target_id))
	return request_change(owner_id,target_id,event.source_id,requester_kind,contest_roll)

func resolve_end_round(round_number:int)->Dictionary:
	var grouped:Dictionary={}
	for request in pending_requests:
		var owner_id:=String(request.get("owner_id",""))
		if not grouped.has(owner_id): grouped[owner_id]=[]
		grouped[owner_id].append(request)
	var changes:Dictionary={}
	var rejected:Array[Dictionary]=[]
	for owner_id in grouped.keys():
		var requests:Array=grouped[owner_id]
		var valid:Array[Dictionary]=[]
		for request in requests:
			if _valid_request(request,round_number):
				valid.append(request)
			else:
				rejected.append(request)
		if valid.is_empty(): continue
		var winner:=_choose_winner(valid)
		var before:=group.active_opponent(String(owner_id))
		var target_id:=String(winner.get("target_id",""))
		if group.set_active_opponent(String(owner_id),target_id):
			if before!=target_id:
				lock_until_round[String(owner_id)]=round_number+LOCK_PROTECTED_ROUNDS
				changes[String(owner_id)]={"from":before,"to":target_id,"requester_id":winner.get("requester_id",""),"requester_kind":winner.get("requester_kind","")}
	pending_requests.clear()
	return {"changes":changes,"rejected":rejected}

func is_locked(owner_id:String,round_number:int)->bool:
	return round_number<=int(lock_until_round.get(owner_id,-1))

func clear_lock(owner_id:String)->void:
	lock_until_round.erase(owner_id)

func _valid_request(request:Dictionary,round_number:int)->bool:
	var owner_id:=String(request.get("owner_id",""))
	var target_id:=String(request.get("target_id",""))
	var requester_kind:=String(request.get("requester_kind",""))
	if not group.living_enemies(owner_id).has(target_id):
		return false
	if requester_kind!="PLAYER" and is_locked(owner_id,round_number):
		return false
	return true

func _choose_winner(requests:Array[Dictionary])->Dictionary:
	var player_requests:Array[Dictionary]=[]
	var npc_requests:Array[Dictionary]=[]
	for request in requests:
		if String(request.get("requester_kind",""))=="PLAYER":
			player_requests.append(request)
		else:
			npc_requests.append(request)
	if not player_requests.is_empty():
		return player_requests[0]
	var winner:Dictionary=npc_requests[0]
	for request in npc_requests:
		var roll:=int(request.get("contest_roll",100))
		var best:=int(winner.get("contest_roll",100))
		if roll<best or (roll==best and String(request.get("requester_id",""))<String(winner.get("requester_id",""))):
			winner=request
	return winner
