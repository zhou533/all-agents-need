#!/usr/bin/env bash
set -euo pipefail

# =========================================================================
#  AAN (All Agents Need) — Claude Code Project Installer
# =========================================================================
#  Discovers spec directories (agents, commands, rules, skills, templates)
#  and installs them into the host project's .claude/ folder.
#  Optionally configures MCP servers in .claude/settings.local.json.
#
#  Dependencies: gum  →  brew install gum
#                jq   →  brew install jq
#
#  Usage:
#    bash aan/install/claude/install.sh
#    bash aan/install/claude/install.sh --project-root /path/to/project
# =========================================================================

VERSION="1.0.0"

# ---- Dependency check ----------------------------------------------------
if ! command -v gum &>/dev/null; then
  echo ""
  echo "  gum is required but not found."
  echo "  Install:  brew install gum"
  echo ""
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo ""
  echo "  jq is required but not found."
  echo "  Install:  brew install jq"
  echo ""
  exit 1
fi

# ---- Path resolution -----------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ---- Defaults ------------------------------------------------------------
FORCE=false
UNINSTALL=false
DRY_RUN=false
USE_COPY=false
PROJECT_ROOT=""
SPEC_EXTENSIONS=("md" "mdc")
# Directories excluded from auto-discovery
EXCLUDE_DIRS=(".git" ".claude" "node_modules" "__pycache__" ".venv" "docs" "install" "mcp")

# ---- Helpers (gum-based) -------------------------------------------------
header() {
  gum style --border double --align center --padding "1 4" \
    --border-foreground 99 --foreground 99 --bold \
    "AAN Installer v${VERSION}" "Claude Code"
}

info()  { gum style --foreground 6 "ℹ  $*"; }
ok()    { gum style --foreground 2 "✓  $*"; }
warn()  { gum style --foreground 3 "⚠  $*"; }
err()   { gum style --foreground 1 "✗  $*" >&2; }
label() { gum style --bold "$*"; }

relpath() {
  python3 -c "import os.path,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$1" "$2"
}

# ---- Path Resolution -----------------------------------------------------
resolve_paths() {
  if [[ -n "$PROJECT_ROOT" ]]; then
    PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
    return
  fi

  # Method 1: git superproject (works when we are a submodule)
  local super
  super="$(cd "$REPO_ROOT" && git rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  if [[ -n "$super" ]]; then
    PROJECT_ROOT="$super"
    return
  fi

  # Method 2: walk up from REPO_ROOT looking for a parent .git
  local dir="$REPO_ROOT"
  while [[ "$dir" != "/" ]]; do
    dir="$(dirname "$dir")"
    if [[ -d "$dir/.git" || -f "$dir/.git" ]]; then
      PROJECT_ROOT="$dir"
      return
    fi
  done

  err "Could not detect project root."
  err "Run with --project-root <path> to specify it manually."
  exit 1
}

