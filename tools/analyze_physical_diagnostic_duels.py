#!/usr/bin/env python3
"""Read real round-by-round CombatEngine traces and audit damage/block mechanics."""
import json
from collections import Counter, defaultdict
from pathlib import Path

def side(name):
    return "AXE_DEF" if name == "DUEL_A" else "DAGGER"

def analyze(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    dagger = data["archetype_b"]
    all_events = [e for r in data["rounds"] for e in r["events"]]
    attack_by_side = defaultdict(Counter)
    dmg_by_side = defaultdict(Counter)
    dmg_source = defaultdict(Counter)
    eff_by_side = defaultdict(Counter)
    abi_by_side = defaultdict(Counter)
    heals = defaultdict(Counter)
    blocked_damage = defaultdict(int)
    blocked_events = defaultdict(int)
    for e in all_events:
        s = side(e["source"])
        result, intent, kind = e["result"], e["intent"], e["kind"]
        if kind == "ATTACK":
            outcome = result.get("outcome", "unknown")
            attack_by_side[s][outcome] += 1
            partial = result.get("partial_block", "")
            if partial:
                attack_by_side[s]["partial_"+partial] += 1
                blocked_events[s] += 1
        elif kind == "DAMAGE":
            damage = int(result.get("final_damage", 0))
            dmg_by_side[s]["total"] += damage
            typ = intent.get("source","attack")
            dmg_source[s][typ] += damage
            if int(e.get("parent",-1)) >= 0:
                pass
        elif kind == "ACTION":
            abi = intent.get("ability_id", "")
            if abi:
                abi_by_side[s][abi] += 1
        elif kind == "EFFECT":
            eff = intent.get("effect_id", "")
            if eff:
                eff_by_side[s][eff] += 1
            h = int(result.get("healed",0))
            if h:
                heals[s][intent.get("ability_id") or eff or "unknown"] += h
    print(f"\n=== {dagger}: {data['result']['rounds']} rounds; winner={data['result']['outcome']} ===")
    print("ATTACK OUTCOMES",json.dumps({k:dict(v) for k,v in attack_by_side.items()},ensure_ascii=False,sort_keys=True))
    print("DAMAGE TOTALS",json.dumps({k:dict(v) for k,v in dmg_source.items()},ensure_ascii=False,sort_keys=True))
    print("ABI CASTS",json.dumps({k:dict(v) for k,v in abi_by_side.items()},ensure_ascii=False,sort_keys=True))
    print("EFF EVENTS",json.dumps({k:dict(v) for k,v in eff_by_side.items()},ensure_ascii=False,sort_keys=True))
    print("HEALING SOURCES",json.dumps({k:dict(v) for k,v in heals.items()},ensure_ascii=False,sort_keys=True))
    print("ROUND DETAIL columns: n A_hp B_hp A_AP B_AP A_damage B_damage A_heal B_heal A_blocks B_blocks A_ABI B_ABI A_effects B_effects")
    for r in data["rounds"]:
        actor_events = defaultdict(list)
        for e in r["events"]:
            actor_events[side(e["source"])].append(e)
        def damage(s):
            return sum(int(e["result"].get("final_damage",0)) for e in actor_events[s] if e["kind"]=="DAMAGE")
        def healed(s):
            return sum(int(e["result"].get("healed",0)) for e in actor_events[s] if e["kind"]=="EFFECT")
        def blocks(s):
            return sum(1 for e in r["events"] if e["kind"]=="ATTACK" and side(e["target"])==s and (e["result"].get("partial_block") or e["result"].get("outcome") in ("manual_block","auto_block")))
        abis=r["selected_abilities"]
        st=r["state"]
        def effects(k):
            return ",".join(f"{e.get('effect_id')}x{e.get('stacks',1)}" for e in st[k])
        print("ROUND",r["round"],
            "A",st["A_hp"],"B",st["B_hp"],"AP",st["A_ap"],st["B_ap"],
            "damage",damage("AXE_DEF"),damage("DAGGER"),
            "heal",healed("AXE_DEF"),healed("DAGGER"),
            "blocks",blocks("AXE_DEF"),blocks("DAGGER"),
            "ABI",abis.get("DUEL_A","-"),abis.get("DUEL_B","-"),
            "effects",effects("A_effects"),"|",effects("B_effects"))
    for r in data["rounds"]:
        for e in r["events"]:
            if e["kind"] in ("ATTACK","DAMAGE","EFFECT"):
                intent,result=e["intent"],e["result"]
                if e["kind"]=="ATTACK" and result.get("outcome","") in ("connected","manual_block","auto_block","dodge"):
                    print("EVENT",r["round"],e["id"],e["kind"],side(e["source"]),"->",side(e["target"]),
                          "abi",intent.get("axe_abi_id") or intent.get("combo_abi_id") or intent.get("ability_id") or ("BASIC" if intent.get("is_weapon_attack") else "-"),
                          "outcome",result.get("outcome"),"block",result.get("partial_block",""),
                          "raw",result.get("raw_damage",""),"after_armour",result.get("after_armour_damage",""),
                          "armour_pct",result.get("armour_after_breach_percent",""),
                          "crit",result.get("critical",""),"zone",intent.get("zone",""))
                if e["kind"]=="EFFECT" and int(result.get("healed",0))>0:
                    print("HEAL_EVENT",r["round"],e["id"],side(e["target"]),"amount",result["healed"],
                          "from",intent.get("ability_id",""),intent.get("effect_id",""))
    print("TRACE_EVENTS",len(all_events))

paths=sorted(Path("test-results/physical-diagnostic").glob("*.json"))
if len(paths)!=2:
    raise SystemExit(f"Expected 2 full traces, got {len(paths)}")
for path in paths:
    analyze(path)
