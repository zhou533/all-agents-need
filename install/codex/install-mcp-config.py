#!/usr/bin/env python3

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import re
import sys
from pathlib import Path
from typing import Any


EXIT_OK = 0
EXIT_FAILURE = 1
EXIT_USAGE = 2
EXIT_INCOMPLETE = 3
EXIT_CONFLICT = 4

BLOCK_START = "# >>> AAN MCP MANAGED BLOCK START >>>"
BLOCK_END = "# <<< AAN MCP MANAGED BLOCK END <<<"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="install-mcp-config.py",
        add_help=False,
        formatter_class=argparse.RawTextHelpFormatter,
        description=(
            "AAN Codex MCP configuration installer\n\n"
            "Convert selected MCP servers from mcp-servers.json into project-local\n"
            ".codex/config.toml entries under a managed AAN block."
        ),
    )
    parser.add_argument("--project-root", default=".", help="Target Codex project root. Default: current directory.")
    parser.add_argument("--aan-root", default=None, help="AAN root directory. Default: inferred from this script path.")
    parser.add_argument(
        "--source",
        default=None,
        help="Source mcp-servers.json path. Default: <aan-root>/mcp/mcp-servers.json",
    )
    parser.add_argument(
        "--config",
        default=None,
        help="Target Codex config.toml path. Default: <project-root>/.codex/config.toml",
    )
    parser.add_argument(
        "--state-file",
        default=None,
        help="Install state file. Default: <project-root>/.codex/aan-install-state.json",
    )
    parser.add_argument(
        "--servers",
        default="",
        help="Comma-separated MCP server names to install. Example: github,context7,playwright",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Replace conflicting unmanaged MCP sections for the selected server names.",
    )
    parser.add_argument("--json", action="store_true", help="Emit JSON summary instead of text.")
    parser.add_argument("--help", action="store_true", help="Show this help message.")
    return parser


def usage() -> str:
    return """AAN Codex MCP configuration installer

Usage:
  install-mcp-config.py [options]

Options:
  --project-root <path>   Target Codex project root. Default: current directory.
  --aan-root <path>       AAN root directory. Default: inferred from this script path.
  --source <path>         Source mcp-servers.json. Default: <aan-root>/mcp/mcp-servers.json
  --config <path>         Target Codex config.toml. Default: <project-root>/.codex/config.toml
  --state-file <path>     Install state file. Default: <project-root>/.codex/aan-install-state.json
  --servers <csv>         Comma-separated MCP server names to install.
  --force                 Replace conflicting unmanaged MCP sections for selected names.
  --json                  Emit JSON summary instead of text.
  --help                  Show this help message.

Exit codes:
  0  MCP configuration was updated successfully.
  1  MCP conversion or file update failed.
  2  Invalid arguments or runtime usage error.
  3  Required inputs are missing; conversion is incomplete.
  4  Conflicting unmanaged MCP sections were detected.

Examples:
  install-mcp-config.py --servers github,context7
  install-mcp-config.py --project-root /path/to/project --servers playwright --json
  install-mcp-config.py --servers github,context7 --force

Notes:
  This script manages only AAN-owned MCP server entries.
  It does not remove unrelated user-defined MCP configuration.
"""


def parse_args() -> argparse.Namespace:
    parser = build_parser()
    args, unknown = parser.parse_known_args()
    if args.help:
        print(usage())
        raise SystemExit(EXIT_OK)
    if unknown:
        print(f"Unknown arguments: {' '.join(unknown)}", file=sys.stderr)
        print(usage(), file=sys.stderr)
        raise SystemExit(EXIT_USAGE)
    return args


def normalize_servers(raw: str) -> list[str]:
    names = [item.strip() for item in raw.split(",") if item.strip()]
    return list(dict.fromkeys(names))


def toml_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def toml_array(values: list[Any]) -> str:
    rendered = []
    for item in values:
        if isinstance(item, str):
            rendered.append(toml_string(item))
        elif isinstance(item, bool):
            rendered.append("true" if item else "false")
        elif isinstance(item, (int, float)):
            rendered.append(str(item))
        else:
            raise ValueError(f"Unsupported array item type: {type(item)!r}")
    return "[" + ", ".join(rendered) + "]"


def section_name(name: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_-]+", name):
        return name
    return toml_string(name)


def assignment_key(name: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_-]+", name):
        return name
    return toml_string(name)


def render_server(name: str, data: dict[str, Any]) -> str:
    lines: list[str] = []
    section = section_name(name)
    lines.append(f"[mcp_servers.{section}]")

    if "command" in data:
        lines.append(f"command = {toml_string(str(data['command']))}")
    if "args" in data:
        lines.append(f"args = {toml_array(list(data['args']))}")
    if "url" in data:
        lines.append(f"url = {toml_string(str(data['url']))}")
    if "startup_timeout_sec" in data:
        lines.append(f"startup_timeout_sec = {int(data['startup_timeout_sec'])}")

    env = data.get("env")
    if isinstance(env, dict) and env:
        lines.append("")
        lines.append(f"[mcp_servers.{section}.env]")
        for key, value in env.items():
            lines.append(f"{assignment_key(str(key))} = {toml_string(str(value))}")

    headers = data.get("headers")
    if isinstance(headers, dict) and headers:
        lines.append("")
        lines.append(f"[mcp_servers.{section}.http_headers]")
        for key, value in headers.items():
            lines.append(f"{assignment_key(str(key))} = {toml_string(str(value))}")

    return "\n".join(lines).rstrip() + "\n"


