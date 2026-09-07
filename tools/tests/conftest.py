import sys
from pathlib import Path

# tools/ is not a package; put it on the path so the scripts import by name.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

REPO_ROOT = Path(__file__).resolve().parents[2]
