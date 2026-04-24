#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AAN_ROOT_DEFAULT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

SECTION="all"
PROJECT_ROOT="$(pwd)"
AAN_ROOT="${AAN_ROOT_DEFAULT}"
STATE_FILE=""
OUTPUT_FORMAT="text"
STRICT=0

EXIT_OK=0
EXIT_FAILURE=1
EXIT_USAGE=2
EXIT_INCOMPLETE=3
EXIT_DRIFT=4

RESULT_LINES=()
OVERALL_STATUS="pass"

usage() {
  cat <<'EOF'
AAN Codex installation verification

Usage:
  install-verification.sh [options]

Options:
  --project-root <path>   Target Codex project root. Default: current directory.
  --aan-root <path>       AAN root directory. Default: inferred from this script path.
  --state-file <path>     Install state file. Default: <project-root>/.codex/aan-install-state.json
  --section <name>        Section to verify. One of: all, skills, agents, mcp, boundary, state
  --json                  Emit JSON summary instead of text.
  --strict                Treat warnings as failures.
  --help                  Show this help message.

Sections:
  all       Run all verification sections.
  skills    Verify installed skills and their required files.
  agents    Verify generated Codex agents and config registration.
  mcp       Verify MCP server entries in .codex/config.toml.
  boundary  Verify AAN submodule hard-boundary settings in .codex/config.toml.
  state     Verify .codex/aan-install-state.json structure and consistency.

Exit codes:
  0  Verification passed.
  1  Verification failed.
  2  Invalid arguments or runtime usage error.
  3  Required inputs are missing; verification is incomplete.
  4  Installed state and on-disk configuration have drifted.

Examples:
  install-verification.sh
  install-verification.sh --section agents
  install-verification.sh --project-root /path/to/project --json
  install-verification.sh --strict --section mcp

Notes:
  This script verifies installation results only.
  It does not install, repair, or modify files.
EOF
}

add_result() {
  local status="$1"
  local section="$2"
  local summary="$3"
  RESULT_LINES+=("${status}|${section}|${summary}")

  case "${status}" in
    fail)
      OVERALL_STATUS="fail"
      ;;
    drift)
      if [[ "${OVERALL_STATUS}" != "fail" ]]; then
        OVERALL_STATUS="drift"
      fi
      ;;
    warn)
      if [[ "${STRICT}" -eq 1 ]]; then
        OVERALL_STATUS="fail"
      elif [[ "${OVERALL_STATUS}" == "pass" ]]; then
        OVERALL_STATUS="warn"
      fi
      ;;
  esac
}

print_text_results() {
  printf 'AAN Codex Verification\n'
  printf 'Project: %s\n' "${PROJECT_ROOT}"
  printf 'AAN Root: %s\n' "${AAN_ROOT}"
  printf 'Section: %s\n' "${SECTION}"
  printf '\n'

  local line status section summary
  for line in "${RESULT_LINES[@]}"; do
    IFS='|' read -r status section summary <<< "${line}"
    printf '%s %s: %s\n' "$(printf '%s' "${status}" | tr '[:lower:]' '[:upper:]')" "${section}" "${summary}"
  done
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "${value}"
}

print_json_results() {
  printf '{'
  printf '"project_root":"%s",' "$(json_escape "${PROJECT_ROOT}")"
  printf '"aan_root":"%s",' "$(json_escape "${AAN_ROOT}")"
  printf '"section":"%s",' "$(json_escape "${SECTION}")"
  printf '"status":"%s",' "$(json_escape "${OVERALL_STATUS}")"
  printf '"results":['

  local first=1
  local line status section summary
  for line in "${RESULT_LINES[@]}"; do
    IFS='|' read -r status section summary <<< "${line}"
    if [[ "${first}" -eq 0 ]]; then
      printf ','
    fi
    first=0
    printf '{"section":"%s","status":"%s","summary":"%s"}' \
      "$(json_escape "${section}")" \
      "$(json_escape "${status}")" \
      "$(json_escape "${summary}")"
  done

  printf ']}'
}

