"""Offline combat/feedback regressions; no Studio or rendering assertions."""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--luau", default="luau")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
files = {
    "ArmorConfig": "src/shared/ArmorEnchantConfig.lua",
    "Armor": "src/server/ArmorEnchantService.lua",
    "Feedback": "src/server/EnchantHitFeedback.lua",
    "Motion": "src/shared/EnchantHitEffectMotion.lua",
    "Config": "src/shared/EnchantHitEffectConfig.lua",
    "Effects": "src/client/EnchantHitEffects.lua",
    "Damage": "src/server/DamageService.lua",
    "Mob": "src/server/MobClass.lua",
    "Spec": "tests/enchant_hits.spec.luau",
}
chunks = ["local sources = {}"]
for name, path in files.items():
    source = (repo / path).read_text(encoding="utf-8-sig")
    assert "]====]" not in source
    chunks.append(f'sources["{name}"] = [====[\n{source}\n]====]')
chunks.append('assert(loadstring(sources.Spec, "enchant_hits.spec"))()(sources)')
with tempfile.TemporaryDirectory(prefix="haruka-enchant-") as directory:
    bundle = Path(directory) / "tests.luau"
    bundle.write_text("\n".join(chunks), encoding="utf-8")
    result = subprocess.run([args.luau, str(bundle)], check=False)
raise SystemExit(result.returncode)
