#!/usr/bin/env bash
set -euo pipefail

# =========================================================================
#  AAN — Claude Code Hook Installer (gum + jq)
# =========================================================================
#  Copies hook scripts into .claude/scripts/hooks/ and merges hook config
#  from hooks/hooks.json into .claude/settings.json.
#
#  Steps:
#    1. Copy scripts/hooks/ → <project_root>/.claude/scripts/hooks/
#    2. Rewrite ${CLAUDE_PLUGIN_ROOT} to $CLAUDE_PROJECT_DIR/.claude
#       so command paths resolve to .claude/scripts/hooks/ (matching layout)
#    3. Deep-merge the "hooks" key into .claude/settings.json
#
#  Dependencies: jq, gum  →  brew install jq gum
#
#  Usage:
#    bash aan/install/claude/init-hook.sh
#    bash aan/install/claude/init-hook.sh --project-root /path/to/project
# =========================================================================

VERSION="1.0.0"

# ---- Dependency checks ---------------------------------------------------
for cmd in jq gum; do
  if ! command -v "$cmd" &>/dev/null; then
    echo ""
    echo "  $cmd is required but not found."
    echo "  Install:  brew install $cmd"
    echo ""
    exit 1
  fi
done

# ---- Helpers (gum-based) -------------------------------------------------
header() {
  gum style --border double --align center --padding "1 4" \
    --border-foreground 99 --foreground 99 --bold \
    "AAN Hook Installer v${VERSION}" "Claude Code"
}

info()  { gum style --foreground 6 "ℹ  $*"; }
ok()    { gum style --foreground 2 "✓  $*"; }
warn()  { gum style --foreground 3 "⚠  $*"; }
err()   { gum style --foreground 1 "✗  $*" >&2; }

# ---- Path resolution -----------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"
SCRIPTS_DIR="$REPO_ROOT/scripts/hooks"

PROJECT_ROOT=""
FORCE=false
DRY_RUN=false

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

  err "Could not detect project root."
  err "Run with --project-root <path> to specify it manually."
  exit 1
}

# ---- Step 1: Copy scripts/hooks → .claude/scripts/hooks -----------------
copy_hook_scripts() {
  local src="$SCRIPTS_DIR"
  local dst="$PROJECT_ROOT/.claude/scripts/hooks"

  if [[ ! -d "$src" ]]; then
    warn "Source directory not found: $src"
    warn "Skipping hook script copy."
    return 1
  fi

  local file_count
  file_count=$(find "$src" -type f -not -name '.DS_Store' | wc -l | tr -d ' ')

  if $DRY_RUN; then
    info "Would copy $file_count file(s) from scripts/hooks/ → .claude/scripts/hooks/"
    return 0
  fi

  if [[ -d "$dst" ]] && ! $FORCE; then
    local existing_count
    existing_count=$(find "$dst" -type f -not -name '.DS_Store' | wc -l | tr -d ' ')
    if (( existing_count > 0 )); then
      warn ".claude/scripts/hooks/ already has $existing_count file(s)."
      local strategy
      strategy=$(gum choose --header="How to handle existing hook scripts?" \
        --cursor.foreground="6" \
        --header.foreground="99" \
        "merge     Overwrite matching files, keep extras" \
        "replace   Remove all existing, copy fresh" \
        "skip      Keep existing, do not copy" \
        "cancel    Abort installation") || { info "Cancelled."; exit 0; }
      strategy="${strategy%% *}"
      case "$strategy" in
        cancel) info "Cancelled."; exit 0 ;;
        skip)   info "Skipping hook script copy."; return 0 ;;
        replace) rm -rf "$dst" ;;
        merge)  ;; # default: cp -R overwrites matching files
      esac
    fi
  fi

  mkdir -p "$dst"
  # Copy all files preserving structure, excluding .DS_Store
  rsync -a --exclude='.DS_Store' "$src/" "$dst/" 2>/dev/null \
    || cp -R "$src/." "$dst/"

  local copied_count
  copied_count=$(find "$dst" -type f -not -name '.DS_Store' | wc -l | tr -d ' ')
  ok "Copied $copied_count hook script(s) → .claude/scripts/hooks/"
}

