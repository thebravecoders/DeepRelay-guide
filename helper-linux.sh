#!/usr/bin/env bash
#
# DeepRelay -> Kilo config helper (Linux)
#
# Usage:
#   bash helper-linux.sh
#   DEEPRELAY_API_KEY=deeprelay_live_xxx bash helper-linux.sh
#   KILO_CONFIG_DIR=/path/to/kilo bash helper-linux.sh   # target a specific config dir
#
set -euo pipefail

# --- locate a Python 3 interpreter -------------------------------------------
PY_BIN="${PYTHON:-}"
if [ -z "$PY_BIN" ]; then
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then
      if "$candidate" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' 2>/dev/null; then
        PY_BIN="$candidate"
        break
      fi
    fi
  done
fi

if [ -z "$PY_BIN" ]; then
  echo "error: Python 3 not found. Install it, e.g.:" >&2
  echo "  Debian/Ubuntu : sudo apt install python3" >&2
  echo "  Fedora/RHEL   : sudo dnf install python3" >&2
  echo "  Arch          : sudo pacman -S python" >&2
  exit 1
fi

"$PY_BIN" - <<'PY'
import json
import os
import re
import shutil
import urllib.error
import urllib.request
from pathlib import Path

API_KEY = os.environ.get(
    "DEEPRELAY_API_KEY", "deeprelay_live_Egp1NeJUZHnuWKoYpD4PVk3S"
)
BASE_URL = "https://api.deeprelay.ai/v1"

# Kilo's config lookup: KILO_CONFIG_DIR, then ~/.config/kilo (XDG-aware),
# then ~/.kilo, then ~/.kilocode.
def resolve_config_path():
    override = os.environ.get("KILO_CONFIG_DIR")
    if override:
        return Path(override).expanduser() / "kilo.jsonc"

    xdg = os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")
    candidates = [
        Path(xdg).expanduser() / "kilo" / "kilo.jsonc",
        Path.home() / ".kilo" / "kilo.jsonc",
        Path.home() / ".kilocode" / "kilo.jsonc",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return candidates[0]


config_path = resolve_config_path()

request = urllib.request.Request(
    f"{BASE_URL}/models",
    headers={"Authorization": f"Bearer {API_KEY}"},
)

try:
    with urllib.request.urlopen(request, timeout=30) as response:
        catalog = json.load(response)
except urllib.error.HTTPError as exc:
    raise SystemExit(f"API error {exc.code}: {exc.reason}. Configuration unchanged.")
except urllib.error.URLError as exc:
    raise SystemExit(f"Network error: {exc.reason}. Configuration unchanged.")

model_ids = sorted({item["id"] for item in catalog.get("data", []) if item.get("id")})

if not model_ids:
    raise SystemExit("No models returned. Configuration unchanged.")


def load_jsonc(text):
    """Parse JSON that may contain // and /* */ comments and trailing commas."""
    without_comments = re.sub(
        r'("(?:\\.|[^"\\])*")|//[^\n]*|/\*.*?\*/',
        lambda m: m.group(1) or "",
        text,
        flags=re.S,
    )
    cleaned = re.sub(r",(\s*[}\]])", r"\1", without_comments)
    return json.loads(cleaned)


# Preserve existing settings and create a backup.
backup_path = config_path.with_suffix(".jsonc.bak")
if config_path.exists():
    shutil.copy2(config_path, backup_path)
    try:
        config = load_jsonc(config_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(
            f"Could not parse {config_path}: {exc}. Backup kept at {backup_path}."
        )
else:
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config = {"$schema": "https://app.kilo.ai/config.json"}

provider = config.setdefault("provider", {}).setdefault("deeprelay", {})
provider["npm"] = "@ai-sdk/openai-compatible"
provider["name"] = "DeepRelay"

options = provider.setdefault("options", {})
options["apiKey"] = API_KEY
options["baseURL"] = BASE_URL

models = provider.setdefault("models", {})

# Models that are not text/coding capable - no tool calling for these.
NON_TEXT = (
    "image", "flux", "seedance", "seedream", "happyhorse",
    "vidu", "wan2", "pixverse", "embedding",
)

for model_id in model_ids:
    name = model_id.split("/")[-1].replace("-", " ").replace(".", " ").title()

    entry = models.setdefault(model_id, {})
    entry["name"] = name

    if not any(word in model_id.lower() for word in NON_TEXT):
        entry["tool_call"] = True

# Keep the currently working default model.
config.setdefault("model", "deeprelay/deeprelay/deepseek-v4-pro")

config_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
os.chmod(config_path, 0o600)

print(f"Added/updated {len(model_ids)} models.")
print(f"Configuration: {config_path}")
if backup_path.exists():
    print(f"Backup: {backup_path}")
print("Restart Kilo and run /models to check the list.")
PY
