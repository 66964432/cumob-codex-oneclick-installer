#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD_DIR="$SCRIPT_DIR/payload"
DEFAULT_INSTALLER_ARCHIVE_URL="https://github.com/66964432/cumob-codex-oneclick-installer/archive/refs/heads/main.zip"
DEFAULT_SKILL_ARCHIVE_URL="https://github.com/66964432/cumob-image-generation4codex/archive/refs/heads/main.zip"
DEFAULT_MODELS_URL="https://raw.githubusercontent.com/66964432/cumob-codex-oneclick-installer/main/payload/cumob-models.json"
DEFAULT_TEMPLATE_URL="https://raw.githubusercontent.com/66964432/cumob-codex-oneclick-installer/main/payload/cumob-config.template.toml"
DEFAULT_MERGE_AWK_URL="https://raw.githubusercontent.com/66964432/cumob-codex-oneclick-installer/main/scripts/merge-config.awk"
DEFAULT_MERGE_AUTH_MJS_URL="https://raw.githubusercontent.com/66964432/cumob-codex-oneclick-installer/main/scripts/merge-auth.mjs"
DEFAULT_MERGE_AUTH_PY_URL="https://raw.githubusercontent.com/66964432/cumob-codex-oneclick-installer/main/scripts/merge_auth.py"

DRY_RUN=0
NO_PROMPT=0
DOWNLOAD_ROOT=""
FILTERED_CONFIG=""
NEW_CONFIG=""
RUNTIME_ROOT=""

cleanup() {
  if [ -n "$DOWNLOAD_ROOT" ] && [ -d "$DOWNLOAD_ROOT" ]; then
    rm -rf "$DOWNLOAD_ROOT"
  fi
  if [ -n "$FILTERED_CONFIG" ]; then
    rm -f "$FILTERED_CONFIG"
  fi
  if [ -n "$NEW_CONFIG" ]; then
    rm -f "$NEW_CONFIG"
  fi
}
trap cleanup EXIT


normalize_cumob_base_url() {
  local value="${1:-}"
  value="$(printf '%s' "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s|/*$||')"
  if [ -z "$value" ]; then
    return 1
  fi
  case "$value" in
    http://api.cumob.com|https://api.cumob.com|http://api.cumob.cn|https://api.cumob.cn|\
    http://api.cumob.com/v1|https://api.cumob.com/v1|http://api.cumob.cn/v1|https://api.cumob.cn/v1)
      ;;
    *)
      return 1
      ;;
  esac
  case "$value" in
    */v1) printf '%s\n' "$value" ;;
    *) printf '%s/v1\n' "$value" ;;
  esac
}

get_existing_cumob_base_url() {
  local config_path="${1:-}"
  local existing

  if [ -z "$config_path" ] || [ ! -f "$config_path" ]; then
    return 1
  fi

  existing="$(
    sed -nE 's/^[[:space:]]*base_url[[:space:]]*=[[:space:]]*"(https?:\/\/api\.cumob\.(com|cn)(\/v1)?)"[[:space:]]*(#.*)?$/\1/p' \
      "$config_path" | head -n 1
  )"
  normalize_cumob_base_url "$existing"
}

read_cumob_base_url_choice() {
  local timeout_seconds="${1:-15}"
  local default_url="${2:-https://api.cumob.com/v1}"
  local cn_url="https://api.cumob.cn/v1"
  local choice=""

  default_url="$(normalize_cumob_base_url "$default_url" || printf '%s\n' "https://api.cumob.com/v1")"

  printf '%s\n' \
    "" \
    "Select CUMOB API endpoint:" \
    "  1) $default_url  (default)" \
    "  2) $cn_url" \
    "Press 1 or 2 within ${timeout_seconds}s. Empty input or timeout keeps the default." >&2

  if [ -t 0 ]; then
    if IFS= read -r -t "$timeout_seconds" choice; then
      :
    else
      choice=""
    fi
  fi

  case "$(printf '%s' "$choice" | tr -d '[:space:]')" in
    2)
      printf '%s\n' "Selected: $cn_url" >&2
      printf '%s\n' "$cn_url"
      ;;
    1|"")
      if [ -z "$(printf '%s' "$choice" | tr -d '[:space:]')" ]; then
        printf '%s\n' "No selection within ${timeout_seconds}s. Using default: $default_url" >&2
      else
        printf '%s\n' "Selected: $default_url" >&2
      fi
      printf '%s\n' "$default_url"
      ;;
    *)
      printf '%s\n' "Unrecognized input. Using default: $default_url" >&2
      printf '%s\n' "$default_url"
      ;;
  esac
}

