#!/usr/bin/env bash
set -euo pipefail

# =========================================================================
#  AAN — Cursor MCP Server Configurator
# =========================================================================
#  Interactive multi-select installer that reads mcp/mcp-servers.json and
#  generates a Cursor-compatible .cursor/mcp.json for the host project.
#
#  Usage:
#    bash aan/cursor/init-mcp.sh
#    bash aan/cursor/init-mcp.sh --project-root /path/to/project
# =========================================================================

VERSION="1.0.0"

command -v python3 &>/dev/null || { echo "Error: python3 is required." >&2; exit 1; }

# ---- Terminal colours (disabled when stdout is not a tty) ----------------
if [[ -t 1 ]]; then
  RST='\033[0m'; GRN='\033[32m'; YEL='\033[33m'; RED='\033[31m'
  CYN='\033[36m'; BLD='\033[1m'; DIM='\033[2m'
else
  RST=''; GRN=''; YEL=''; RED=''; CYN=''; BLD=''; DIM=''
fi

info()  { printf "${CYN}ℹ${RST}  %s\n" "$*"; }
ok()    { printf "${GRN}✓${RST}  %s\n" "$*"; }
warn()  { printf "${YEL}⚠${RST}  %s\n" "$*"; }
err()   { printf "${RED}✗${RST}  %s\n" "$*" >&2; }

# ---- Path resolution -----------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MCP_JSON="$REPO_ROOT/mcp/mcp-servers.json"

[[ -f "$MCP_JSON" ]] || { err "MCP config not found: $MCP_JSON"; exit 1; }

PROJECT_ROOT=""

resolve_project_root() {
  [[ -n "$PROJECT_ROOT" ]] && { PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"; return; }

  # Method 1: git superproject (submodule case)
  local super
  super="$(cd "$REPO_ROOT" && git rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  [[ -n "$super" ]] && { PROJECT_ROOT="$super"; return; }

  # Method 2: walk up looking for a parent .git
  local dir="$REPO_ROOT"
  while [[ "$dir" != "/" ]]; do
    dir="$(dirname "$dir")"
    [[ -d "$dir/.git" || -f "$dir/.git" ]] && { PROJECT_ROOT="$dir"; return; }
  done

  PROJECT_ROOT="$(pwd)"
}

# ---- Parse mcp-servers.json into bash arrays -----------------------------
declare -a SRV_NAMES=() SRV_DESCS=() SRV_ENVS=() SRV_SEL=()

load_servers() {
  while IFS=$'\x1f' read -r name desc envs; do
    SRV_NAMES+=("$name")
    SRV_DESCS+=("$desc")
    SRV_ENVS+=("$envs")
    SRV_SEL+=("0")
  done < <(
    MCP_JSON="$MCP_JSON" python3 -c "
import json, os

with open(os.environ['MCP_JSON']) as f:
    data = json.load(f)

for name, cfg in data.get('mcpServers', {}).items():
    desc = cfg.get('description', '')
    keys = []
    for k, v in cfg.get('env', {}).items():
        if isinstance(v, str) and ('YOUR_' in v or '_HERE' in v.upper()):
            keys.append(k)
    for k, v in cfg.get('headers', {}).items():
        if isinstance(v, str) and ('YOUR_' in v or '_HERE' in v.upper()):
            keys.append('header:' + k)
    print(name + chr(31) + desc + chr(31) + '|'.join(keys))
"
  )
}

# ---- Generate .cursor/mcp.json via python3 -------------------------------
write_config() {
  local output="$1" selected_csv="$2" overrides_file="$3"

  MCP_JSON="$MCP_JSON" python3 -c "
import json, os, sys

with open(os.environ['MCP_JSON']) as f:
    data = json.load(f)

selected = [s for s in sys.argv[1].split(',') if s]
overrides = {}
ovr_path = sys.argv[2]
if os.path.isfile(ovr_path):
    with open(ovr_path) as f:
        for ln in f:
            ln = ln.strip()
            if not ln:
                continue
            dot = ln.index('.')
            eq  = ln.index('=', dot)
            srv, key, val = ln[:dot], ln[dot+1:eq], ln[eq+1:]
            overrides.setdefault(srv, {})[key] = val

result = {'mcpServers': {}}
for name in selected:
    orig = data['mcpServers'].get(name)
    if not orig:
        continue
    cfg = {k: v for k, v in orig.items() if k != 'description'}
    for key, val in overrides.get(name, {}).items():
        if key.startswith('header:'):
            cfg.setdefault('headers', {})[key[7:]] = val
        else:
            cfg.setdefault('env', {})[key] = val
    result['mcpServers'][name] = cfg

out_path = sys.argv[3]
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, 'w') as f:
    json.dump(result, f, indent=2, ensure_ascii=False)
    f.write('\n')
print(len(result['mcpServers']))
" "$selected_csv" "$overrides_file" "$output"
}