# ---- Step 2: Rewrite paths and merge hooks into settings.json ------------
merge_hooks_config() {
  local settings_file="$PROJECT_ROOT/.claude/settings.json"

  if [[ ! -f "$HOOKS_JSON" ]]; then
    err "Hook config not found: $HOOKS_JSON"
    return 1
  fi

  # Validate hooks.json has a "hooks" key
  if ! jq -e '.hooks' "$HOOKS_JSON" > /dev/null 2>&1; then
    err "hooks/hooks.json does not contain a 'hooks' key."
    return 1
  fi

  # Rewrite command paths:
  #   ${CLAUDE_PLUGIN_ROOT} → "$CLAUDE_PROJECT_DIR"/.claude
  #   This preserves the original scripts/hooks/ subdirectory structure,
  #   so e.g. ${CLAUDE_PLUGIN_ROOT}/scripts/hooks/run-with-flags.js
  #        → "$CLAUDE_PROJECT_DIR"/.claude/scripts/hooks/run-with-flags.js
  local rewritten_hooks
  rewritten_hooks=$(jq '.hooks | walk(
    if type == "string" then
      gsub("\\$\\{CLAUDE_PLUGIN_ROOT\\}"; "\"$CLAUDE_PROJECT_DIR\"/.claude")
    else . end
  )' "$HOOKS_JSON")

  if $DRY_RUN; then
    info "Would merge hooks config into $settings_file"
    info "Hook events to install:"
    echo "$rewritten_hooks" | jq -r 'keys[]' | while IFS= read -r event; do
      local count
      count=$(echo "$rewritten_hooks" | jq -r --arg e "$event" '.[$e] | length')
      info "  $event: $count hook group(s)"
    done
    return 0
  fi

  mkdir -p "$(dirname "$settings_file")"

  # Create settings.json if it doesn't exist
  if [[ ! -f "$settings_file" ]]; then
    echo '{}' > "$settings_file"
  fi

  # Deep-merge: for each hook event, concatenate arrays and deduplicate
  # by description (to allow re-running without creating duplicates)
  local merged
  merged=$(jq --argjson new_hooks "$rewritten_hooks" '
    # For each event in new_hooks, merge with existing
    .hooks as $existing_hooks |
    .hooks = (
      ($existing_hooks // {}) as $old |
      $new_hooks | to_entries | reduce .[] as $entry (
        $old;
        .[$entry.key] as $old_arr |
        if $old_arr == null then
          .[$entry.key] = $entry.value
        else
          # Deduplicate by description field
          ($old_arr | map(.description) | map(select(. != null))) as $old_descs |
          .[$entry.key] = (
            $old_arr + [
              $entry.value[] |
              select(
                .description == null or
                (.description as $d | $old_descs | index($d) == null)
              )
            ]
          )
        end
      )
    )
  ' "$settings_file")

  echo "$merged" > "$settings_file"

  local event_count
  event_count=$(echo "$merged" | jq '.hooks | keys | length')
  local total_groups
  total_groups=$(echo "$merged" | jq '[.hooks[] | length] | add // 0')
  ok "Merged hooks into .claude/settings.json ($event_count events, $total_groups hook groups)"
}

# ---- Argument parsing ----------------------------------------------------
usage() {
  gum style --border normal --padding "1 2" --border-foreground 99 \
    "AAN Hook Installer v${VERSION} — Claude Code" \
    "" \
    "Usage: bash init-hook.sh [OPTIONS]" \
    "" \
    "Options:" \
    "  --project-root PATH   Project root (auto-detected by default)" \
    "  --force               Overwrite without confirmation" \
    "  --dry-run             Preview changes only" \
    "  -h, --help            Show this help" \
    "" \
    "Dependencies: jq, gum  ->  brew install jq gum"
}

# ---- Main ----------------------------------------------------------------
main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) PROJECT_ROOT="$2"; shift 2 ;;
      --force)        FORCE=true;        shift ;;
      --dry-run)      DRY_RUN=true;      shift ;;
      -h|--help)      usage; exit 0 ;;
      *) err "Unknown option: $1"; usage; exit 1 ;;
    esac
  done

  resolve_project_root

  echo ""
  header
  echo ""
  info "AAN repo:     $REPO_ROOT"
  info "Project root: $PROJECT_ROOT"
  info "Target:       $PROJECT_ROOT/.claude/"
  $DRY_RUN && warn "Mode: dry-run (no changes will be made)"
  $FORCE   && warn "Mode: force (no confirmation prompts)"

  # Validate source files exist
  local missing=false
  [[ ! -d "$SCRIPTS_DIR" ]] && { warn "scripts/hooks/ not found"; missing=true; }
  [[ ! -f "$HOOKS_JSON" ]]  && { err  "hooks/hooks.json not found"; missing=true; }
  $missing && [[ ! -f "$HOOKS_JSON" ]] && exit 1

  # Step 1: Copy hook scripts
  echo ""
  info "Step 1: Copy hook scripts → .claude/scripts/hooks/"
  copy_hook_scripts

  # Step 2: Merge hooks config into settings.json
  echo ""
  info "Step 2: Merge hook config → .claude/settings.json"
  merge_hooks_config

  # Summary
  echo ""
  if $DRY_RUN; then
    info "Dry-run complete. No changes were made."
  else
    ok "Hook installation complete."
    echo ""
    info "Hook scripts:  .claude/scripts/hooks/"
    info "Hook config:   .claude/settings.json → hooks"
    echo ""
    info "To customize hooks, edit .claude/settings.json or use env vars:"
    info "  ECC_HOOK_PROFILE=minimal|standard|strict"
    info "  ECC_DISABLED_HOOKS=hook-id-1,hook-id-2"
  fi
  echo ""
}

main "$@"