resolve_cumob_base_url() {
  local config_path="${1:-}"
  local no_prompt="${2:-0}"
  local default_url="https://api.cumob.com/v1"
  local from_env existing

  if from_env="$(normalize_cumob_base_url "${CUMOB_BASE_URL:-}")"; then
    printf '%s\n' "Using CUMOB_BASE_URL: $from_env" >&2
    printf '%s\n' "$from_env"
    return 0
  fi

  if existing="$(get_existing_cumob_base_url "$config_path")"; then
    printf '%s\n' "Existing CUMOB endpoint in config.toml: $existing" >&2
  fi

  if [ "$no_prompt" -eq 1 ] || [ ! -t 0 ]; then
    printf '%s\n' "Using default CUMOB endpoint: $default_url" >&2
    printf '%s\n' "$default_url"
    return 0
  fi

  read_cumob_base_url_choice 15 "$default_url"
}

usage() {
  printf '%s\n' \
    "Usage: ./install.sh [--dry-run] [--no-prompt]" \
    "" \
    "Environment variables:" \
    "  CODEX_HOME                  Override the Codex home directory." \
    "  CUMOB_INSTALL_API_KEY       Set the API key without a command-line argument." \
    "  CUMOB_SKILL_URL             Override the GitHub Skill archive URL." \
    "  CUMOB_SKILL_ARCHIVE         Local Skill zip path, or Skill archive URL." \
    "  CUMOB_SKILL_SOURCE_DIR      Use a local unpacked Skill directory." \
    "  CUMOB_INSTALLER_URL         Override installer archive URL used by bootstrap." \
    "  CUMOB_MODELS_URL            Override remote model catalog URL." \
    "  CUMOB_CONFIG_TEMPLATE_URL   Override remote config template URL." \
    "  CUMOB_BASE_URL              Skip the prompt and force https://api.cumob.com/v1 or https://api.cumob.cn/v1."
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --no-prompt)
      NO_PROMPT=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Required command not found: %s\n' "$1" >&2
    exit 1
  }
}

download_file() {
  local url="$1"
  local dest="$2"
  printf 'Downloading %s\n' "$url"
  curl -fsSL --retry 3 --retry-delay 2 -o "$dest" "$url"
}

