#!/usr/bin/env bash
set -euo pipefail

# =========================================================================
#  AAN — Claude Code MCP Server Configurator (gum + jq)
# =========================================================================
#  Interactive multi-select installer that reads mcp/mcp-servers.json and
#  merges selected servers into the appropriate config file based on scope.
#
#  Claude Code MCP installation scopes:
#    local   → ~/.claude.json  (project-specific, private, default)
#    project → .mcp.json       (project root, shared via version control)
#    user    → ~/.claude.json  (cross-project, private)
#
#  This script preserves all existing keys when merging.
#
#  Dependencies: jq, gum  →  brew install jq gum
#
#  Usage:
#    bash aan/install/claude/init-mcp.sh
#    bash aan/install/claude/init-mcp.sh --scope project
#    bash aan/install/claude/init-mcp.sh --project-root /path/to/project
# =========================================================================

VERSION="1.0.0"

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

# ---- Helpers (gum-based) --------------------------------------------------
header() {
  gum style --border double --align center --padding "1 4" \
    --border-foreground 99 --foreground 99 --bold \
    "AAN MCP Configurator v${VERSION}" "Claude Code"
}

info()  { gum style --foreground 6 "ℹ  $*"; }
ok()    { gum style --foreground 2 "✓  $*"; }
warn()  { gum style --foreground 3 "⚠  $*"; }
err()   { gum style --foreground 1 "✗  $*" >&2; }

# ---- Path resolution -------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MCP_JSON="$REPO_ROOT/mcp/mcp-servers.json"

[[ -f "$MCP_JSON" ]] || { err "MCP config not found: $MCP_JSON"; exit 1; }

PROJECT_ROOT=""
SCOPE=""
CLAUDE_JSON="$HOME/.claude.json"

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

# ---- Scope-aware settings file resolution ---------------------------------

# Returns the settings file path for the selected scope
resolve_settings_file() {
  case "$SCOPE" in
    local|user) echo "$CLAUDE_JSON" ;;
    project)    echo "$PROJECT_ROOT/.mcp.json" ;;
  esac
}

# Returns a human-readable scope description
scope_description() {
  case "$SCOPE" in
    local)   echo "local   → ~/.claude.json (project-specific, private)" ;;
    project) echo "project → .mcp.json (shared via version control)" ;;
    user)    echo "user    → ~/.claude.json (cross-project, private)" ;;
  esac
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

# ---- Build new mcpServers object from selection ----------------------------
build_mcp_servers() {
  local selected_csv="$1" overrides_file="$2"

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

  jq -n --argjson selected "$selected_json" \
        --argjson overrides "$overrides_json" \
        --slurpfile src "$MCP_JSON" '
    $src[0].mcpServers as $all |
    ([$selected[] |
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
  '
}

# ---- Scope-aware read/write for mcpServers --------------------------------

# Read existing mcpServers from the correct location based on scope
read_mcp_servers() {
  local settings_file="$1"
  [[ -f "$settings_file" ]] || { echo "{}"; return; }

  case "$SCOPE" in
    local)
      jq -r --arg path "$PROJECT_ROOT" '
        .projects[$path].mcpServers // {}
      ' "$settings_file" 2>/dev/null || echo "{}"
      ;;
    user|project)
      jq -r '.mcpServers // {}' "$settings_file" 2>/dev/null || echo "{}"
      ;;
  esac
}

