
python3 <<'PY'
import json
import os
import shutil
import urllib.request
from pathlib import Path

config_path = Path.home() / ".config/kilo/kilo.jsonc"
api_key = "deeprelay_live_Egp1NeJUZHnuWKoYpD4PVk3S"

request = urllib.request.Request(
    "https://api.deeprelay.ai/v1/models",
    headers={"Authorization": f"Bearer {api_key}"},
)

with urllib.request.urlopen(request, timeout=30) as response:
    catalog = json.load(response)

model_ids = sorted({
    item["id"] for item in catalog["data"] if item.get("id")
})

if not model_ids:
    raise SystemExit("No models returned. Configuration unchanged.")

# Preserve existing settings and create a backup.
if config_path.exists():
    shutil.copy2(
        config_path,
        config_path.with_suffix(".jsonc.bak")
    )
    config = json.loads(config_path.read_text())
else:
    config = {"$schema": "https://app.kilo.ai/config.json"}

provider = config.setdefault("provider", {}).setdefault("deeprelay", {})
provider["npm"] = "@ai-sdk/openai-compatible"
provider["name"] = "DeepRelay"

options = provider.setdefault("options", {})
options["apiKey"] = api_key
options["baseURL"] = "https://api.deeprelay.ai/v1"

models = provider.setdefault("models", {})

for model_id in model_ids:
    name = model_id.split("/")[-1]
    name = name.replace("-", " ").replace(".", " ").title()

    entry = models.setdefault(model_id, {})
    entry["name"] = name

    # Enable tool calling only for likely text/coding models.
    non_text = (
        "image", "flux", "seedance", "seedream", "happyhorse",
        "vidu", "wan2", "pixverse", "embedding"
    )
    if not any(word in model_id.lower() for word in non_text):
        entry["tool_call"] = True

# Keep the currently working default model.
config.setdefault("model", "deeprelay/deeprelay/deepseek-v4-pro")

config_path.write_text(json.dumps(config, indent=2) + "\n")

print(f"Added/updated {len(model_ids)} models.")
print(f"Configuration: {config_path}")
print(f"Backup: {config_path.with_suffix('.jsonc.bak')}")
print("Restart Kilo and run /models to check the list.")
PY