require_file() {
  local path="$1"
  local section="$2"
  local label="$3"
  if [[ ! -f "${path}" ]]; then
    printf 'FAIL|%s is missing: %s\n' "${label}" "${path}"
    return 1
  fi
  return 0
}

require_dir() {
  local path="$1"
  local section="$2"
  local label="$3"
  if [[ ! -d "${path}" ]]; then
    printf 'FAIL|%s is missing: %s\n' "${label}" "${path}"
    return 1
  fi
  return 0
}

toml_parse_available() {
  python3 - <<'PY' >/dev/null 2>&1
import sys
try:
    import tomllib  # noqa: F401
except Exception:
    sys.exit(1)
PY
}

validate_toml() {
  local config_file="$1"
  python3 - "${config_file}" <<'PY'
import sys
import tomllib

path = sys.argv[1]
with open(path, "rb") as fh:
    tomllib.load(fh)
PY
}

state_json_get() {
  local expr="$1"
  python3 - "${STATE_FILE}" "${expr}" <<'PY'
import json
import sys

path = sys.argv[1]
expr = sys.argv[2]

with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

parts = [p for p in expr.split(".") if p]
current = data
for part in parts:
    if isinstance(current, dict) and part in current:
        current = current[part]
    else:
        sys.exit(3)

if isinstance(current, (dict, list)):
    print(json.dumps(current, ensure_ascii=False))
else:
    print(current)
PY
}

validate_skills() {
  local section="skills"
  local skills_dir="${PROJECT_ROOT}/.agents/skills"

  require_dir "${skills_dir}" "${section}" "skills directory" || return 0

  if [[ ! -f "${STATE_FILE}" ]]; then
    printf 'WARN|state file is missing; cannot verify AAN-managed skills precisely\n'
    return 0
  fi

  local installed_skills_json
  if ! installed_skills_json="$(state_json_get "skills")"; then
    printf 'DRIFT|state file does not contain a readable skills list\n'
    return 0
  fi

  python3 - "${skills_dir}" "${installed_skills_json}" <<'PY'
import json
import sys
from pathlib import Path

skills_dir = Path(sys.argv[1])
skills = json.loads(sys.argv[2])

missing = []
broken = []

for name in skills:
    target = skills_dir / name
    if not target.is_dir():
        missing.append(name)
        continue
    if not (target / "SKILL.md").is_file():
        broken.append(name)

if missing:
    print("FAIL|" + ", ".join(missing))
elif broken:
    print("WARN|" + ", ".join(broken))
else:
    print(f"PASS|{len(skills)}")
PY
}

validate_agents() {
  local section="agents"
  local agents_dir="${PROJECT_ROOT}/.codex/agents"
  local config_file="${PROJECT_ROOT}/.codex/config.toml"

  require_dir "${agents_dir}" "${section}" "agents directory" || return 0
  require_file "${config_file}" "${section}" "Codex config" || return 0

  if toml_parse_available; then
    if ! validate_toml "${config_file}" >/dev/null 2>&1; then
      printf 'FAIL|config.toml is not valid TOML\n'
      return 0
    fi
  else
    printf 'WARN|python tomllib is unavailable; skipped full TOML parse\n'
    return 0
  fi

  if [[ ! -f "${STATE_FILE}" ]]; then
    printf 'WARN|state file is missing; cannot verify AAN-managed agents precisely\n'
    return 0
  fi

  local installed_agents_json
  if ! installed_agents_json="$(state_json_get "agents")"; then
    printf 'DRIFT|state file does not contain a readable agents list\n'
    return 0
  fi

  python3 - "${agents_dir}" "${config_file}" "${installed_agents_json}" <<'PY'
import json
import sys
import tomllib
from pathlib import Path

agents_dir = Path(sys.argv[1])
config_file = Path(sys.argv[2])
agents = json.loads(sys.argv[3])
config_text = config_file.read_text(encoding="utf-8")

missing_files = []
missing_config = []
broken_files = []
invalid_toml = []

for item in agents:
    agent_id = item["id"] if isinstance(item, dict) else str(item)
    agent_file = agents_dir / f"{agent_id}.toml"
    if not agent_file.is_file():
      missing_files.append(agent_id)
      continue

    try:
        with agent_file.open("rb") as fh:
            agent_data = tomllib.load(fh)
    except Exception:
        invalid_toml.append(agent_id)
        continue

    description = agent_data.get("description")
    instructions = agent_data.get("developer_instructions")
    if not isinstance(description, str) or not description.strip():
      broken_files.append(agent_id)
    elif not isinstance(instructions, str) or not instructions.strip():
      broken_files.append(agent_id)

    marker = f"[agents.{agent_id}]"
    if marker not in config_text:
      missing_config.append(agent_id)

if missing_files or missing_config or invalid_toml:
    parts = []
    if missing_files:
        parts.append("missing files: " + ", ".join(missing_files))
    if missing_config:
        parts.append("missing config entries: " + ", ".join(missing_config))
    if invalid_toml:
        parts.append("invalid TOML files: " + ", ".join(invalid_toml))
    print("FAIL|" + "; ".join(parts))
elif broken_files:
    print("WARN|broken agent files: " + ", ".join(broken_files))
else:
    print(f"PASS|{len(agents)}")
PY
}