def render_managed_block(selected: dict[str, dict[str, Any]]) -> str:
    rendered = [BLOCK_START, "# Managed by all-agents-need/install/codex/install-mcp-config.py"]
    if selected:
        rendered.append("")
        names = sorted(selected.keys())
        for index, name in enumerate(names):
            rendered.append(render_server(name, selected[name]).rstrip())
            if index != len(names) - 1:
                rendered.append("")
    rendered.append(BLOCK_END)
    return "\n".join(rendered).rstrip() + "\n"


def strip_managed_block(text: str) -> str:
    pattern = re.compile(
        rf"(?ms)^[ \t]*{re.escape(BLOCK_START)}\n.*?^[ \t]*{re.escape(BLOCK_END)}\n?"
    )
    return re.sub(pattern, "", text)


def split_with_newlines(text: str) -> list[str]:
    return text.splitlines(keepends=True)


def parse_section_header(line: str) -> str | None:
    match = re.match(r"^\s*\[([^\]]+)\]\s*$", line)
    if not match:
        return None
    return match.group(1).strip()


def is_target_mcp_section(header: str, target_names: set[str]) -> bool:
    parts = [part.strip().strip('"').strip("'") for part in header.split(".")]
    if len(parts) < 2 or parts[0] != "mcp_servers":
        return False
    return parts[1] in target_names


def find_conflicting_sections(text: str, target_names: set[str]) -> list[str]:
    conflicts: list[str] = []
    seen: set[str] = set()
    for line in text.splitlines():
        header = parse_section_header(line)
        if not header:
            continue
        parts = [part.strip().strip('"').strip("'") for part in header.split(".")]
        if len(parts) < 2 or parts[0] != "mcp_servers":
            continue
        name = parts[1]
        if name in target_names and name not in seen:
            conflicts.append(name)
            seen.add(name)
    return conflicts


def remove_conflicting_sections(text: str, target_names: set[str]) -> str:
    lines = split_with_newlines(text)
    result: list[str] = []
    current_block: list[str] = []
    current_header: str | None = None

    def flush_block() -> None:
        nonlocal current_block, current_header
        if current_block:
            if current_header and is_target_mcp_section(current_header, target_names):
                current_block = []
                current_header = None
                return
            result.extend(current_block)
        current_block = []
        current_header = None

    for line in lines:
        header = parse_section_header(line)
        if header is not None:
            flush_block()
            current_header = header
            current_block = [line]
        else:
            current_block.append(line)

    flush_block()
    return "".join(result)


def ensure_trailing_newline(text: str) -> str:
    if not text:
        return ""
    if not text.endswith("\n"):
        return text + "\n"
    return text


def merge_managed_block(existing_text: str, managed_block: str) -> str:
    base = strip_managed_block(existing_text).rstrip()
    if not base:
        return managed_block
    return base + "\n\n" + managed_block


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def relative_aan_path(project_root: Path, aan_root: Path) -> str:
    try:
        return str(aan_root.resolve().relative_to(project_root.resolve()))
    except Exception:
        return str(aan_root.resolve())


def ensure_state_defaults(data: dict[str, Any], project_root: Path, aan_root: Path) -> dict[str, Any]:
    defaults = {
        "installed_at": datetime.now(timezone.utc).isoformat(),
        "aan_root": str(aan_root.resolve()),
        "aan_project_relative_path": relative_aan_path(project_root, aan_root),
        "selected_modules": [],
        "skills": [],
        "agents": [],
        "mcp_servers": [],
        "ignored_categories": ["commands", "rules", "hooks"],
        "boundary_profile": "",
    }
    merged = dict(defaults)
    merged.update(data)
    return merged


def collect_placeholders(value: Any) -> list[str]:
    placeholders: list[str] = []

    if isinstance(value, str):
        if re.search(r"\bYOUR_[A-Z0-9_]*(?:_HERE)?\b", value):
            placeholders.append(value)
        elif re.search(r"/path/to/your(?:/|\b)", value, flags=re.IGNORECASE):
            placeholders.append(value)
    elif isinstance(value, dict):
        for nested in value.values():
            placeholders.extend(collect_placeholders(nested))
    elif isinstance(value, list):
        for nested in value:
            placeholders.extend(collect_placeholders(nested))

    return placeholders