ensure_runtime_assets() {
  local catalog_source="$PAYLOAD_DIR/cumob-models.json"
  local template_source="$PAYLOAD_DIR/cumob-config.template.toml"
  local merge_awk="$SCRIPT_DIR/scripts/merge-config.awk"
  local merge_auth_mjs="$SCRIPT_DIR/scripts/merge-auth.mjs"
  local merge_auth_py="$SCRIPT_DIR/scripts/merge_auth.py"

  if [ -f "$catalog_source" ] &&
    [ -f "$template_source" ] &&
    [ -f "$merge_awk" ] &&
    { [ -f "$merge_auth_mjs" ] || [ -f "$merge_auth_py" ]; }; then
    CATALOG_SOURCE="$catalog_source"
    TEMPLATE_SOURCE="$template_source"
    MERGE_AWK="$merge_awk"
    MERGE_AUTH_MJS="$merge_auth_mjs"
    MERGE_AUTH_PY="$merge_auth_py"
    return 0
  fi

  require_cmd curl
  RUNTIME_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cumob-installer-runtime.XXXXXX")"
  DOWNLOAD_ROOT="$RUNTIME_ROOT"
  mkdir -p "$RUNTIME_ROOT/payload" "$RUNTIME_ROOT/scripts"

  CATALOG_SOURCE="$RUNTIME_ROOT/payload/cumob-models.json"
  TEMPLATE_SOURCE="$RUNTIME_ROOT/payload/cumob-config.template.toml"
  MERGE_AWK="$RUNTIME_ROOT/scripts/merge-config.awk"
  MERGE_AUTH_MJS="$RUNTIME_ROOT/scripts/merge-auth.mjs"
  MERGE_AUTH_PY="$RUNTIME_ROOT/scripts/merge_auth.py"

  if [ -f "$catalog_source" ]; then
    cp "$catalog_source" "$CATALOG_SOURCE"
  else
    download_file "${CUMOB_MODELS_URL:-$DEFAULT_MODELS_URL}" "$CATALOG_SOURCE"
  fi

  if [ -f "$template_source" ]; then
    cp "$template_source" "$TEMPLATE_SOURCE"
  else
    download_file "${CUMOB_CONFIG_TEMPLATE_URL:-$DEFAULT_TEMPLATE_URL}" "$TEMPLATE_SOURCE"
  fi

  if [ -f "$merge_awk" ]; then
    cp "$merge_awk" "$MERGE_AWK"
  else
    download_file "${CUMOB_MERGE_AWK_URL:-$DEFAULT_MERGE_AWK_URL}" "$MERGE_AWK"
  fi

  if [ -f "$merge_auth_mjs" ]; then
    cp "$merge_auth_mjs" "$MERGE_AUTH_MJS"
  else
    download_file "${CUMOB_MERGE_AUTH_MJS_URL:-$DEFAULT_MERGE_AUTH_MJS_URL}" "$MERGE_AUTH_MJS" || true
  fi

  if [ -f "$merge_auth_py" ]; then
    cp "$merge_auth_py" "$MERGE_AUTH_PY"
  else
    download_file "${CUMOB_MERGE_AUTH_PY_URL:-$DEFAULT_MERGE_AUTH_PY_URL}" "$MERGE_AUTH_PY" || true
  fi

  if [ ! -f "$CATALOG_SOURCE" ] || [ ! -f "$TEMPLATE_SOURCE" ] || [ ! -f "$MERGE_AWK" ]; then
    printf '%s\n' "Failed to obtain installer assets from GitHub. Existing Codex files were not changed." >&2
    exit 1
  fi

  if [ ! -f "$MERGE_AUTH_MJS" ] && [ ! -f "$MERGE_AUTH_PY" ]; then
    printf '%s\n' "Failed to obtain auth merge helpers from GitHub. Existing Codex files were not changed." >&2
    exit 1
  fi
}

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
SKILLS_DIR="$CODEX_HOME/skills"
SKILL_TARGET="$SKILLS_DIR/cumob-image-generation4codex"
CATALOG_DIR="$CODEX_HOME/model-catalogs"
CATALOG_TARGET="$CATALOG_DIR/cumob-models.json"
CONFIG_PATH="$CODEX_HOME/config.toml"
AUTH_PATH="$CODEX_HOME/auth.json"

if [ "$DRY_RUN" -eq 1 ]; then
  printf '%s\n' \
    "Dry run only; no files will be changed." \
    "Codex home: $CODEX_HOME" \
    "Skill target: $SKILL_TARGET" \
    "Catalog target: $CATALOG_TARGET" \
    "Config target: $CONFIG_PATH" \
    "Auth target: $AUTH_PATH" \
    "Installer source: ${CUMOB_INSTALLER_URL:-$DEFAULT_INSTALLER_ARCHIVE_URL}" \
    "Skill source: ${CUMOB_SKILL_URL:-$DEFAULT_SKILL_ARCHIVE_URL}" \
    "Models source: ${CUMOB_MODELS_URL:-$DEFAULT_MODELS_URL}"
  exit 0
fi

ensure_runtime_assets