validate_mcp() {
  local section="mcp"
  local config_file="${PROJECT_ROOT}/.codex/config.toml"

  require_file "${config_file}" "${section}" "Codex config" || return 0

  if [[ ! -f "${STATE_FILE}" ]]; then
    printf 'WARN|state file is missing; cannot verify AAN-managed MCP servers precisely\n'
    return 0
  fi

  local mcp_json
  if ! mcp_json="$(state_json_get "mcp_servers")"; then
    printf 'WARN|state file does not contain MCP server selections\n'
    return 0
  fi

  python3 - "${config_file}" "${mcp_json}" <<'PY'
import json
import re
import sys
from pathlib import Path

config_text = Path(sys.argv[1]).read_text(encoding="utf-8")
servers = json.loads(sys.argv[2])

missing = []
placeholders = []

for item in servers:
    name = item["name"] if isinstance(item, dict) else str(item)
    marker = f"[mcp_servers.{name}]"
    if marker not in config_text:
        missing.append(name)

for line in config_text.splitlines():
    if re.search(r"\bYOUR_[A-Z0-9_]*(?:_HERE)?\b", line):
        placeholders.append(line.strip())
    elif re.search(r"/path/to/your(?:/|\b)", line, flags=re.IGNORECASE):
        placeholders.append(line.strip())

if missing:
    print("FAIL|" + ", ".join(missing))
elif placeholders:
    print("WARN|" + str(len(placeholders)))
else:
    print(f"PASS|{len(servers)}")
PY
}