def update_state_file(path: Path, project_root: Path, aan_root: Path, selected_names: list[str]) -> None:
    if path.exists():
        data = load_json(path)
        if not isinstance(data, dict):
            raise ValueError(f"State file is not a JSON object: {path}")
    else:
        data = {}

    data = ensure_state_defaults(data, project_root, aan_root)
    data["aan_root"] = str(aan_root.resolve())
    data["aan_project_relative_path"] = relative_aan_path(project_root, aan_root)
    data["mcp_servers"] = [{"name": name} for name in selected_names]

    ensure_parent(path)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def print_text_summary(
    config_path: Path,
    selected_names: list[str],
    created: bool,
    placeholders: list[str],
    forced: list[str],
) -> None:
    print("AAN Codex MCP Install")
    print(f"Config: {config_path}")
    print(f"Servers: {', '.join(selected_names) if selected_names else '(none)'}")
    print(f"Managed block: {'created' if created else 'updated'}")
    if forced:
        print(f"Replaced unmanaged sections: {', '.join(forced)}")
    if placeholders:
        print(f"Placeholders: {', '.join(placeholders)}")


def print_json_summary(
    config_path: Path,
    selected_names: list[str],
    created: bool,
    placeholders: list[str],
    forced: list[str],
) -> None:
    payload = {
        "status": "ok",
        "config": str(config_path),
        "servers": selected_names,
        "managed_block": "created" if created else "updated",
        "replaced_unmanaged_sections": forced,
        "placeholders": placeholders,
    }
    print(json.dumps(payload, ensure_ascii=False))


def main() -> int:
    args = parse_args()

    script_dir = Path(__file__).resolve().parent
    aan_root = Path(args.aan_root).resolve() if args.aan_root else script_dir.parent.parent.resolve()
    project_root = Path(args.project_root).resolve()
    source_path = Path(args.source).resolve() if args.source else aan_root / "mcp" / "mcp-servers.json"
    config_path = Path(args.config).resolve() if args.config else project_root / ".codex" / "config.toml"
    state_file = Path(args.state_file).resolve() if args.state_file else project_root / ".codex" / "aan-install-state.json"
    selected_names = normalize_servers(args.servers)

    if not selected_names:
        print("No MCP servers were specified. Use --servers <csv>.", file=sys.stderr)
        print(usage(), file=sys.stderr)
        return EXIT_USAGE

    if not project_root.is_dir():
        print(f"Project root does not exist: {project_root}", file=sys.stderr)
        return EXIT_INCOMPLETE

    if not aan_root.is_dir():
        print(f"AAN root does not exist: {aan_root}", file=sys.stderr)
        return EXIT_INCOMPLETE

    if not source_path.is_file():
        print(f"Source mcp-servers.json does not exist: {source_path}", file=sys.stderr)
        return EXIT_INCOMPLETE

    try:
        source_data = load_json(source_path)
    except Exception as exc:
        print(f"Failed to read source JSON: {exc}", file=sys.stderr)
        return EXIT_FAILURE

    servers = source_data.get("mcpServers")
    if not isinstance(servers, dict):
        print(f"Source file does not contain an mcpServers object: {source_path}", file=sys.stderr)
        return EXIT_FAILURE

    missing = [name for name in selected_names if name not in servers]
    if missing:
        print(f"Selected MCP servers were not found in source JSON: {', '.join(missing)}", file=sys.stderr)
        return EXIT_FAILURE

    selected = {name: servers[name] for name in selected_names}
    placeholders = sorted({placeholder for data in selected.values() for placeholder in collect_placeholders(data)})

    ensure_parent(config_path)
    existing_text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
    existing_text = ensure_trailing_newline(existing_text)
    stripped_text = strip_managed_block(existing_text)

    conflicts = find_conflicting_sections(stripped_text, set(selected_names))
    replaced_conflicts: list[str] = []

    if conflicts and not args.force:
        message = {
            "status": "conflict",
            "conflicts": conflicts,
            "config": str(config_path),
        }
        if args.json:
            print(json.dumps(message, ensure_ascii=False))
        else:
            print("Conflicting unmanaged MCP sections detected:", file=sys.stderr)
            for name in conflicts:
                print(f"- {name}", file=sys.stderr)
            print("Re-run with --force only after the user confirms replacement.", file=sys.stderr)
        return EXIT_CONFLICT

    if conflicts and args.force:
        stripped_text = remove_conflicting_sections(stripped_text, set(selected_names))
        replaced_conflicts = conflicts[:]

    managed_block = render_managed_block(selected)
    merged_text = merge_managed_block(stripped_text, managed_block)

    try:
        config_path.write_text(ensure_trailing_newline(merged_text), encoding="utf-8")
        update_state_file(state_file, project_root, aan_root, selected_names)
    except Exception as exc:
        print(f"Failed to update MCP configuration: {exc}", file=sys.stderr)
        return EXIT_FAILURE

    created = BLOCK_START not in existing_text

    if args.json:
        print_json_summary(config_path, selected_names, created, placeholders, replaced_conflicts)
    else:
        print_text_summary(config_path, selected_names, created, placeholders, replaced_conflicts)

    return EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
