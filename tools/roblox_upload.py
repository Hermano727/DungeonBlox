"""Upload a model (.fbx), an animation (.rbxmx KeyframeSequence) or a sound (.mp3/.ogg) to Roblox
through Open Cloud.

    python tools/roblox_upload.py <file> <displayName> ["description"]

Reads ASSET_API_KEY from the repo's .env (never printed or written anywhere). Creator is the
experience owner, userId 706604079. Asset type comes from the extension: .fbx -> Model,
.rbxm/.rbxmx -> Animation, .mp3/.ogg -> Audio, .png -> Decal
(its image id: InsertService:LoadAsset(decalId) in Studio, then the Decal's Texture). Prints one line: RESULT {"assetId": ..., "error": ...}, and writes
the same JSON next to the uploaded file as <file>.upload.json.
"""
import json, os, re, sys, time, uuid, urllib.request, urllib.error
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
USER_ID = "706604079"
TYPES = {".fbx": ("Model", "model/fbx"), ".rbxm": ("Animation", "model/x-rbxm"), ".rbxmx": ("Animation", "model/x-rbxm"),
         ".mp3": ("Audio", "audio/mpeg"), ".ogg": ("Audio", "audio/ogg"),
         ".png": ("Decal", "image/png")}


def api_key():
    env = (ROOT / ".env").read_text(encoding="utf-8-sig")
    match = re.search(r"^\s*ASSET_API_KEY\s*=\s*(.*?)\s*$", env, re.M)
    if not match:
        raise SystemExit("ASSET_API_KEY is not configured in .env")
    return match.group(1).strip().strip("\"'")


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    path = Path(sys.argv[1]).resolve()
    name = sys.argv[2]
    description = sys.argv[3] if len(sys.argv) > 3 else name
    asset_type, mime = TYPES[path.suffix.lower()]
    key = api_key()
    request = {"assetType": asset_type, "displayName": name, "description": description,
               "creationContext": {"creator": {"userId": USER_ID}}}
    boundary = "DungeonBlox" + uuid.uuid4().hex
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\nContent-Type: application/json\r\n\r\n"
            f"{json.dumps(request)}\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; "
            f"filename=\"{path.name}\"\r\nContent-Type: {mime}\r\n\r\n").encode() + path.read_bytes() + f"\r\n--{boundary}--\r\n".encode()

    def call(url, data=None):
        headers = {"x-api-key": key}
        if data is not None:
            headers["Content-Type"] = "multipart/form-data; boundary=" + boundary
        try:
            with urllib.request.urlopen(urllib.request.Request(url, data=data, headers=headers), timeout=120) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            details = error.read().decode(errors="replace").replace(key, "[redacted]")
            return {"done": True, "error": {"status": error.code, "details": details[:1500]}}

    result = call("https://apis.roblox.com/assets/v1/assets", body)
    operation = result.get("path")
    for _ in range(40):
        if result.get("done") or not operation:
            break
        time.sleep(3)
        result = call("https://apis.roblox.com/assets/v1/" + operation)
    summary = {"assetId": (result.get("response") or {}).get("assetId"), "error": result.get("error"), "done": result.get("done")}
    Path(str(path) + ".upload.json").write_text(json.dumps(result, indent=2))
    print("RESULT", json.dumps(summary))


if __name__ == "__main__":
    main()