# ---- Keyboard input -------------------------------------------------------
read_key() {
  local k
  IFS= read -rsn1 k 2>/dev/null
  case "$k" in
    $'\x1b')
      local seq
      IFS= read -rsn2 -t 0.1 seq 2>/dev/null || true
      case "$seq" in
        '[A') echo UP   ;; '[B') echo DOWN ;;
        *)    echo X    ;;
      esac ;;
    ' ')  echo SPACE ;; '') echo ENTER ;;
    a|A)  echo ALL   ;; n|N) echo NONE ;;
    q|Q)  echo QUIT  ;; *)   echo X    ;;
  esac
}

count_sel() {
  local c=0
  for s in "${SRV_SEL[@]}"; do [[ "$s" == 1 ]] && c=$((c + 1)); done
  echo $c
}

# ---- Interactive multi-select TUI ----------------------------------------
draw_menu() {
  local cur=$1 total=$2
  for (( i = 0; i < total; i++ )); do
    printf "\r\033[K"

    # Cursor indicator
    if (( i == cur )); then printf " ${CYN}›${RST} "; else printf "   "; fi

    # Checkbox
    if [[ "${SRV_SEL[$i]}" == 1 ]]; then printf "${GRN}[x]${RST} "; else printf "[ ] "; fi

    # Server name (fixed-width via manual padding)
    local nm="${SRV_NAMES[$i]}"
    local pad=$(( 28 - ${#nm} ))
    (( pad < 1 )) && pad=1
    if (( i == cur )); then printf "${BLD}%s${RST}" "$nm"; else printf "%s" "$nm"; fi
    printf "%${pad}s" ""

    # Description (truncated)
    local ds="${SRV_DESCS[$i]}"
    (( ${#ds} > 50 )) && ds="${ds:0:47}..."
    printf "${DIM}%s${RST}" "$ds"

    # Required env/header variables hint
    if [[ -n "${SRV_ENVS[$i]}" ]]; then
      local readable
      readable=$(echo "${SRV_ENVS[$i]}" | sed 's/header://g' | tr '|' ', ')
      printf "  ${YEL}[%s required]${RST}" "$readable"
    fi

    printf "\n"
  done
}

run_selector() {
  local total=${#SRV_NAMES[@]}
  local cur=0

  tput civis 2>/dev/null || true
  trap 'tput cnorm 2>/dev/null; stty sane 2>/dev/null' EXIT INT TERM

  printf "\n"
  printf "  ${BLD}Select MCP servers for your project${RST}\n"
  printf "  ${DIM}↑↓ Navigate  SPACE Toggle  a All  n None  ENTER Confirm  q Quit${RST}\n\n"

  draw_menu "$cur" "$total"
  printf "\r\033[K  ${DIM}$(count_sel) / $total selected${RST}"

  while true; do
    local key
    key=$(read_key)
    case "$key" in
      UP)    (( cur > 0 )) && cur=$((cur - 1)) || true ;;
      DOWN)  (( cur < total - 1 )) && cur=$((cur + 1)) || true ;;
      SPACE) [[ "${SRV_SEL[$cur]}" == 1 ]] && SRV_SEL[$cur]=0 || SRV_SEL[$cur]=1 ;;
      ALL)   for (( i = 0; i < total; i++ )); do SRV_SEL[$i]=1; done ;;
      NONE)  for (( i = 0; i < total; i++ )); do SRV_SEL[$i]=0; done ;;
      ENTER) tput cnorm 2>/dev/null || true; printf "\n\n"; return ;;
      QUIT)  tput cnorm 2>/dev/null || true; printf "\n\n"; info "Cancelled."; exit 0 ;;
      *)     continue ;;
    esac

    # Redraw: move cursor back up to the first menu line, then repaint
    tput cuu "$total" 2>/dev/null
    draw_menu "$cur" "$total"
    printf "\r\033[K  ${DIM}$(count_sel) / $total selected${RST}"
  done
}