validate_boundary() {
  local section="boundary"
  local config_file="${PROJECT_ROOT}/.codex/config.toml"

  require_file "${config_file}" "${section}" "Codex config" || return 0

  if [[ ! -f "${STATE_FILE}" ]]; then
    printf 'WARN|state file is missing; cannot verify boundary ownership\n'
    return 0
  fi

  local submodule_path profile_name
  if ! submodule_path="$(state_json_get "aan_project_relative_path" 2>/dev/null)"; then
    printf 'DRIFT|state file does not contain AAN relative path\n'
    return 0
  fi
  if ! profile_name="$(state_json_get "boundary_profile" 2>/dev/null)"; then
    printf 'DRIFT|state file does not contain boundary profile name\n'
    return 0
  fi
  if [[ -z "${profile_name}" ]]; then
    printf 'DRIFT|state file contains an empty boundary profile name\n'
    return 0
  fi

  python3 - "${config_file}" "${submodule_path}" "${profile_name}" <<'PY'
import sys
import tomllib
from pathlib import Path

config_file = Path(sys.argv[1])
submodule = sys.argv[2].strip()
profile = sys.argv[3].strip()

try:
    with config_file.open("rb") as fh:
        config = tomllib.load(fh)
except Exception as exc:
    print(f"FAIL|config.toml is not valid TOML: {exc}")
    raise SystemExit(0)

def text_values(node):
    if isinstance(node, dict):
        for key, value in node.items():
            yield str(key)
            yield from text_values(value)
    elif isinstance(node, list):
        for value in node:
            yield from text_values(value)
    elif isinstance(node, str):
        yield node

def has_profile_reference(node, profile_name):
    return any(value == profile_name for value in text_values(node))

def profile_nodes(node, profile_name):
    found = []
    if isinstance(node, dict):
        for key, value in node.items():
            if str(key) == profile_name:
                found.append(value)
            found.extend(profile_nodes(value, profile_name))
    elif isinstance(node, list):
        for value in node:
            found.extend(profile_nodes(value, profile_name))
    return found

def has_boundary_path(node, path):
    candidates = {
        path,
        path.rstrip("/") + "/**",
        "Read(" + path.rstrip("/") + "/**)",
        "Read(" + path.rstrip("/") + ")",
    }
    for value in text_values(node):
        normalized = value.strip()
        if normalized in candidates or path in normalized:
            return True
    return False

def has_deny_read_semantics(node):
    values = [value.strip().lower() for value in text_values(node)]
    joined = " ".join(values)
    if "deny-read" in joined or "deny_read" in joined:
        return True
    if "deny" in joined and "read" in joined:
        return True
    return any(value.startswith("read(") for value in values)

def has_boundary(node, path):
    return has_boundary_path(node, path) and has_deny_read_semantics(node)

nodes = profile_nodes(config, profile)
profile_present = bool(nodes) or has_profile_reference(config, profile)

if nodes:
    boundary_present = any(has_boundary(node, submodule) for node in nodes)
else:
    boundary_present = False

# Some Codex configs keep the selected profile and permission tables in separate
# top-level sections. Accept that shape only after TOML parsing and explicit
# profile reference/path/deny-read checks have all passed.
if not boundary_present and profile_present:
    boundary_present = has_boundary(config, submodule)

if not profile_present or not boundary_present:
    parts = []
    if not profile_present:
        parts.append(f"profile not found: {profile}")
    if not boundary_present:
        parts.append(f"deny-read boundary not found for path: {submodule}")
    print("FAIL|" + "; ".join(parts))
else:
    print("PASS|1")
PY
}

validate_state() {
  local section="state"

  require_file "${STATE_FILE}" "${section}" "install state file" || return 0

  python3 - "${STATE_FILE}" <<'PY'
import json
import sys

required = [
    "installed_at",
    "aan_root",
    "aan_project_relative_path",
    "selected_modules",
    "skills",
    "agents",
    "ignored_categories",
    "boundary_profile",
]

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

missing = [key for key in required if key not in data]

if missing:
    print("FAIL|" + ", ".join(missing))
else:
    print("PASS|1")
PY
}

consume_section_result() {
  local section="$1"
  local raw="$2"
  local status detail
  IFS='|' read -r status detail <<< "${raw}"
  status="$(printf '%s' "${status}" | tr '[:upper:]' '[:lower:]')"

  case "${section}" in
    skills)
      case "${status}" in
        pass) add_result "pass" "${section}" "${detail} installed skills validated" ;;
        warn) add_result "warn" "${section}" "skills missing SKILL.md: ${detail}" ;;
        fail) add_result "fail" "${section}" "missing installed skills: ${detail}" ;;
        drift) add_result "drift" "${section}" "${detail}" ;;
      esac
      ;;
    agents)
      case "${status}" in
        pass) add_result "pass" "${section}" "${detail} agents validated" ;;
        warn) add_result "warn" "${section}" "${detail}" ;;
        fail) add_result "fail" "${section}" "${detail}" ;;
        drift) add_result "drift" "${section}" "${detail}" ;;
      esac
      ;;
    mcp)
      case "${status}" in
        pass) add_result "pass" "${section}" "${detail} MCP servers validated" ;;
        warn) add_result "warn" "${section}" "${detail} unresolved placeholder lines remain in config.toml" ;;
        fail) add_result "fail" "${section}" "missing MCP server entries: ${detail}" ;;
        drift) add_result "drift" "${section}" "${detail}" ;;
      esac
      ;;
    boundary)
      case "${status}" in
        pass) add_result "pass" "${section}" "AAN hard boundary is present" ;;
        fail) add_result "fail" "${section}" "${detail}" ;;
        drift) add_result "drift" "${section}" "${detail}" ;;
        warn) add_result "warn" "${section}" "${detail}" ;;
      esac
      ;;
    state)
      case "${status}" in
        pass) add_result "pass" "${section}" "install state file is structurally valid" ;;
        fail) add_result "fail" "${section}" "state file is missing required keys: ${detail}" ;;
        drift) add_result "drift" "${section}" "${detail}" ;;
        warn) add_result "warn" "${section}" "${detail}" ;;
      esac
      ;;
  esac
}

