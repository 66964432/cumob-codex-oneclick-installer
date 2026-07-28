import json
import os
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("merge_auth.py requires an auth.json path.", file=sys.stderr)
        return 2

    api_key = os.environ.get("CUMOB_INSTALL_API_KEY", "")
    if not api_key:
        return 0

    auth_path = Path(sys.argv[1])
    auth = {}
    if auth_path.exists():
        parsed = json.loads(auth_path.read_text(encoding="utf-8"))
        if not isinstance(parsed, dict):
            raise ValueError(f"{auth_path} must contain a JSON object.")
        auth = parsed

    auth["OPENAI_API_KEY"] = api_key
    auth_path.parent.mkdir(parents=True, exist_ok=True)

    temp_path = auth_path.with_name(f"{auth_path.name}.cumob-installer-{os.getpid()}.tmp")
    temp_path.write_text(
        json.dumps(auth, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    os.chmod(temp_path, 0o600)
    temp_path.replace(auth_path)
    os.chmod(auth_path, 0o600)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
