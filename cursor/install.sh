#!/usr/bin/env bash
set -euo pipefail

# =========================================================================
#  AAN (All Agents Need) — Cursor Project Installer
# =========================================================================
#  Discovers spec directories (agents, commands, rules, …) and symlinks
#  them into the host Cursor project's .cursor/ folder.
#
#  Typical workflow:
#    cd <your-cursor-project>
#    git submodule add <repo-url> aan
#    bash aan/cursor/install.sh
#
#  Re-run after pulling submodule updates to pick up new specs.
# =========================================================================

VERSION="1.0.0"

# ---- Colours (disabled when stdout is not a tty) -------------------------
if [[ -t 1 ]]; then
  C_RESET='\033[0m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'
  C_RED='\033[0;31m'; C_CYAN='\033[0;36m'; C_BOLD='\033[1m'
else
  C_RESET=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_CYAN=''; C_BOLD=''
fi

# ---- Helpers -------------------------------------------------------------
info()  { printf "${C_CYAN}ℹ${C_RESET}  %s\n" "$*"; }
ok()    { printf "${C_GREEN}✓${C_RESET}  %s\n" "$*"; }
warn()  { printf "${C_YELLOW}⚠${C_RESET}  %s\n" "$*"; }
err()   { printf "${C_RED}✗${C_RESET}  %s\n" "$*" >&2; }
bold()  { printf "${C_BOLD}%s${C_RESET}\n" "$*"; }

relpath() {
  python3 -c "import os.path,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$1" "$2"
}

# Returns 0 if the directory uses nested structure (subdirs with spec files),
# e.g. skills/brainstorming/SKILL.md. Returns 1 for flat structure.
is_nested_spec_dir() {
  local dir="$1"
  for subdir in "$dir"/*/; do
    [[ -d "$subdir" ]] || continue
    for ext in "${SPEC_EXTENSIONS[@]}"; do
      if compgen -G "$subdir*.$ext" > /dev/null 2>&1; then
        return 0
      fi
    done
  done
  return 1
}

# ---- Defaults ------------------------------------------------------------
FORCE=false
UNINSTALL=false
DRY_RUN=false
USE_COPY=false
OVERWRITE_ALL=false
PROJECT_ROOT=""
SPEC_EXTENSIONS=("md" "mdc")
EXCLUDE_DIRS=(".git" "node_modules" "__pycache__" ".venv" "docs" "cursor")

# ---- Interactive overwrite confirmation ----------------------------------
# Returns 0 (true) if the file should be overwritten, 1 (false) to skip.
# Sets OVERWRITE_ALL=true when user picks 'a' (all).
confirm_overwrite() {
  local filepath="$1"
  if $OVERWRITE_ALL; then return 0; fi

  while true; do
    printf "${C_YELLOW}⚠${C_RESET}  File exists: ${C_BOLD}%s${C_RESET}\n" "$filepath"
    printf "   Overwrite? [y]es / [n]o / [a]ll / [q]uit: "
    read -r choice < /dev/tty
    case "$choice" in
      y|Y) return 0 ;;
      n|N) return 1 ;;
      a|A) OVERWRITE_ALL=true; return 0 ;;
      q|Q) info "Aborted by user."; exit 0 ;;
      *)   warn "Invalid choice. Please enter y, n, a, or q." ;;
    esac
  done
}

# ---- Argument parsing ----------------------------------------------------
usage() {
  cat <<EOF
${C_BOLD}AAN Installer v${VERSION}${C_RESET}

Usage: bash install.sh [OPTIONS]

Options:
  --project-root PATH   Cursor project root (auto-detected by default)
  --force               Overwrite all conflicting files without confirmation
  --copy                Copy files instead of creating symlinks
  --uninstall           Remove previously installed symlinks
  --dry-run             Preview changes without applying them
  -h, --help            Show this help

When a file conflict is detected, you will be prompted interactively:
  [y] overwrite this file  [n] skip  [a] overwrite all remaining  [q] quit
Use --force to skip all prompts (useful for CI / automation).

Spec directories are auto-discovered: any top-level directory containing
.md or .mdc files is treated as a spec directory and mapped to
.cursor/<dir>/ in the target project.

Currently recognised spec directories in this repo:
EOF
  discover_spec_dirs_display
}

# ---- Path Resolution -----------------------------------------------------
resolve_paths() {
  # REPO_ROOT is the AAN repository root (one level up from this script)
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

  err "Could not detect Cursor project root."
  err "Run with --project-root <path> to specify it manually."
  exit 1
}

# ---- Spec Directory Discovery --------------------------------------------
discover_spec_dirs() {
  local dirs=()
  for dir in "$REPO_ROOT"/*/; do
    [[ -d "$dir" ]] || continue
    local dirname
    dirname="$(basename "$dir")"

    # Skip excluded directories
    local skip=false
    for ex in "${EXCLUDE_DIRS[@]}"; do
      [[ "$dirname" == "$ex" ]] && { skip=true; break; }
    done
    $skip && continue

    # Check flat structure (e.g. agents/*.md) or nested structure (e.g. skills/*/SKILL.md)
    local found=false
    for ext in "${SPEC_EXTENSIONS[@]}"; do
      if compgen -G "$dir*.$ext" > /dev/null 2>&1; then
        found=true; break
      fi
    done
    if ! $found && is_nested_spec_dir "$dir"; then
      found=true
    fi
    $found && dirs+=("$dirname")
  done
  echo "${dirs[@]}"
}