# ---- Main -----------------------------------------------------------------
main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) PROJECT_ROOT="$2"; shift 2 ;;
      -h|--help)
        printf "Usage: bash init-mcp.sh [--project-root PATH]\n"
        printf "Interactively select MCP servers and generate .cursor/mcp.json\n"
        exit 0 ;;
      *) err "Unknown option: $1"; exit 1 ;;
    esac
  done

  resolve_project_root
  local output="$PROJECT_ROOT/.cursor/mcp.json"

  printf "\n${BLD}AAN MCP Configurator v${VERSION}${RST}\n\n"
  info "Project root: $PROJECT_ROOT"
  info "Output:       $output"

  # Warn and confirm if config already exists
  if [[ -f "$output" ]]; then
    echo ""
    warn "Existing MCP config found: $output"
    printf "   Overwrite? [y/N]: "
    read -r ans < /dev/tty
    [[ "$ans" =~ ^[yY]$ ]] || { info "Cancelled."; exit 0; }
  fi

  # Load server catalogue
  load_servers
  (( ${#SRV_NAMES[@]} > 0 )) || { err "No servers found in $MCP_JSON"; exit 1; }

  # Interactive multi-select
  run_selector

  # Collect selected server names
  local selected=()
  for (( i = 0; i < ${#SRV_NAMES[@]}; i++ )); do
    [[ "${SRV_SEL[$i]}" == 1 ]] && selected+=("${SRV_NAMES[$i]}")
  done
  (( ${#selected[@]} > 0 )) || { warn "No servers selected. Nothing to write."; exit 0; }

  ok "Selected ${#selected[@]} server(s): ${selected[*]}"

  # Collect credentials for servers that require env vars / header keys
  local tmpfile
  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"; tput cnorm 2>/dev/null' EXIT

  local need_env=false
  for (( i = 0; i < ${#SRV_NAMES[@]}; i++ )); do
    [[ "${SRV_SEL[$i]}" == 1 && -n "${SRV_ENVS[$i]}" ]] && { need_env=true; break; }
  done

  if $need_env; then
    printf "\n  ${BLD}Configure required credentials${RST}\n"
    printf "  ${DIM}Leave empty to keep placeholder value${RST}\n\n"

    for (( i = 0; i < ${#SRV_NAMES[@]}; i++ )); do
      [[ "${SRV_SEL[$i]}" == 1 && -n "${SRV_ENVS[$i]}" ]] || continue
      local name="${SRV_NAMES[$i]}"
      IFS='|' read -ra vars <<< "${SRV_ENVS[$i]}"
      for v in "${vars[@]}"; do
        local display="${v#header:}"
        printf "  ${CYN}%-22s${RST} ${BLD}%s${RST}: " "$name" "$display"
        read -r val < /dev/tty
        [[ -n "$val" ]] && echo "${name}.${v}=${val}" >> "$tmpfile"
      done
    done
  fi

  # Build CSV and write config
  printf "\n"
  local csv
  csv=$(IFS=','; echo "${selected[*]}")

  local count
  count=$(write_config "$output" "$csv" "$tmpfile")

  printf "\n"
  ok "Generated .cursor/mcp.json with ${count} server(s)"
  info "Path: $output"
  info "Restart Cursor or reload window to activate MCP servers."
  printf "\n"
}

main "$@"
