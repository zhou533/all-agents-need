#!/usr/bin/env bash
set -euo pipefail

# =========================================================================
#  AAN — Cursor MCP Server Configurator (gum + jq)
# =========================================================================
#  Interactive multi-select installer that reads mcp/mcp-servers.json and
#  generates a Cursor-compatible .cursor/mcp.json for the host project.
#
#  Dependencies: jq, gum  →  brew install jq gum
#
#  Usage:
#    bash aan/cursor/init-mcp.sh
#    bash aan/cursor/init-mcp.sh --project-root /path/to/project
# =========================================================================

VERSION="2.0.0"

# ---- Dependency checks ----------------------------------------------------
for cmd in jq gum; do
  if ! command -v "$cmd" &>/dev/null; then
    echo ""
    echo "  $cmd is required but not found."
    echo "  Install:  brew install $cmd"
    echo ""
    exit 1
  fi
done

# ---- Colours ---------------------------------------------------------------
if [[ -t 1 ]]; then
  RST='\033[0m'; GRN='\033[32m'; YEL='\033[33m'; RED='\033[31m'
  CYN='\033[36m'; BLD='\033[1m'
else
  RST=''; GRN=''; YEL=''; RED=''; CYN=''; BLD=''
fi

info()  { printf "${CYN}ℹ${RST}  %s\n" "$*"; }
ok()    { printf "${GRN}✓${RST}  %s\n" "$*"; }
warn()  { printf "${YEL}⚠${RST}  %s\n" "$*"; }
err()   { printf "${RED}✗${RST}  %s\n" "$*" >&2; }

# ---- Path resolution -------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MCP_JSON="$REPO_ROOT/mcp/mcp-servers.json"

[[ -f "$MCP_JSON" ]] || { err "MCP config not found: $MCP_JSON"; exit 1; }

PROJECT_ROOT=""