run_section() {
  local section="$1"
  local raw=""

  case "${section}" in
    skills) raw="$(validate_skills || true)" ;;
    agents) raw="$(validate_agents || true)" ;;
    mcp) raw="$(validate_mcp || true)" ;;
    boundary) raw="$(validate_boundary || true)" ;;
    state) raw="$(validate_state || true)" ;;
    *) return 1 ;;
  esac

  if [[ -n "${raw}" ]]; then
    consume_section_result "${section}" "${raw}"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root)
        [[ $# -ge 2 ]] || { echo "Missing value for --project-root" >&2; exit "${EXIT_USAGE}"; }
        PROJECT_ROOT="$2"
        shift 2
        ;;
      --aan-root)
        [[ $# -ge 2 ]] || { echo "Missing value for --aan-root" >&2; exit "${EXIT_USAGE}"; }
        AAN_ROOT="$2"
        shift 2
        ;;
      --state-file)
        [[ $# -ge 2 ]] || { echo "Missing value for --state-file" >&2; exit "${EXIT_USAGE}"; }
        STATE_FILE="$2"
        shift 2
        ;;
      --section)
        [[ $# -ge 2 ]] || { echo "Missing value for --section" >&2; exit "${EXIT_USAGE}"; }
        SECTION="$2"
        shift 2
        ;;
      --json)
        OUTPUT_FORMAT="json"
        shift
        ;;
      --strict)
        STRICT=1
        shift
        ;;
      --help|-h)
        usage
        exit "${EXIT_OK}"
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage >&2
        exit "${EXIT_USAGE}"
        ;;
    esac
  done
}

validate_inputs() {
  case "${SECTION}" in
    all|skills|agents|mcp|boundary|state) ;;
    *)
      echo "Invalid --section: ${SECTION}" >&2
      exit "${EXIT_USAGE}"
      ;;
  esac

  [[ -n "${STATE_FILE}" ]] || STATE_FILE="${PROJECT_ROOT}/.codex/aan-install-state.json"

  if [[ ! -d "${PROJECT_ROOT}" ]]; then
    add_result "fail" "runtime" "project root does not exist: ${PROJECT_ROOT}"
    return 1
  fi

  if [[ ! -d "${AAN_ROOT}" ]]; then
    add_result "fail" "runtime" "AAN root does not exist: ${AAN_ROOT}"
    return 1
  fi

  return 0
}

main() {
  parse_args "$@"
  validate_inputs || true

  if [[ "${SECTION}" == "all" ]]; then
    run_section "state"
    run_section "skills"
    run_section "agents"
    run_section "mcp"
    run_section "boundary"
  else
    run_section "${SECTION}"
  fi

  if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
    print_json_results
    printf '\n'
  else
    print_text_results
  fi

  case "${OVERALL_STATUS}" in
    pass)
      exit "${EXIT_OK}"
      ;;
    warn)
      if [[ "${STRICT}" -eq 1 ]]; then
        exit "${EXIT_FAILURE}"
      fi
      exit "${EXIT_OK}"
      ;;
    fail)
      exit "${EXIT_FAILURE}"
      ;;
    drift)
      exit "${EXIT_DRIFT}"
      ;;
    *)
      exit "${EXIT_INCOMPLETE}"
      ;;
  esac
}

main "$@"
