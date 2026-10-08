"""Run potion service regressions without starting Studio (requires the Luau CLI)."""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--luau', default='luau')
parser.add_argument('--bundle', type=Path, help='Write a standalone mock-only test bundle')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
paths = {'Server': 'src/server/PotionService.server.luau',
         'Config': 'src/shared/PotionConfig.lua',
         'Action': 'src/shared/PotionAction.luau',
         'Client': 'src/client/PotionDrinkClient.client.luau',
         'HudClient': 'src/client/PotionClient.client.luau',
         'InputSpec': 'tests/potion_input.spec.luau',
         'Request': 'src/shared/PotionDrinkRequest.luau',
         'RequestSpec': 'tests/potion_request.spec.luau',
         'AnimationSpec': 'tests/potion_animation.spec.luau',
         'Spec': 'tests/potions.spec.luau'}
chunks = ['local sources = {}']
for name, path in paths.items():
    source = (repo / path).read_text(encoding='utf-8-sig')
    assert ']====]' not in source
    chunks.append(f'sources["{name}"] = [====[\n{source}\n]====]')
chunks.append('assert(loadstring(sources.Spec, "potions.spec"))()(sources)')
chunks.append('print("Potion animation regressions passed:", assert(loadstring(sources.AnimationSpec))()(sources.Client))')
chunks.append('print("Potion request regressions passed:", assert(loadstring(sources.RequestSpec))()(sources.Request))')
chunks.append('print("Potion input regressions passed:", assert(loadstring(sources.InputSpec))()(sources.HudClient))')
bundle = '\n'.join(chunks)
if args.bundle:
    args.bundle.write_text(bundle, encoding='utf-8')
else:
    with tempfile.TemporaryDirectory(prefix='haruka-potions-') as directory:
        path = Path(directory) / 'tests.luau'
        path.write_text(bundle, encoding='utf-8')
        raise SystemExit(subprocess.run([args.luau, str(path)], check=False).returncode)