# ---- Deny permissions in .claude/settings.json ---------------------------
ensure_deny_permissions() {
  local settings_dir="$PROJECT_ROOT/.claude"
  local settings_file="$settings_dir/settings.json"
  # Derive the submodule directory name under project root
  # e.g. user ran: git submodule add <url> aan  →  aan_rel="aan"
  local aan_rel="${REPO_ROOT#"$PROJECT_ROOT"/}"
  if [[ "$aan_rel" == "$REPO_ROOT" ]]; then
    err "AAN repo is not under project root — cannot compute submodule path."
    err "Ensure the AAN repo is a submodule of the project."
    return 1
  fi

  # Deny patterns to prevent Claude from reading the AAN submodule
  local deny_patterns=(
    "Read ${aan_rel}/**"
    "Glob ${aan_rel}/**"
    "Grep ${aan_rel}/**"
  )

  if $DRY_RUN; then
    info "Would add permissions.deny to $settings_file:"
    for p in "${deny_patterns[@]}"; do
      info "  - $p"
    done
    return
  fi

  mkdir -p "$settings_dir"

  # Create settings.json if it doesn't exist
  if [[ ! -f "$settings_file" ]]; then
    echo '{}' > "$settings_file"
  fi

  # Merge deny patterns into permissions.deny (deduplicated)
  local updated
  updated=$(jq --argjson new "$(printf '%s\n' "${deny_patterns[@]}" | jq -R . | jq -s .)" '
    .permissions.deny = ((.permissions.deny // []) + $new | unique)
  ' "$settings_file") || { err "Failed to update $settings_file"; return 1; }

  echo "$updated" > "$settings_file"
  ok "Updated .claude/settings.json (deny read access to ${aan_rel}/)"
}

# ---- Discovery -----------------------------------------------------------

# Discover all installable spec directories (flat or nested)
discover_spec_dirs() {
  local dirs=()
  for dir in "$REPO_ROOT"/*/; do
    [[ -d "$dir" ]] || continue
    local dirname
    dirname="$(basename "$dir")"

    local skip=false
    for ex in "${EXCLUDE_DIRS[@]}"; do
      [[ "$dirname" == "$ex" ]] && { skip=true; break; }
    done
    $skip && continue

    local found=false
    # Check for flat spec files
    for ext in "${SPEC_EXTENSIONS[@]}"; do
      if compgen -G "$dir*.$ext" > /dev/null 2>&1; then
        found=true; break
      fi
    done
    # Check for nested structure (subdirs containing spec files)
    if ! $found; then
      for subdir in "$dir"/*/; do
        [[ -d "$subdir" ]] || continue
        for ext in "${SPEC_EXTENSIONS[@]}"; do
          if compgen -G "$subdir*.$ext" > /dev/null 2>&1; then
            found=true; break 2
          fi
        done
      done
    fi
    $found && dirs+=("$dirname")
  done
  echo "${dirs[@]}"
}

# Classify a spec directory as "flat", "nested-skills" (symlink subdirs),
# or "nested-rules" (preserve subdirs, symlink files within)
classify_dir() {
  local dir="$REPO_ROOT/$1"

  # Check if it has subdirectories with spec files
  local has_nested=false
  for subdir in "$dir"/*/; do
    [[ -d "$subdir" ]] || continue
    for ext in "${SPEC_EXTENSIONS[@]}"; do
      if compgen -G "$subdir*.$ext" > /dev/null 2>&1; then
        has_nested=true; break 2
      fi
    done
  done

  if ! $has_nested; then
    echo "flat"
    return
  fi

  # skills → symlink entire subdirectory; rules → symlink files within subdirs
  case "$1" in
    skills) echo "nested-skills" ;;
    *)      echo "nested-rules" ;;
  esac
}

# Count files in a spec directory
count_spec_files() {
  local dir="$REPO_ROOT/$1"
  local count=0
  local kind
  kind="$(classify_dir "$1")"

  case "$kind" in
    flat)
      for ext in "${SPEC_EXTENSIONS[@]}"; do
        for f in "$dir"/*."$ext"; do
          [[ -f "$f" ]] && count=$((count + 1))
        done
      done
      ;;
    nested-skills)
      for subdir in "$dir"/*/; do
        [[ -d "$subdir" ]] || continue
        local has_specs=false
        for ext in "${SPEC_EXTENSIONS[@]}"; do
          if compgen -G "$subdir*.$ext" > /dev/null 2>&1; then
            has_specs=true; break
          fi
        done
        $has_specs && count=$((count + 1))
      done
      ;;
    nested-rules)
      for subdir in "$dir"/*/; do
        [[ -d "$subdir" ]] || continue
        for ext in "${SPEC_EXTENSIONS[@]}"; do
          for f in "$subdir"*."$ext"; do
            [[ -f "$f" ]] && count=$((count + 1))
          done
        done
      done
      ;;
  esac
  echo "$count"
}

# Build display label for a spec directory (for gum choose)
build_dir_label() {
  local dirname="$1"
  local count
  count="$(count_spec_files "$dirname")"
  local kind
  kind="$(classify_dir "$dirname")"

  local detail=""
  case "$kind" in
    flat)           detail="${count} file(s)" ;;
    nested-skills)  detail="${count} skill(s)" ;;
    nested-rules)
      local groups=()
      for subdir in "$REPO_ROOT/$dirname"/*/; do
        [[ -d "$subdir" ]] && groups+=("$(basename "$subdir")")
      done
      detail="sets: $(IFS=', '; echo "${groups[*]}")"
      ;;
  esac

  printf "%-14s  %s" "$dirname/" "$detail"
}

# ---- Install functions ---------------------------------------------------

# Install flat spec directory: symlink each file
install_flat() {
  local spec_dir="$1"
  local source_dir="$REPO_ROOT/$spec_dir"
  local target_dir="$PROJECT_ROOT/.claude/$spec_dir"
  local installed=0 skipped=0 updated=0 up_to_date=0

  $DRY_RUN || mkdir -p "$target_dir"

  for ext in "${SPEC_EXTENSIONS[@]}"; do
    for file in "$source_dir"/*."$ext"; do
      [[ -f "$file" ]] || continue
      local filename
      filename="$(basename "$file")"
      local target="$target_dir/$filename"
      local rel
      rel="$(relpath "$file" "$target_dir")"

      if [[ -L "$target" ]]; then
        local current_link
        current_link="$(cd "$(dirname "$target")" && readlink "$(basename "$target")" 2>/dev/null || true)"
        if [[ "$current_link" == "$rel" ]]; then
          up_to_date=$((up_to_date + 1))
        elif $DRY_RUN; then
          info "Would update: .claude/$spec_dir/$filename"
          updated=$((updated + 1))
        elif $FORCE || gum confirm "Overwrite .claude/$spec_dir/$filename?"; then
          ln -sf "$rel" "$target"
          updated=$((updated + 1))
        else
          skipped=$((skipped + 1))
        fi
      elif [[ -f "$target" ]]; then
        if $DRY_RUN; then
          warn "Would overwrite: .claude/$spec_dir/$filename"
          updated=$((updated + 1))
        elif $FORCE || gum confirm "Overwrite existing .claude/$spec_dir/$filename?"; then
          if $USE_COPY; then
            cp "$file" "$target"
          else
            rm "$target"
            ln -s "$rel" "$target"
          fi
          updated=$((updated + 1))
        else
          skipped=$((skipped + 1))
        fi
      else
        if $DRY_RUN; then
          ok "Would install: .claude/$spec_dir/$filename"
        elif $USE_COPY; then
          cp "$file" "$target"
        else
          ln -s "$rel" "$target"
        fi
        installed=$((installed + 1))
      fi
    done
  done

  print_stats "$spec_dir" "$installed" "$updated" "$up_to_date" "$skipped"
}

# Install nested-skills: symlink entire subdirectories
install_nested_skills() {
  local spec_dir="$1"
  local source_dir="$REPO_ROOT/$spec_dir"
  local target_dir="$PROJECT_ROOT/.claude/$spec_dir"
  local installed=0 skipped=0 updated=0 up_to_date=0

  $DRY_RUN || mkdir -p "$target_dir"

  for subdir in "$source_dir"/*/; do
    [[ -d "$subdir" ]] || continue
    local subdirname
    subdirname="$(basename "$subdir")"

    local has_specs=false
    for ext in "${SPEC_EXTENSIONS[@]}"; do
      if compgen -G "$subdir*.$ext" > /dev/null 2>&1; then
        has_specs=true; break
      fi
    done
    $has_specs || continue

    local target="$target_dir/$subdirname"
    local rel
    rel="$(relpath "$subdir" "$target_dir")"
    rel="${rel%/}"

    if [[ -L "$target" ]]; then
      local current_link
      current_link="$(cd "$(dirname "$target")" && readlink "$(basename "$target")" 2>/dev/null || true)"
      if [[ "$current_link" == "$rel" ]]; then
        up_to_date=$((up_to_date + 1))
      elif $DRY_RUN; then
        info "Would update: .claude/$spec_dir/$subdirname"
        updated=$((updated + 1))
      elif $FORCE || gum confirm "Overwrite .claude/$spec_dir/$subdirname/?"; then
        ln -sfn "$rel" "$target"
        updated=$((updated + 1))
      else
        skipped=$((skipped + 1))
      fi
    elif [[ -d "$target" ]]; then
      if $DRY_RUN; then
        warn "Would replace dir: .claude/$spec_dir/$subdirname"
        updated=$((updated + 1))
      elif $FORCE || gum confirm "Replace directory .claude/$spec_dir/$subdirname/?"; then
        if $USE_COPY; then
          rm -rf "$target"
          cp -R "$subdir" "$target"
        else
          rm -rf "$target"
          ln -s "$rel" "$target"
        fi
        updated=$((updated + 1))
      else
        skipped=$((skipped + 1))
      fi
    else
      if $DRY_RUN; then
        ok "Would install: .claude/$spec_dir/$subdirname/"
      elif $USE_COPY; then
        cp -R "$subdir" "$target"
      else
        ln -s "$rel" "$target"
      fi
      installed=$((installed + 1))
    fi
  done

  print_stats "$spec_dir" "$installed" "$updated" "$up_to_date" "$skipped"
}

# Install nested-rules: preserve subdirectory structure, symlink files within
# Accepts optional list of selected rule sets; if empty, installs all.
install_nested_rules() {
  local spec_dir="$1"
  shift
  local selected_sets=("$@")
  local source_dir="$REPO_ROOT/$spec_dir"
  local target_dir="$PROJECT_ROOT/.claude/$spec_dir"
  local installed=0 skipped=0 updated=0 up_to_date=0

  for subdir in "$source_dir"/*/; do
    [[ -d "$subdir" ]] || continue
    local setname
    setname="$(basename "$subdir")"

    # Filter by selected sets if provided
    if (( ${#selected_sets[@]} > 0 )); then
      local match=false
      for s in "${selected_sets[@]}"; do
        [[ "$s" == "$setname" ]] && { match=true; break; }
      done
      $match || continue
    fi

    local sub_target="$target_dir/$setname"
    $DRY_RUN || mkdir -p "$sub_target"

    for ext in "${SPEC_EXTENSIONS[@]}"; do
      for file in "$subdir"*."$ext"; do
        [[ -f "$file" ]] || continue
        local filename
        filename="$(basename "$file")"
        local target="$sub_target/$filename"
        local rel
        rel="$(relpath "$file" "$sub_target")"

        if [[ -L "$target" ]]; then
          local current_link
          current_link="$(cd "$(dirname "$target")" && readlink "$(basename "$target")" 2>/dev/null || true)"
          if [[ "$current_link" == "$rel" ]]; then
            up_to_date=$((up_to_date + 1))
          elif $DRY_RUN; then
            info "Would update: .claude/$spec_dir/$setname/$filename"
            updated=$((updated + 1))
          elif $FORCE || gum confirm "Overwrite .claude/$spec_dir/$setname/$filename?"; then
            ln -sf "$rel" "$target"
            updated=$((updated + 1))
          else
            skipped=$((skipped + 1))
          fi
        elif [[ -f "$target" ]]; then
          if $DRY_RUN; then
            warn "Would overwrite: .claude/$spec_dir/$setname/$filename"
            updated=$((updated + 1))
          elif $FORCE || gum confirm "Overwrite .claude/$spec_dir/$setname/$filename?"; then
            if $USE_COPY; then
              cp "$file" "$target"
            else
              rm "$target"
              ln -s "$rel" "$target"
            fi
            updated=$((updated + 1))
          else
            skipped=$((skipped + 1))
          fi
        else
          if $DRY_RUN; then
            ok "Would install: .claude/$spec_dir/$setname/$filename"
          elif $USE_COPY; then
            cp "$file" "$target"
          else
            ln -s "$rel" "$target"
          fi
          installed=$((installed + 1))
        fi
      done
    done
  done

  print_stats "$spec_dir" "$installed" "$updated" "$up_to_date" "$skipped"
}

# ---- Uninstall functions -------------------------------------------------

uninstall_flat() {
  local spec_dir="$1"
  local target_dir="$PROJECT_ROOT/.claude/$spec_dir"
  local removed=0

  [[ -d "$target_dir" ]] || return 0

  for ext in "${SPEC_EXTENSIONS[@]}"; do
    for target in "$target_dir"/*."$ext"; do
      [[ -L "$target" ]] || continue
      local link_dest
      link_dest="$(cd "$(dirname "$target")" && readlink "$(basename "$target")")"
      local resolved
      resolved="$(cd "$(dirname "$target")" && cd "$(dirname "$link_dest")" 2>/dev/null && pwd)/$(basename "$link_dest")"

      if [[ "$resolved" == "$REPO_ROOT"/* ]]; then
        if $DRY_RUN; then
          info "Would remove: .claude/$spec_dir/$(basename "$target")"
        else
          rm "$target"
        fi
        removed=$((removed + 1))
      fi
    done
  done

  if ! $DRY_RUN && [[ -d "$target_dir" ]]; then
    rmdir "$target_dir" 2>/dev/null || true
  fi

  if (( removed > 0 )); then
    ok "Removed $removed file(s) from $spec_dir/"
  else
    info "Nothing to remove in $spec_dir/"
  fi
}

uninstall_nested_skills() {
  local spec_dir="$1"
  local target_dir="$PROJECT_ROOT/.claude/$spec_dir"
  local removed=0

  [[ -d "$target_dir" ]] || return 0

  for target in "$target_dir"/*/; do
    [[ -L "${target%/}" ]] || continue
    local link_dest
    link_dest="$(cd "$(dirname "${target%/}")" && readlink "$(basename "${target%/}")")"
    local resolved
    resolved="$(cd "$(dirname "${target%/}")" && cd "$link_dest" 2>/dev/null && pwd)"

    if [[ "$resolved" == "$REPO_ROOT"/* ]]; then
      if $DRY_RUN; then
        info "Would remove: .claude/$spec_dir/$(basename "$target")"
      else
        rm "${target%/}"
      fi
      removed=$((removed + 1))
    fi
  done

  if ! $DRY_RUN && [[ -d "$target_dir" ]]; then
    rmdir "$target_dir" 2>/dev/null || true
  fi

  if (( removed > 0 )); then
    ok "Removed $removed skill(s) from $spec_dir/"
  else
    info "Nothing to remove in $spec_dir/"
  fi
}

uninstall_nested_rules() {
  local spec_dir="$1"
  local target_dir="$PROJECT_ROOT/.claude/$spec_dir"
  local removed=0

  [[ -d "$target_dir" ]] || return 0

  for sub_target in "$target_dir"/*/; do
    [[ -d "$sub_target" ]] || continue
    for ext in "${SPEC_EXTENSIONS[@]}"; do
      for target in "$sub_target"*."$ext"; do
        [[ -L "$target" ]] || continue
        local link_dest
        link_dest="$(cd "$(dirname "$target")" && readlink "$(basename "$target")")"
        local resolved
        resolved="$(cd "$(dirname "$target")" && cd "$(dirname "$link_dest")" 2>/dev/null && pwd)/$(basename "$link_dest")"

        if [[ "$resolved" == "$REPO_ROOT"/* ]]; then
          if $DRY_RUN; then
            info "Would remove: .claude/$spec_dir/$(basename "$sub_target")/$(basename "$target")"
          else
            rm "$target"
          fi
          removed=$((removed + 1))
        fi
      done
    done
    if ! $DRY_RUN; then
      rmdir "$sub_target" 2>/dev/null || true
    fi
  done

  if ! $DRY_RUN && [[ -d "$target_dir" ]]; then
    rmdir "$target_dir" 2>/dev/null || true
  fi

  if (( removed > 0 )); then
    ok "Removed $removed rule(s) from $spec_dir/"
  else
    info "Nothing to remove in $spec_dir/"
  fi
}

# ---- Stats printer -------------------------------------------------------
print_stats() {
  local dir="$1" installed="$2" updated="$3" up_to_date="$4" skipped="$5"
  if $DRY_RUN; then return; fi
  local parts=()
  (( installed > 0 ))  && parts+=("${installed} installed")
  (( updated > 0 ))    && parts+=("${updated} updated")
  (( up_to_date > 0 )) && parts+=("${up_to_date} up-to-date")
  (( skipped > 0 ))    && parts+=("${skipped} skipped")
  if (( ${#parts[@]} > 0 )); then
    ok "$dir/: $(IFS=', '; echo "${parts[*]}")"
  fi
}

# ---- Argument parsing ----------------------------------------------------
usage() {
  gum style --border normal --padding "1 2" --border-foreground 99 \
    "AAN Installer v${VERSION} — Claude Code" \
    "" \
    "Usage: bash install.sh [OPTIONS]" \
    "" \
    "Options:" \
    "  --project-root PATH   Project root (auto-detected by default)" \
    "  --force               Overwrite without confirmation" \
    "  --copy                Copy files instead of symlinks" \
    "  --uninstall           Remove installed symlinks" \
    "  --dry-run             Preview changes only" \
    "  -h, --help            Show this help"
}

# ---- Main ----------------------------------------------------------------
main() {
  local show_help=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) PROJECT_ROOT="$2"; shift 2 ;;
      --force)        FORCE=true;        shift ;;
      --copy)         USE_COPY=true;     shift ;;
      --uninstall)    UNINSTALL=true;    shift ;;
      --dry-run)      DRY_RUN=true;      shift ;;
      -h|--help)      show_help=true;    shift ;;
      *) err "Unknown option: $1"; usage; exit 1 ;;
    esac
  done

  if $show_help; then
    usage
    exit 0
  fi

  resolve_paths

  echo ""
  header
  echo ""
  info "AAN repo:     $REPO_ROOT"
  info "Project root: $PROJECT_ROOT"
  info "Target:       $PROJECT_ROOT/.claude/"
  $DRY_RUN  && warn "Mode: dry-run (no changes will be made)"
  $USE_COPY && warn "Mode: copy (files will be copied, not symlinked)"
  $UNINSTALL && warn "Mode: uninstall"

  # Deny Claude agent access to the AAN submodule directory
  ensure_deny_permissions

  # Discover spec directories
  local spec_dirs_str
  spec_dirs_str="$(discover_spec_dirs)"
  local spec_dirs
  read -ra spec_dirs <<< "$spec_dirs_str"

  if [[ ${#spec_dirs[@]} -eq 0 ]]; then
    warn "No spec directories found in $REPO_ROOT"
    exit 0
  fi

  # ---- Uninstall mode ----------------------------------------------------
  if $UNINSTALL; then
    echo ""
    label "Removing installed specs..."
    echo ""
    for dir in "${spec_dirs[@]}"; do
      local kind
      kind="$(classify_dir "$dir")"
      case "$kind" in
        flat)           uninstall_flat "$dir" ;;
        nested-skills)  uninstall_nested_skills "$dir" ;;
        nested-rules)   uninstall_nested_rules "$dir" ;;
      esac
    done
    echo ""
    if $DRY_RUN; then
      info "Dry-run complete. No changes were made."
    else
      ok "Uninstall complete."
    fi
    return
  fi

  # ---- Install mode: select categories -----------------------------------
  echo ""
  local options=()
  for dir in "${spec_dirs[@]}"; do
    options+=("$(build_dir_label "$dir")")
  done

  local selected
  selected=$(printf '%s\n' "${options[@]}" | gum choose --no-limit \
    --header="Select categories to install  (SPACE toggle, ENTER confirm)" \
    --cursor.foreground="6" \
    --selected.foreground="2" \
    --header.foreground="99") || { warn "No selection made."; exit 0; }

  local selected_dirs=()
  while IFS= read -r line; do
    local name="${line%% *}"
    name="${name%/}"
    selected_dirs+=("$name")
  done <<< "$selected"

  # ---- For rules: select which rule sets ---------------------------------
  local selected_rule_sets=()
  for dir in "${selected_dirs[@]}"; do
    if [[ "$(classify_dir "$dir")" == "nested-rules" ]]; then
      local rule_groups=()
      for subdir in "$REPO_ROOT/$dir"/*/; do
        [[ -d "$subdir" ]] || continue
        local setname
        setname="$(basename "$subdir")"
        local fcount=0
        for ext in "${SPEC_EXTENSIONS[@]}"; do
          for f in "$subdir"*."$ext"; do
            [[ -f "$f" ]] && fcount=$((fcount + 1))
          done
        done
        rule_groups+=("$(printf "%-14s  %s file(s)" "$setname" "$fcount")")
      done

      if (( ${#rule_groups[@]} > 1 )); then
        echo ""
        local rule_sel
        rule_sel=$(printf '%s\n' "${rule_groups[@]}" | gum choose --no-limit \
          --header="Select rule sets to install  (SPACE toggle, ENTER confirm)" \
          --cursor.foreground="6" \
          --selected.foreground="2" \
          --header.foreground="99") || true
        if [[ -n "$rule_sel" ]]; then
          while IFS= read -r line; do
            selected_rule_sets+=("${line%% *}")
          done <<< "$rule_sel"
        fi
      fi
    fi
  done

  # ---- Install selected categories ---------------------------------------
  echo ""
  label "Installing into .claude/..."
  echo ""

  for dir in "${selected_dirs[@]}"; do
    local kind
    kind="$(classify_dir "$dir")"
    case "$kind" in
      flat)           install_flat "$dir" ;;
      nested-skills)  install_nested_skills "$dir" ;;
      nested-rules)   install_nested_rules "$dir" "${selected_rule_sets[@]}" ;;
    esac
  done

  # ---- Summary -----------------------------------------------------------
  echo ""
  if $DRY_RUN; then
    info "Dry-run complete. No changes were made."
  else
    ok "Install complete."
    echo ""
    info "To update after pulling changes, re-run:"
    info "  bash $(relpath "${SCRIPT_DIR}" "$PROJECT_ROOT")/install.sh"
  fi
  echo ""
}

main "$@"