SKILL_SOURCE="${CUMOB_SKILL_SOURCE_DIR:-}"
if [ -z "$SKILL_SOURCE" ]; then
  require_cmd unzip
  if [ -z "$DOWNLOAD_ROOT" ]; then
    DOWNLOAD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cumob-skill-download.XXXXXX")"
  fi
  skill_archive="$DOWNLOAD_ROOT/cumob-image-generation4codex.zip"
  skill_extract_dir="$DOWNLOAD_ROOT/skill-extracted"
  mkdir -p "$skill_extract_dir"

  if [ -n "${CUMOB_SKILL_ARCHIVE:-}" ] && [ -f "$CUMOB_SKILL_ARCHIVE" ]; then
    cp "$CUMOB_SKILL_ARCHIVE" "$skill_archive"
  else
    require_cmd curl
    skill_url="${CUMOB_SKILL_ARCHIVE:-${CUMOB_SKILL_URL:-$DEFAULT_SKILL_ARCHIVE_URL}}"
    download_file "$skill_url" "$skill_archive"
  fi

  unzip -q "$skill_archive" -d "$skill_extract_dir"
  for candidate in "$skill_extract_dir"/*; do
    if [ -d "$candidate" ] && [ -f "$candidate/SKILL.md" ]; then
      SKILL_SOURCE="$candidate"
      break
    fi
  done
fi

if [ -z "$SKILL_SOURCE" ] ||
  [ ! -f "$SKILL_SOURCE/SKILL.md" ] ||
  { [ ! -f "$SKILL_SOURCE/scripts/generate-image.mjs" ] &&
    [ ! -f "$SKILL_SOURCE/scripts/generate-image.py" ]; }; then
  printf '%s\n' "Downloaded Skill archive is invalid or incomplete. Existing Codex files were not changed." >&2
  exit 1
fi

skill_version="latest"
if [ -f "$SKILL_SOURCE/VERSION" ]; then
  skill_version="$(sed -n '1p' "$SKILL_SOURCE/VERSION" | tr -d '\r')"
fi

api_key="${CUMOB_INSTALL_API_KEY:-}"
if [ -z "$api_key" ] && [ "$NO_PROMPT" -eq 0 ] && [ -t 0 ]; then
  printf '%s' "CUMOB API Key (leave blank to keep existing auth.json): "
  IFS= read -r -s api_key
  printf '\n'
fi

cumob_base_url="$(resolve_cumob_base_url "$CONFIG_PATH" "$NO_PROMPT")"

timestamp="$(date '+%Y%m%d-%H%M%S')"
backup_dir="$CODEX_HOME/backups/cumob-installer-$timestamp"
if [ -e "$backup_dir" ]; then
  backup_dir="$backup_dir-$$"
fi
mkdir -p "$backup_dir" "$SKILLS_DIR" "$CATALOG_DIR"

if [ -f "$CONFIG_PATH" ]; then
  cp "$CONFIG_PATH" "$backup_dir/config.toml"
fi
if [ -f "$AUTH_PATH" ]; then
  cp "$AUTH_PATH" "$backup_dir/auth.json"
fi
if [ -f "$CATALOG_TARGET" ]; then
  cp "$CATALOG_TARGET" "$backup_dir/cumob-models.json"
fi
if [ -d "$SKILL_TARGET" ]; then
  cp -R "$SKILL_TARGET" "$backup_dir/cumob-image-generation4codex"
fi

temp_skill="$SKILLS_DIR/.cumob-image-generation4codex.tmp.$$"
rm -rf "$temp_skill"
cp -R "$SKILL_SOURCE" "$temp_skill"
rm -rf "$SKILL_TARGET"
mv "$temp_skill" "$SKILL_TARGET"
cp "$CATALOG_SOURCE" "$CATALOG_TARGET"

FILTERED_CONFIG="$(mktemp "${TMPDIR:-/tmp}/cumob-config-filtered.XXXXXX")"
NEW_CONFIG="$(mktemp "${TMPDIR:-/tmp}/cumob-config-new.XXXXXX")"

if [ -f "$CONFIG_PATH" ]; then
  awk -f "$MERGE_AWK" "$CONFIG_PATH" > "$FILTERED_CONFIG"
else
  : > "$FILTERED_CONFIG"
fi

catalog_toml_path="${CATALOG_TARGET//\\/\\\\}"
catalog_toml_path="${catalog_toml_path//\"/\\\"}"

if [ -f "$TEMPLATE_SOURCE" ]; then
  managed_block="$(
    sed \
      -e "s|{{MODEL_CATALOG_PATH}}|$catalog_toml_path|g" \
      -e "s|{{CUMOB_BASE_URL}}|$cumob_base_url|g" \
      "$TEMPLATE_SOURCE"
  )"
else
  managed_block="$(
    printf '%s\n' \
      'model_provider = "cumob"' \
      'model = "gpt-5.6-sol"' \
      'disable_response_storage = true' \
      "model_catalog_json = \"$catalog_toml_path\"" \
      'model_reasoning_effort = "high"' \
      '' \
      '[model_providers.cumob]' \
      'name = "cumob"' \
      'wire_api = "responses"' \
      'image_api = "images"' \
      'image_model = "gpt-image-2-ref"' \
      'requires_openai_auth = true' \
      "base_url = \"$cumob_base_url\""
  )"
fi

{
  printf '%s\n' "# BEGIN CUMOB CODEX ONE-CLICK INSTALLER"
  printf '%s\n' "$managed_block"
  printf '%s\n' "# END CUMOB CODEX ONE-CLICK INSTALLER"

  if [ -s "$FILTERED_CONFIG" ]; then
    printf '\n'
    sed '/./,$!d' "$FILTERED_CONFIG"
  fi
} > "$NEW_CONFIG"

mv "$NEW_CONFIG" "$CONFIG_PATH"
NEW_CONFIG=""
chmod 600 "$CONFIG_PATH"

if [ -n "$api_key" ]; then
  export CUMOB_INSTALL_API_KEY="$api_key"
  if command -v node >/dev/null 2>&1 && [ -f "$MERGE_AUTH_MJS" ]; then
    node "$MERGE_AUTH_MJS" "$AUTH_PATH"
  elif command -v python3 >/dev/null 2>&1 && [ -f "$MERGE_AUTH_PY" ]; then
    python3 "$MERGE_AUTH_PY" "$AUTH_PATH"
  elif [ -x "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node" ] && [ -f "$MERGE_AUTH_MJS" ]; then
    "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node" \
      "$MERGE_AUTH_MJS" "$AUTH_PATH"
  else
    printf '%s\n' \
      "The skill and Codex configuration were installed, but auth.json could not be updated." \
      "Install Node.js 18+ or Python 3, then run this installer again." >&2
    exit 1
  fi
  unset CUMOB_INSTALL_API_KEY
elif [ ! -f "$AUTH_PATH" ]; then
  printf '%s\n' "Warning: no API Key was provided. Run the installer again to complete authentication." >&2
fi

runtime_message="No Node.js 18+ or Python 3 runtime was detected on PATH."
if command -v node >/dev/null 2>&1; then
  node_major="$(node -p 'Number(process.versions.node.split(\".\")[0])' 2>/dev/null || printf '0')"
  if [ "$node_major" -ge 18 ]; then
    runtime_message="Node.js runtime detected."
  fi
fi
if [ "$runtime_message" != "Node.js runtime detected." ] && command -v python3 >/dev/null 2>&1; then
  runtime_message="Python 3 runtime detected."
fi

printf '%s\n' \
  "" \
  "codex 一键接入自定义路由 - cumob 篇 安装完成。" \
  "Backup: $backup_dir" \
  "Skill: $SKILL_TARGET (downloaded version: $skill_version)" \
  "Model catalog: $CATALOG_TARGET" \
  "Config: $CONFIG_PATH" \
  "CUMOB endpoint: $cumob_base_url" \
  "$runtime_message" \
  "Restart Codex or create a new task to reload the skill and model catalog."
