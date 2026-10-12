"""Search Roblox's licensed sound libraries (Pro Sound Effects, APM) through the public toolbox API.

    python tools/sfx_search.py "keyword" [max_seconds] [count]

Prints id, duration, name and the first line of the library description for each hit. Only these
two creators: both libraries are licensed by Roblox for every experience, unlike random uploads
(which are often ripped from other games). Audio is toolbox category 3; the creator filter is
creatorTargetId + creatorType 1. Pick by description, then AUDITION before shipping.
"""
import json
import sys
import urllib.parse
import urllib.request

CREATORS = {"PSE": 7462895450, "APM": 7462718749}


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode("utf-8"))


def search(keyword, creator_id, count):
    q = urllib.parse.urlencode({"keyword": keyword, "num": count, "creatorTargetId": creator_id, "creatorType": 1})
    data = get(f"https://apis.roblox.com/toolbox-service/v1/marketplace/3?{q}")
    return [d["id"] for d in data.get("data", [])]


def details(ids):
    out = []
    for i in range(0, len(ids), 30):
        chunk = ",".join(str(x) for x in ids[i:i + 30])
        out += get(f"https://apis.roblox.com/toolbox-service/v1/items/details?assetIds={chunk}").get("data", [])
    return out


keyword = sys.argv[1]
max_seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 99
count = int(sys.argv[3]) if len(sys.argv) > 3 else 12
for label, cid in CREATORS.items():
    ids = search(keyword, cid, count)
    for item in details(ids):
        a = item["asset"]
        if item["creator"]["id"] != cid:
            continue
        dur = a.get("duration") or 0
        if dur > max_seconds:
            continue
        desc = (a.get("description") or "").split("\n")[0][:110]
        print(f"{label} {a['id']:>14} {dur:5.1f}s  {a['name'][:42]:42} | {desc}")
