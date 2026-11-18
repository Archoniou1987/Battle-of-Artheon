#!/usr/bin/env python3
"""Aggregate canonical physical 1v1 duel CSVs; no gameplay formulas changed."""
import csv
import json
import pathlib
import sys
from collections import defaultdict

ARCHETYPES = [
    "SWORD_DEF", "SWORD_DODGE", "SWORD_CRIT",
    "DAGGER_DEF", "DAGGER_ATTACK", "DAGGER_PEN",
    "AXE_DEF", "AXE_ATTACK", "AXE_SHIELD", "2H_AXE",
    "HAMMER_DEF", "HAMMER_ATTACK", "2H_HAMMER",
    "2H_SPEAR", "2H_SWORD",
]
EXPECTED_PAIRS = len(ARCHETYPES) * (len(ARCHETYPES) - 1) // 2
EXPECTED_BATTLES = 50
FIELDS = [
    "pair_index", "archetype_a", "archetype_b", "battles",
    "wins_a", "wins_b", "draws", "timeouts", "avg_rounds",
    "avg_survivor_hp_a", "avg_survivor_hp_b", "abi_casts_a", "abi_casts_b",
]


def main():
    root = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path("test-results/physical-archetype-duels")
    output = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else root
    files = sorted(root.rglob("duels_*.csv"))
    if not files:
        raise SystemExit(f"No physical duel CSVs under {root}")
    rows = []
    for path in files:
        with path.open(newline="", encoding="utf-8") as stream:
            reader = csv.DictReader(stream)
            if reader.fieldnames != FIELDS:
                raise ValueError(f"Unexpected CSV schema in {path}: {reader.fieldnames}")
            # Each shard uploads its 2-fight smoke CSV alongside 50-fight output.
            # Ignore smoke rows rather than counting them as tournament matchups.
            rows.extend(dict(row) for row in reader if int(row["battles"]) == EXPECTED_BATTLES)
    if len(rows) != EXPECTED_PAIRS:
        raise ValueError(f"Expected {EXPECTED_PAIRS} pairing rows, found {len(rows)}")
    by_pair = {}
    for row in rows:
        idx = int(row["pair_index"])
        if idx in by_pair:
            raise ValueError(f"Duplicate pair_index: {idx}")
        a = row["archetype_a"]
        b = row["archetype_b"]
        if a not in ARCHETYPES or b not in ARCHETYPES or a == b:
            raise ValueError(f"Invalid pair {a}/{b}")
        counts = [int(row[k]) for k in ("wins_a", "wins_b", "draws", "timeouts")]
        battles = int(row["battles"])
        if battles != EXPECTED_BATTLES or sum(counts) != battles:
            raise ValueError(f"Invalid battle counts at {idx}: {counts}/{battles}")
        by_pair[idx] = row
    if set(by_pair) != set(range(EXPECTED_PAIRS)):
        raise ValueError("Pair indices do not cover 0..104")
    stats = {
        name: dict(archetype=name, wins=0, losses=0, draws=0, timeouts=0,
                   fights=0, rounds_weighted=0.0, surviving_hp_weighted=0.0,
                   abi_casts=0, pairs_won=0, pairs_lost=0, pairs_tied=0)
        for name in ARCHETYPES
    }
    matrix = {name: {other: "" for other in ARCHETYPES} for name in ARCHETYPES}
    for index in sorted(by_pair):
        row = by_pair[index]
        a, b = row["archetype_a"], row["archetype_b"]
        wa, wb = int(row["wins_a"]), int(row["wins_b"])
        draws, timeouts = int(row["draws"]), int(row["timeouts"])
        avg_rounds = float(row["avg_rounds"])
        for me, wins, losses, hp, casts in [
            (a, wa, wb, float(row["avg_survivor_hp_a"]), int(row["abi_casts_a"])),
            (b, wb, wa, float(row["avg_survivor_hp_b"]), int(row["abi_casts_b"])),
        ]:
            s = stats[me]
            s["wins"] += wins
            s["losses"] += losses
            s["draws"] += draws
            s["timeouts"] += timeouts
            s["fights"] += EXPECTED_BATTLES
            s["rounds_weighted"] += avg_rounds * EXPECTED_BATTLES
            s["surviving_hp_weighted"] += hp * EXPECTED_BATTLES
            s["abi_casts"] += casts
            s["pairs_won"] += wins > losses
            s["pairs_lost"] += wins < losses
            s["pairs_tied"] += wins == losses
        matrix[a][b] = f"{wa}-{wb}"
        matrix[b][a] = f"{wb}-{wa}"
    rankings = []
    for s in stats.values():
        fights = s["fights"]
        rankings.append({
            "archetype": s["archetype"], "wins": s["wins"],
            "losses": s["losses"], "draws": s["draws"],
            "timeouts": s["timeouts"], "fights": fights,
            "win_pct": round(100 * s["wins"] / fights, 2),
            "nonloss_pct": round(100 * (s["wins"] + s["draws"] / 2) / fights, 2),
            "avg_rounds": round(s["rounds_weighted"] / fights, 2),
            "avg_remaining_hp": round(s["surviving_hp_weighted"] / fights, 2),
            "abi_casts_per_fight": round(s["abi_casts"] / fights, 2),
            "pairs_won": s["pairs_won"], "pairs_lost": s["pairs_lost"],
            "pairs_tied": s["pairs_tied"],
        })
    rankings.sort(key=lambda r: (-r["nonloss_pct"], -r["win_pct"], r["archetype"]))
    output.mkdir(parents=True, exist_ok=True)
    with (output / "pvp_rankings.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rankings[0].keys()))
        writer.writeheader()
        writer.writerows(rankings)
    with (output / "pvp_matchup_matrix.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(["archetype"] + ARCHETYPES)
        for a in ARCHETYPES:
            writer.writerow([a] + [matrix[a][b] for b in ARCHETYPES])
    with (output / "pvp_pairs.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=FIELDS)
        writer.writeheader()
        for index in sorted(by_pair):
            writer.writerow(by_pair[index])
    result = dict(pairs=EXPECTED_PAIRS, fights=EXPECTED_PAIRS * EXPECTED_BATTLES,
                  rankings=rankings, total_timeouts=sum(int(r["timeouts"]) for r in rows),
                  total_draws=sum(int(r["draws"]) for r in rows))
    (output / "pvp_summary.json").write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"PHYSICAL_DUEL_AGGREGATE=PASS pairs={EXPECTED_PAIRS} fights={result['fights']} "
          f"timeouts={result['total_timeouts']} draws={result['total_draws']}")
    for r in rankings:
        print(f"PVP_RANK={r['archetype']} wins={r['wins']}/{r['fights']} "
              f"win_pct={r['win_pct']} avg_rounds={r['avg_rounds']}")


if __name__ == "__main__":
    main()