discover_spec_dirs_display() {
  for dir in "$REPO_ROOT"/*/; do
    [[ -d "$dir" ]] || continue
    local dirname
    dirname="$(basename "$dir")"
    local skip=false
    for ex in "${EXCLUDE_DIRS[@]}"; do
      [[ "$dirname" == "$ex" ]] && { skip=true; break; }
    done
    $skip && continue

    if is_nested_spec_dir "$dir"; then
      # Nested structure (skills): list subdirectories
      local subdirs=()
      for subdir in "$dir"/*/; do
        [[ -d "$subdir" ]] || continue
        local has_specs=false
        for ext in "${SPEC_EXTENSIONS[@]}"; do
          if compgen -G "$subdir*.$ext" > /dev/null 2>&1; then
            has_specs=true; break
          fi
        done
        $has_specs && subdirs+=("$(basename "$subdir")/")
      done
      if (( ${#subdirs[@]} > 0 )); then
        printf "  ${C_CYAN}%-12s${C_RESET} → .cursor/%-12s  (%s)\n" \
          "$dirname/" "$dirname/" "$(IFS=', '; echo "${subdirs[*]}")"
      fi
    else
      # Flat structure (agents, commands, rules): list files
      local count=0
      for ext in "${SPEC_EXTENSIONS[@]}"; do
        for f in "$dir"*."$ext"; do
          [[ -f "$f" ]] && count=$((count + 1))
        done
      done
      if (( count > 0 )); then
        local files=()
        for ext in "${SPEC_EXTENSIONS[@]}"; do
          for f in "$dir"*."$ext"; do
            [[ -f "$f" ]] && files+=("$(basename "$f")")
          done
        done
        printf "  ${C_CYAN}%-12s${C_RESET} → .cursor/%-12s  (%s)\n" \
          "$dirname/" "$dirname/" "$(IFS=', '; echo "${files[*]}")"
      fi
    fi
  done
}

# ---- Install / Uninstall ------------------------------------------------
install_spec_dir() {
  local spec_dir="$1"
  local source_dir="$REPO_ROOT/$spec_dir"
  local target_dir="$PROJECT_ROOT/.cursor/$spec_dir"
  local installed=0 skipped=0 updated=0

  bold "  $spec_dir/"

  if ! $DRY_RUN; then
    mkdir -p "$target_dir"
  fi

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
          skipped=$((skipped + 1))
        elif $DRY_RUN; then
          info "Would update symlink: .cursor/$spec_dir/$filename"
          updated=$((updated + 1))
        elif $FORCE || confirm_overwrite ".cursor/$spec_dir/$filename"; then
          ln -sf "$rel" "$target"
          updated=$((updated + 1))
        else
          warn "Skipped: $filename"
          skipped=$((skipped + 1))
        fi
      elif [[ -f "$target" ]]; then
        if $DRY_RUN; then
          warn "Would overwrite: .cursor/$spec_dir/$filename"
          updated=$((updated + 1))
        elif $FORCE || confirm_overwrite ".cursor/$spec_dir/$filename"; then
          if $USE_COPY; then
            cp "$file" "$target"
          else
            rm "$target"
            ln -s "$rel" "$target"
          fi
          updated=$((updated + 1))
        else
          warn "Skipped: $filename"
          skipped=$((skipped + 1))
        fi
      else
        if $DRY_RUN; then
          ok "Would install: .cursor/$spec_dir/$filename"
        elif $USE_COPY; then
          cp "$file" "$target"
        else
          ln -s "$rel" "$target"
        fi
        installed=$((installed + 1))
      fi
    done
  done

  if ! $DRY_RUN; then
    if (( installed > 0 )); then ok "Installed $installed new file(s)"; fi
    if (( updated > 0 ));   then ok "Updated $updated file(s)"; fi
    if (( skipped > 0 ));   then warn "Skipped $skipped file(s)"; fi
  fi
}

install_nested_spec_dir() {
  local spec_dir="$1"
  local source_dir="$REPO_ROOT/$spec_dir"
  local target_dir="$PROJECT_ROOT/.cursor/$spec_dir"
  local installed=0 skipped=0 updated=0

  bold "  $spec_dir/ (nested)"

  if ! $DRY_RUN; then
    mkdir -p "$target_dir"
  fi

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
        skipped=$((skipped + 1))
      elif $DRY_RUN; then
        info "Would update symlink: .cursor/$spec_dir/$subdirname"
        updated=$((updated + 1))
      elif $FORCE || confirm_overwrite ".cursor/$spec_dir/$subdirname"; then
        ln -sfn "$rel" "$target"
        updated=$((updated + 1))
      else
        warn "Skipped: $subdirname/"
        skipped=$((skipped + 1))
      fi
    elif [[ -d "$target" ]]; then
      if $DRY_RUN; then
        warn "Would replace directory: .cursor/$spec_dir/$subdirname"
        updated=$((updated + 1))
      elif $FORCE || confirm_overwrite ".cursor/$spec_dir/$subdirname"; then
        if $USE_COPY; then
          rm -rf "$target"
          cp -R "$subdir" "$target"
        else
          rm -rf "$target"
          ln -s "$rel" "$target"
        fi
        updated=$((updated + 1))
      else
        warn "Skipped: $subdirname/"
        skipped=$((skipped + 1))
      fi
    else
      if $DRY_RUN; then
        ok "Would install: .cursor/$spec_dir/$subdirname/"
      elif $USE_COPY; then
        cp -R "$subdir" "$target"
      else
        ln -s "$rel" "$target"
      fi
      installed=$((installed + 1))
    fi
  done

  if ! $DRY_RUN; then
    if (( installed > 0 )); then ok "Installed $installed skill(s)"; fi
    if (( updated > 0 ));   then ok "Updated $updated skill(s)"; fi
    if (( skipped > 0 ));   then warn "Skipped $skipped skill(s)"; fi
  fi
}

uninstall_nested_spec_dir() {
  local spec_dir="$1"
  local target_dir="$PROJECT_ROOT/.cursor/$spec_dir"
  local removed=0

  [[ -d "$target_dir" ]] || return 0

  bold "  $spec_dir/ (nested)"

  for target in "$target_dir"/*/; do
    [[ -L "${target%/}" ]] || continue
    local subdirname
    subdirname="$(basename "$target")"
    local link_dest
    link_dest="$(cd "$(dirname "${target%/}")" && readlink "$(basename "${target%/}")")"
    local resolved
    resolved="$(cd "$(dirname "${target%/}")" && cd "$link_dest" 2>/dev/null && pwd)"

    if [[ "$resolved" == "$REPO_ROOT"/* ]]; then
      if $DRY_RUN; then
        info "Would remove: .cursor/$spec_dir/$subdirname"
      else
        rm "${target%/}"
      fi
      removed=$((removed + 1))
    fi
  done

  if ! $DRY_RUN && [[ -d "$target_dir" ]]; then
    rmdir "$target_dir" 2>/dev/null && info "Removed empty directory: .cursor/$spec_dir/" || true
  fi

  if ! $DRY_RUN; then
    if (( removed > 0 )); then
      ok "Removed $removed skill(s)"
    else
      info "Nothing to remove"
    fi
  fi
}

uninstall_spec_dir() {
  local spec_dir="$1"
  local target_dir="$PROJECT_ROOT/.cursor/$spec_dir"
  local removed=0

  [[ -d "$target_dir" ]] || return 0

  bold "  $spec_dir/"

  for ext in "${SPEC_EXTENSIONS[@]}"; do
    for target in "$target_dir"/*."$ext"; do
      [[ -L "$target" ]] || continue
      # Resolve symlink and check if it points into our repo
      local link_dest
      link_dest="$(cd "$(dirname "$target")" && readlink "$(basename "$target")")"
      local resolved
      resolved="$(cd "$(dirname "$target")" && cd "$(dirname "$link_dest")" 2>/dev/null && pwd)/$(basename "$link_dest")"

      if [[ "$resolved" == "$REPO_ROOT"/* ]]; then
        local filename
        filename="$(basename "$target")"
        if $DRY_RUN; then
          info "Would remove: .cursor/$spec_dir/$filename"
        else
          rm "$target"
        fi
        removed=$((removed + 1))
      fi
    done
  done

  # Remove directory if empty
  if ! $DRY_RUN && [[ -d "$target_dir" ]]; then
    rmdir "$target_dir" 2>/dev/null && info "Removed empty directory: .cursor/$spec_dir/" || true
  fi

  if ! $DRY_RUN; then
    if (( removed > 0 )); then
      ok "Removed $removed file(s)"
    else
      info "Nothing to remove"
    fi
  fi
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
      *)              err "Unknown option: $1"; SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"; usage; exit 1 ;;
    esac
  done

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

  if $show_help; then
    usage
    exit 0
  fi

  resolve_paths

  echo ""
  bold "AAN Installer v${VERSION}"
  echo ""
  info "AAN repo:     $REPO_ROOT"
  info "Project root: $PROJECT_ROOT"
  $DRY_RUN   && info "Mode: dry-run (no changes will be made)" || true
  $USE_COPY  && info "Mode: copy (files will be copied, not symlinked)" || true
  $UNINSTALL && info "Mode: uninstall" || true
  echo ""

  # Discover spec directories
  local spec_dirs
  read -ra spec_dirs <<< "$(discover_spec_dirs)"

  if [[ ${#spec_dirs[@]} -eq 0 ]]; then
    warn "No spec directories found in $REPO_ROOT"
    exit 0
  fi

  if $UNINSTALL; then
    bold "Removing installed specs…"
    echo ""
    for dir in "${spec_dirs[@]}"; do
      if is_nested_spec_dir "$REPO_ROOT/$dir"; then
        uninstall_nested_spec_dir "$dir"
      else
        uninstall_spec_dir "$dir"
      fi
    done
  else
    bold "Installing specs into .cursor/…"
    echo ""
    for dir in "${spec_dirs[@]}"; do
      if is_nested_spec_dir "$REPO_ROOT/$dir"; then
        install_nested_spec_dir "$dir"
      else
        install_spec_dir "$dir"
      fi
    done
  fi

  echo ""
  if $DRY_RUN; then
    info "Dry-run complete. No changes were made."
  elif $UNINSTALL; then
    ok "Uninstall complete."
  else
    ok "Install complete."
    echo ""
    info "To update after pulling submodule changes, re-run:"
    info "  bash $(relpath "$REPO_ROOT" "$PROJECT_ROOT")/cursor/install.sh"
  fi
  echo ""
}

main "$@"
