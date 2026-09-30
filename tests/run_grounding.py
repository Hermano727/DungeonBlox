"""Run grounding regressions without launching Studio (requires the Luau CLI)."""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--luau", default="luau", help="Path to the Luau CLI executable")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
files = {
    "CharacterGrounding": "src/shared/CharacterGrounding.lua",
    "CharacterGroundState": "src/client/CharacterGroundState.lua",
    "Server": "src/server/CharacterGrounding.server.lua",
    "Bootstrap": "src/client/CharacterGroundStateBootstrap.client.lua",
    "Spec": "tests/grounding.spec.luau",
}
chunks = ["local sources = {}"]
for name, path in files.items():
    source = (repo / path).read_text(encoding="utf-8-sig")
    assert "]====]" not in source
    chunks.append(f'sources["{name}"] = [====[\n{source}\n]====]')
chunks.append('assert(loadstring(sources.Spec, "grounding.spec"))()(sources)')
with tempfile.TemporaryDirectory(prefix="haruka-grounding-") as directory:
    bundle = Path(directory) / "tests.luau"
    bundle.write_text("\n".join(chunks), encoding="utf-8")
    result = subprocess.run([args.luau, str(bundle)], check=False)
raise SystemExit(result.returncode)