resolve_project_root() {
  [[ -n "$PROJECT_ROOT" ]] && { PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"; return; }

  local super
  super="$(cd "$REPO_ROOT" && git rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  [[ -n "$super" ]] && { PROJECT_ROOT="$super"; return; }

  local dir="$REPO_ROOT"
  while [[ "$dir" != "/" ]]; do
    dir="$(dirname "$dir")"
    [[ -d "$dir/.git" || -f "$dir/.git" ]] && { PROJECT_ROOT="$dir"; return; }
  done

  PROJECT_ROOT="$(pwd)"
}

# ---- Build display lines for gum choose -----------------------------------
build_options() {
  jq -r '
    def pad($n): . + ("                              "[:([0, $n - length] | max)]);
    .mcpServers | to_entries[] |
    .key as $name |
    .value as $cfg |
    (($cfg.description // "") | if length > 50 then .[:47] + "..." else . end) as $desc |
    ([
      (($cfg.env // {}) | to_entries[] | select(.value | test("YOUR_|_HERE"; "i")) | .key),
      (($cfg.headers // {}) | to_entries[] | select(.value | test("YOUR_|_HERE"; "i")) | .key)
    ]) as $keys |
    (if ($keys | length) > 0 then "  [" + ($keys | join(", ")) + " required]" else "" end) as $hint |
    ($name | pad(28)) + " " + $desc + $hint
  ' "$MCP_JSON"
}

# ---- Get required env/header vars for a server ----------------------------
get_env_vars() {
  jq -r --arg name "$1" '
    .mcpServers[$name] // empty |
    (((.env // {}) | to_entries[] | select(.value | test("YOUR_|_HERE"; "i")) | .key),
     ((.headers // {}) | to_entries[] | select(.value | test("YOUR_|_HERE"; "i")) | "header:" + .key))
  ' "$MCP_JSON"
}

# ---- Write .cursor/mcp.json -----------------------------------------------
write_config() {
  local output="$1" selected_csv="$2" overrides_file="$3"

  local selected_json
  selected_json=$(echo "$selected_csv" | tr ',' '\n' | jq -R '.' | jq -s '.')

  local overrides_json="{}"
  if [[ -s "$overrides_file" ]]; then
    overrides_json=$(jq -Rn '
      [inputs | select(length > 0) |
        capture("^(?<srv>[^.]+)\\.(?<key>[^=]+)=(?<val>.+)$")]
      | group_by(.srv)
      | map({key: .[0].srv, value: (map({key: .key, value: .val}) | from_entries)})
      | from_entries
    ' < "$overrides_file")
  fi

  mkdir -p "$(dirname "$output")"

  jq -n --argjson selected "$selected_json" \
        --argjson overrides "$overrides_json" \
        --slurpfile src "$MCP_JSON" '
    $src[0].mcpServers as $all |
    {mcpServers: (
      [$selected[] |
        . as $name |
        ($all[$name] // null) |
        if . == null then empty
        else
          del(.description) |
          if $overrides[$name] then
            reduce ($overrides[$name] | to_entries[]) as {$key, $value} (.;
              if ($key | startswith("header:")) then
                .headers[($key | ltrimstr("header:"))] = $value
              else
                .env[$key] = $value
              end)
          else . end |
          {($name): .}
        end
      ] | add // {})
    }
  ' > "$output"

  jq '.mcpServers | length' "$output"
}

# ---- Main ------------------------------------------------------------------
main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) PROJECT_ROOT="$2"; shift 2 ;;
      -h|--help)
        echo "Usage: bash init-mcp.sh [--project-root PATH]"
        echo "Interactively select MCP servers and generate .cursor/mcp.json"
        echo "Dependencies: jq, gum  →  brew install jq gum"
        exit 0 ;;
      *) err "Unknown option: $1"; exit 1 ;;
    esac
  done

  resolve_project_root
  local output="$PROJECT_ROOT/.cursor/mcp.json"

  printf "\n${BLD}AAN MCP Configurator v${VERSION}${RST}\n\n"
  info "Project root: $PROJECT_ROOT"
  info "Output:       $output"

  if [[ -f "$output" ]]; then
    echo ""
    warn "Existing MCP config found: $output"
    gum confirm "Overwrite?" || { info "Cancelled."; exit 0; }
  fi

  echo ""
  local options
  options=$(build_options)

  local selected
  selected=$(echo "$options" | gum choose --no-limit \
    --header="Select MCP servers  (SPACE toggle, ENTER confirm)" \
    --cursor.foreground="6" \
    --selected.foreground="2" \
    --header.foreground="99") || { warn "No selection made."; exit 0; }

  local server_names=()
  while IFS= read -r line; do
    server_names+=("${line%% *}")
  done <<< "$selected"

  (( ${#server_names[@]} > 0 )) || { warn "No servers selected."; exit 0; }
  echo ""
  ok "Selected ${#server_names[@]} server(s): ${server_names[*]}"

  local tmpfile
  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' EXIT

  local prompted=false
  for name in "${server_names[@]}"; do
    local vars
    vars=$(get_env_vars "$name")
    [[ -z "$vars" ]] && continue

    if ! $prompted; then
      echo ""
      info "Configure credentials (leave empty to keep placeholder)"
      warn "Keys will be stored in .cursor/mcp.json (gitignored, local only)"
      prompted=true
    fi

    while IFS= read -r var; do
      local display="${var#header:}"
      local val
      val=$(gum input --placeholder="skip (keep placeholder)" \
        --header="${name} → ${display}" \
        --width=60) || true
      [[ -n "$val" ]] && echo "${name}.${var}=${val}" >> "$tmpfile"
    done <<< "$vars"
  done

  local csv
  csv=$(IFS=','; echo "${server_names[*]}")

  local count
  count=$(write_config "$output" "$csv" "$tmpfile")

  # Ensure .cursor/mcp.json is in .gitignore
  local gitignore="$PROJECT_ROOT/.gitignore"
  local pattern=".cursor/mcp.json"
  if [[ -f "$gitignore" ]]; then
    if ! grep -qxF "$pattern" "$gitignore"; then
      printf '\n# MCP config contains API keys — do not commit\n%s\n' "$pattern" >> "$gitignore"
      ok "Added $pattern to .gitignore"
    fi
  else
    printf '# MCP config contains API keys — do not commit\n%s\n' "$pattern" > "$gitignore"
    ok "Created .gitignore with $pattern"
  fi

  echo ""
  ok "Generated .cursor/mcp.json with ${count} server(s)"
  info "Path: $output"
  echo ""
  warn "mcp.json contains API keys — it has been gitignored."
  warn "Do NOT commit this file. Each developer should run this script locally."
  info "Restart Cursor or reload window to activate MCP servers."
  echo ""
}

main "$@"