# Write mcpServers into the correct location based on scope
write_settings() {
  local output="$1" new_servers="$2"

  mkdir -p "$(dirname "$output")"

  case "$SCOPE" in
    local)
      # ~/.claude.json → .projects."<project_path>".mcpServers
      if [[ -f "$output" ]]; then
        local merged
        merged=$(jq --arg path "$PROJECT_ROOT" --argjson new "$new_servers" '
          .projects[$path].mcpServers = ((.projects[$path].mcpServers // {}) + $new)
        ' "$output")
        echo "$merged" > "$output"
      else
        jq -n --arg path "$PROJECT_ROOT" --argjson servers "$new_servers" '
          { projects: { ($path): { mcpServers: $servers } } }
        ' > "$output"
      fi
      ;;
    user)
      # ~/.claude.json → .mcpServers (top-level)
      if [[ -f "$output" ]]; then
        local merged
        merged=$(jq --argjson new "$new_servers" '
          .mcpServers = ((.mcpServers // {}) + $new)
        ' "$output")
        echo "$merged" > "$output"
      else
        jq -n --argjson servers "$new_servers" '{ mcpServers: $servers }' > "$output"
      fi
      ;;
    project)
      # .mcp.json → .mcpServers
      if [[ -f "$output" ]]; then
        local merged
        merged=$(jq --argjson new "$new_servers" '
          .mcpServers = ((.mcpServers // {}) + $new)
        ' "$output")
        echo "$merged" > "$output"
      else
        jq -n --argjson servers "$new_servers" '{ mcpServers: $servers }' > "$output"
      fi
      ;;
  esac
}

# Clear all mcpServers for the current scope (used by "replace" strategy)
clear_mcp_servers() {
  local settings_file="$1"
  [[ -f "$settings_file" ]] || return 0

  case "$SCOPE" in
    local)
      local cleared
      cleared=$(jq --arg path "$PROJECT_ROOT" '
        .projects[$path] |= del(.mcpServers)
      ' "$settings_file")
      echo "$cleared" > "$settings_file"
      ;;
    user|project)
      local cleared
      cleared=$(jq 'del(.mcpServers)' "$settings_file")
      echo "$cleared" > "$settings_file"
      ;;
  esac
}

# Count mcpServers for the current scope
count_mcp_servers() {
  local settings_file="$1"
  read_mcp_servers "$settings_file" | jq 'length'
}

# ---- Show currently configured servers ------------------------------------
show_existing() {
  local settings_file="$1"
  [[ -f "$settings_file" ]] || return 0

  local servers_json
  servers_json=$(read_mcp_servers "$settings_file")
  local names
  names=$(echo "$servers_json" | jq -r 'keys[]' 2>/dev/null) || return 0
  [[ -z "$names" ]] && return 0

  local count
  count=$(echo "$names" | wc -l | tr -d ' ')
  warn "Existing config has $count MCP server(s) in $SCOPE scope:"
  echo "$names" | while IFS= read -r n; do
    gum style --foreground 8 "   $n"
  done
}

# ---- Main ------------------------------------------------------------------
main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) PROJECT_ROOT="$2"; shift 2 ;;
      --scope)        SCOPE="$2";        shift 2 ;;
      -h|--help)
        gum style --border normal --padding "1 2" --border-foreground 99 \
          "AAN MCP Configurator v${VERSION} — Claude Code" \
          "" \
          "Usage: bash init-mcp.sh [OPTIONS]" \
          "" \
          "Options:" \
          "  --project-root PATH   Project root (auto-detected by default)" \
          "  --scope SCOPE         Installation scope: local, project, user" \
          "  -h, --help            Show this help" \
          "" \
          "Scopes:" \
          "  local    ~/.claude.json (project-specific, private, default)" \
          "  project  .mcp.json (shared via version control)" \
          "  user     ~/.claude.json (cross-project, private)" \
          "" \
          "Dependencies: jq, gum  ->  brew install jq gum"
        exit 0 ;;
      *) err "Unknown option: $1"; exit 1 ;;
    esac
  done

  resolve_project_root

  echo ""
  header
  echo ""
  info "Project root: $PROJECT_ROOT"

  # ---- Scope selection -----------------------------------------------------
  if [[ -z "$SCOPE" ]]; then
    echo ""
    SCOPE=$(gum choose --header="Select MCP installation scope" \
      --cursor.foreground="6" \
      --selected.foreground="2" \
      --header.foreground="99" \
      "local    ~/.claude.json (project-specific, private)" \
      "project  .mcp.json (shared via version control)" \
      "user     ~/.claude.json (cross-project, private)") || { info "Cancelled."; exit 0; }
    SCOPE="${SCOPE%% *}"
  fi

  # Validate scope
  case "$SCOPE" in
    local|project|user) ;;
    *) err "Invalid scope: $SCOPE (must be local, project, or user)"; exit 1 ;;
  esac

  local settings_file
  settings_file="$(resolve_settings_file)"

  info "Scope:        $(scope_description)"
  info "Settings:     $settings_file"
  echo ""

  # Show existing MCP servers if any
  show_existing "$settings_file"

  # Ask merge strategy when existing servers are present
  local has_existing=false
  if [[ -f "$settings_file" ]]; then
    local existing_count
    existing_count=$(count_mcp_servers "$settings_file")
    if (( existing_count > 0 )); then
      has_existing=true
      echo ""
      local strategy
      strategy=$(gum choose --header="How to handle existing MCP servers?" \
        --cursor.foreground="6" \
        --header.foreground="99" \
        "merge    Add selected servers, keep existing ones" \
        "replace  Remove all existing, use only new selection" \
        "cancel   Do nothing") || { info "Cancelled."; exit 0; }
      strategy="${strategy%% *}"
      case "$strategy" in
        cancel) info "Cancelled."; exit 0 ;;
      esac
    fi
  fi

  # Server selection
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

  # Collect credentials for servers that need them
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
      if [[ "$SCOPE" == "project" ]]; then
        warn "Keys will be stored in .mcp.json — avoid committing secrets!"
      else
        warn "Keys will be stored in ~/.claude.json (private)"
      fi
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

  # Build new mcpServers object
  local csv
  csv=$(IFS=','; echo "${server_names[*]}")

  local new_servers
  new_servers=$(build_mcp_servers "$csv" "$tmpfile")

  # Write to the scope-appropriate settings file
  if $has_existing && [[ "${strategy:-merge}" == "replace" ]]; then
    clear_mcp_servers "$settings_file"
  fi

  write_settings "$settings_file" "$new_servers"

  local total
  total=$(count_mcp_servers "$settings_file")

  # Scope-specific post-install actions
  case "$SCOPE" in
    project)
      # .mcp.json should be committed — warn about secrets instead
      echo ""
      ok ".mcp.json now has $total MCP server(s)"
      info "Path: $settings_file"
      echo ""
      warn ".mcp.json is designed for version control."
      warn "Ensure no API keys/secrets are stored — use env vars instead."
      info "Team members will be prompted to approve project-scoped servers."
      ;;
    local|user)
      echo ""
      ok "~/.claude.json now has $total MCP server(s) in $SCOPE scope"
      info "Path: $settings_file"
      echo ""
      warn "~/.claude.json may contain API keys — it is private to your machine."
      if [[ "$SCOPE" == "local" ]]; then
        info "Servers are available only in: $PROJECT_ROOT"
      else
        info "Servers are available across all projects."
      fi
      ;;
  esac

  info "Run 'claude' to start Claude Code with the new MCP servers."
  echo ""
}

main "$@"
