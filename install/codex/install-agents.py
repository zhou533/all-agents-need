#!/usr/bin/env python3

from __future__ import annotations

import argparse
import ast
from datetime import datetime, timezone
import json
import re
import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any


EXIT_OK = 0
EXIT_FAILURE = 1
EXIT_USAGE = 2
EXIT_INCOMPLETE = 3
EXIT_CONFLICT = 4

BLOCK_START = "# >>> AAN AGENTS MANAGED BLOCK START >>>"
BLOCK_END = "# <<< AAN AGENTS MANAGED BLOCK END <<<"
FILE_HEADER = "# Managed by all-agents-need/install/codex/install-agents.py"


@dataclass
class AgentSpec:
    source_path: Path
    file_name: str
    frontmatter_name: str | None
    agent_id: str
    description: str
    tools: list[str]
    model: str | None
    body: str


def usage() -> str:
    return """AAN Codex agent installer

Usage:
  install-agents.py [options]

Options:
  --project-root <path>   Target Codex project root. Default: current directory.
  --aan-root <path>       AAN root directory. Default: inferred from this script path.
  --source-dir <path>     Source agents directory. Default: <aan-root>/agents
  --config <path>         Target Codex config.toml. Default: <project-root>/.codex/config.toml
  --agents-dir <path>     Target Codex agents directory. Default: <project-root>/.codex/agents
  --state-file <path>     Install state file. Default: <project-root>/.codex/aan-install-state.json
  --agents <csv>          Comma-separated agents to install. Accepts source filenames, frontmatter names, or agent ids.
  --force                 Replace conflicting unmanaged agent files and config sections.
  --json                  Emit JSON summary instead of text.
  --help                  Show this help message.

Exit codes:
  0  Agent conversion and registration succeeded.
  1  Agent conversion or file update failed.
  2  Invalid arguments or runtime usage error.
  3  Required inputs are missing; conversion is incomplete.
  4  Conflicting unmanaged agent files or config sections were detected.

Examples:
  install-agents.py --agents planner.md,code-explorer.md
  install-agents.py --project-root /path/to/project --agents security-reviewer --json
  install-agents.py --agents planner,code-explorer --force

Notes:
  This script generates project-local Codex agents under .codex/agents/.
  It manages only AAN-owned agent files and [agents.<id>] config entries.
"""


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="install-agents.py",
        add_help=False,
        formatter_class=argparse.RawTextHelpFormatter,
        description=(
            "AAN Codex agent installer\n\n"
            "Convert selected AAN markdown agents into project-local Codex TOML agents\n"
            "and register them under a managed config.toml block."
        ),
    )
    parser.add_argument("--project-root", default=".", help="Target Codex project root. Default: current directory.")
    parser.add_argument("--aan-root", default=None, help="AAN root directory. Default: inferred from this script path.")
    parser.add_argument("--source-dir", default=None, help="Source agents directory. Default: <aan-root>/agents")
    parser.add_argument(
        "--config",
        default=None,
        help="Target Codex config.toml path. Default: <project-root>/.codex/config.toml",
    )
    parser.add_argument(
        "--agents-dir",
        default=None,
        help="Target Codex agents directory. Default: <project-root>/.codex/agents",
    )
    parser.add_argument(
        "--state-file",
        default=None,
        help="Install state file. Default: <project-root>/.codex/aan-install-state.json",
    )
    parser.add_argument(
        "--agents",
        default="",
        help="Comma-separated agents to install. Accepts source filenames, frontmatter names, or agent ids.",
    )
    parser.add_argument("--force", action="store_true", help="Replace conflicting unmanaged agent files and config sections.")
    parser.add_argument("--json", action="store_true", help="Emit JSON summary instead of text.")
    parser.add_argument("--help", action="store_true", help="Show this help message.")
    return parser


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


def normalize_csv(raw: str) -> list[str]:
    values = [item.strip() for item in raw.split(",") if item.strip()]
    return list(dict.fromkeys(values))


def slugify_agent_id(value: str) -> str:
    cleaned = value.strip().lower()
    cleaned = re.sub(r"\.md$", "", cleaned)
    cleaned = re.sub(r"[^a-z0-9]+", "_", cleaned)
    cleaned = re.sub(r"_+", "_", cleaned).strip("_")
    return cleaned or "agent"


def toml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def toml_multiline(value: str) -> str:
    return toml_string(value.rstrip() + "\n")


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def load_state(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    data = load_json(path)
    if not isinstance(data, dict):
        raise ValueError(f"State file is not a JSON object: {path}")
    return data


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


def parse_frontmatter_list(value: str) -> list[str]:
    text = value.strip()
    if not text:
        return []
    if text.startswith("[") and text.endswith("]"):
        inner = text[1:-1].strip()
        if not inner:
            return []
        try:
            parsed = ast.literal_eval(text)
            if isinstance(parsed, list):
                return [str(item) for item in parsed]
        except Exception:
            pass
        return [item.strip().strip('"').strip("'") for item in inner.split(",") if item.strip()]
    return [item.strip().strip('"').strip("'") for item in text.split(",") if item.strip()]


def parse_frontmatter(text: str) -> tuple[dict[str, Any], str]:
    if not text.startswith("---\n"):
        return {}, text

    end_marker = "\n---\n"
    end_index = text.find(end_marker, 4)
    if end_index == -1:
        return {}, text

    raw = text[4:end_index]
    body = text[end_index + len(end_marker):]
    data: dict[str, Any] = {}

    for line in raw.splitlines():
        if not line.strip() or ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if key == "tools":
            data[key] = parse_frontmatter_list(value)
        else:
            data[key] = value.strip().strip('"').strip("'")

    return data, body


def infer_description(body: str, fallback: str) -> str:
    for line in body.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("#"):
            continue
        return stripped[:240]
    return fallback


def is_supported_codex_model(model: str | None) -> bool:
    if not model:
        return False
    lowered = model.strip().lower()
    return lowered.startswith(("gpt-", "codex", "o1", "o3", "o4"))


def derive_sandbox_mode(tools: list[str]) -> str | None:
    if not tools:
        return None
    normalized = {tool.strip().lower() for tool in tools}
    read_only = {"read", "grep", "glob"}
    if normalized and normalized.issubset(read_only):
        return "read-only"
    return None


def parse_agent_file(path: Path) -> AgentSpec:
    text = path.read_text(encoding="utf-8")
    meta, body = parse_frontmatter(text)
    frontmatter_name = meta.get("name")
    canonical_source = frontmatter_name or path.stem
    agent_id = slugify_agent_id(canonical_source)
    description = str(meta.get("description") or infer_description(body, path.stem))
    tools = [str(item) for item in meta.get("tools", [])]
    model = str(meta["model"]) if "model" in meta else None

    return AgentSpec(
        source_path=path,
        file_name=path.name,
        frontmatter_name=str(frontmatter_name) if frontmatter_name else None,
        agent_id=agent_id,
        description=description,
        tools=tools,
        model=model,
        body=body.strip() + "\n",
    )


def load_source_agents(source_dir: Path) -> list[AgentSpec]:
    return [parse_agent_file(path) for path in sorted(source_dir.glob("*.md"))]


def resolve_selected_agents(all_agents: list[AgentSpec], selectors: list[str]) -> list[AgentSpec]:
    if not selectors:
        raise ValueError("No agents were specified. Use --agents <csv>.")

    by_file = {agent.file_name: agent for agent in all_agents}
    by_name = {agent.frontmatter_name: agent for agent in all_agents if agent.frontmatter_name}
    by_id = {agent.agent_id: agent for agent in all_agents}

    selected: list[AgentSpec] = []
    seen: set[str] = set()
    missing: list[str] = []

    for raw in selectors:
        agent = by_file.get(raw) or by_name.get(raw) or by_id.get(slugify_agent_id(raw))
        if not agent:
            missing.append(raw)
            continue
        if agent.agent_id not in seen:
            selected.append(agent)
            seen.add(agent.agent_id)

    if missing:
        raise ValueError("Selected agents were not found: " + ", ".join(missing))

    return selected


def render_agent_file(agent: AgentSpec) -> str:
    lines = [FILE_HEADER, f"description = {toml_string(agent.description)}"]

    sandbox_mode = derive_sandbox_mode(agent.tools)
    if sandbox_mode:
        lines.append(f'sandbox_mode = "{sandbox_mode}"')

    if is_supported_codex_model(agent.model):
        lines.append(f"model = {toml_string(str(agent.model))}")

    lines.append(f"developer_instructions = {toml_multiline(agent.body)}")
    return "\n".join(lines).rstrip() + "\n"


def render_registration_block(selected_agents: list[AgentSpec]) -> str:
    rendered = [BLOCK_START, "# Managed by all-agents-need/install/codex/install-agents.py"]
    if selected_agents:
        rendered.append("")
        ordered = sorted(selected_agents, key=lambda item: item.agent_id)
        for index, agent in enumerate(ordered):
            rendered.append(f"[agents.{agent.agent_id}]")
            rendered.append(f"description = {toml_string(agent.description)}")
            rendered.append(f'config_file = "agents/{agent.agent_id}.toml"')
            if index != len(ordered) - 1:
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


def is_target_agent_section(header: str, target_ids: set[str]) -> bool:
    parts = [part.strip().strip('"').strip("'") for part in header.split(".")]
    if len(parts) < 2 or parts[0] != "agents":
        return False
    if len(parts) == 2:
        return parts[1] in target_ids
    return parts[1] in target_ids


def find_conflicting_agent_sections(text: str, target_ids: set[str]) -> list[str]:
    conflicts: list[str] = []
    seen: set[str] = set()
    for line in text.splitlines():
        header = parse_section_header(line)
        if not header:
            continue
        parts = [part.strip().strip('"').strip("'") for part in header.split(".")]
        if len(parts) < 2 or parts[0] != "agents":
            continue
        if parts[1] in target_ids and parts[1] not in seen:
            conflicts.append(parts[1])
            seen.add(parts[1])
    return conflicts


def remove_conflicting_sections(text: str, target_ids: set[str]) -> str:
    lines = split_with_newlines(text)
    result: list[str] = []
    current_block: list[str] = []
    current_header: str | None = None

    def flush_block() -> None:
        nonlocal current_block, current_header
        if current_block:
            if current_header and is_target_agent_section(current_header, target_ids):
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
    if text and not text.endswith("\n"):
        return text + "\n"
    return text


def merge_registration_block(existing_text: str, managed_block: str) -> str:
    base = strip_managed_block(existing_text).rstrip()
    if not base:
        return managed_block
    return base + "\n\n" + managed_block


def managed_agent_ids_from_state(state: dict[str, Any]) -> set[str]:
    agents = state.get("agents", [])
    result: set[str] = set()
    if isinstance(agents, list):
      for item in agents:
          if isinstance(item, dict) and "id" in item:
              result.add(str(item["id"]))
          elif isinstance(item, str):
              result.add(str(item))
    return result


def detect_file_conflicts(selected_agents: list[AgentSpec], agents_dir: Path, managed_ids: set[str]) -> list[str]:
    conflicts: list[str] = []
    for agent in selected_agents:
        path = agents_dir / f"{agent.agent_id}.toml"
        if not path.exists():
            continue
        content = path.read_text(encoding="utf-8")
        if agent.agent_id in managed_ids or FILE_HEADER in content:
            continue
        conflicts.append(agent.agent_id)
    return conflicts


def write_agent_files(selected_agents: list[AgentSpec], agents_dir: Path) -> list[str]:
    ensure_parent(agents_dir / ".keep")
    written: list[str] = []
    for agent in selected_agents:
        target = agents_dir / f"{agent.agent_id}.toml"
        target.write_text(render_agent_file(agent), encoding="utf-8")
        written.append(agent.agent_id)
    return written


def validate_agent_files(selected_agents: list[AgentSpec], agents_dir: Path) -> None:
    for agent in selected_agents:
        target = agents_dir / f"{agent.agent_id}.toml"
        with target.open("rb") as fh:
            data = tomllib.load(fh)
        for key in ("description", "developer_instructions"):
            value = data.get(key)
            if not isinstance(value, str) or not value.strip():
                raise ValueError(f"{target} is missing a non-empty {key}")


def update_state_file(path: Path, project_root: Path, aan_root: Path, selected_agents: list[AgentSpec]) -> None:
    data = ensure_state_defaults(load_state(path), project_root, aan_root)
    data["aan_root"] = str(aan_root.resolve())
    data["aan_project_relative_path"] = relative_aan_path(project_root, aan_root)
    data["agents"] = [
        {
            "id": agent.agent_id,
            "source_file": agent.file_name,
            "name": agent.frontmatter_name or agent.file_name,
        }
        for agent in selected_agents
    ]

    ensure_parent(path)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def print_text_summary(
    agents_dir: Path,
    config_path: Path,
    selected_agents: list[AgentSpec],
    replaced_files: list[str],
    replaced_sections: list[str],
    created_block: bool,
) -> None:
    print("AAN Codex Agent Install")
    print(f"Agents Dir: {agents_dir}")
    print(f"Config: {config_path}")
    print("Agents: " + ", ".join(agent.agent_id for agent in selected_agents))
    print(f"Managed block: {'created' if created_block else 'updated'}")
    if replaced_files:
        print("Replaced unmanaged agent files: " + ", ".join(replaced_files))
    if replaced_sections:
        print("Replaced unmanaged config sections: " + ", ".join(replaced_sections))


def print_json_summary(
    agents_dir: Path,
    config_path: Path,
    selected_agents: list[AgentSpec],
    replaced_files: list[str],
    replaced_sections: list[str],
    created_block: bool,
) -> None:
    payload = {
        "status": "ok",
        "agents_dir": str(agents_dir),
        "config": str(config_path),
        "agents": [agent.agent_id for agent in selected_agents],
        "managed_block": "created" if created_block else "updated",
        "replaced_unmanaged_files": replaced_files,
        "replaced_unmanaged_sections": replaced_sections,
    }
    print(json.dumps(payload, ensure_ascii=False))


def main() -> int:
    args = parse_args()
    script_dir = Path(__file__).resolve().parent
    aan_root = Path(args.aan_root).resolve() if args.aan_root else script_dir.parent.parent.resolve()
    project_root = Path(args.project_root).resolve()
    source_dir = Path(args.source_dir).resolve() if args.source_dir else aan_root / "agents"
    config_path = Path(args.config).resolve() if args.config else project_root / ".codex" / "config.toml"
    agents_dir = Path(args.agents_dir).resolve() if args.agents_dir else project_root / ".codex" / "agents"
    state_file = Path(args.state_file).resolve() if args.state_file else project_root / ".codex" / "aan-install-state.json"
    selectors = normalize_csv(args.agents)

    if not project_root.is_dir():
        print(f"Project root does not exist: {project_root}", file=sys.stderr)
        return EXIT_INCOMPLETE
    if not aan_root.is_dir():
        print(f"AAN root does not exist: {aan_root}", file=sys.stderr)
        return EXIT_INCOMPLETE
    if not source_dir.is_dir():
        print(f"Source agents directory does not exist: {source_dir}", file=sys.stderr)
        return EXIT_INCOMPLETE

    try:
        all_agents = load_source_agents(source_dir)
        selected_agents = resolve_selected_agents(all_agents, selectors)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        print(usage(), file=sys.stderr)
        return EXIT_USAGE
    except Exception as exc:
        print(f"Failed to load source agents: {exc}", file=sys.stderr)
        return EXIT_FAILURE

    try:
        state = load_state(state_file)
    except Exception as exc:
        print(f"Failed to read state file: {exc}", file=sys.stderr)
        return EXIT_FAILURE

    ensure_parent(config_path)
    agents_dir.mkdir(parents=True, exist_ok=True)

    existing_text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
    stripped_text = strip_managed_block(ensure_trailing_newline(existing_text))
    managed_ids = managed_agent_ids_from_state(state)
    target_ids = {agent.agent_id for agent in selected_agents}

    file_conflicts = detect_file_conflicts(selected_agents, agents_dir, managed_ids)
    section_conflicts = find_conflicting_agent_sections(stripped_text, target_ids)

    if (file_conflicts or section_conflicts) and not args.force:
        payload = {
            "status": "conflict",
            "conflicting_files": file_conflicts,
            "conflicting_sections": section_conflicts,
            "agents_dir": str(agents_dir),
            "config": str(config_path),
        }
        if args.json:
            print(json.dumps(payload, ensure_ascii=False))
        else:
            if file_conflicts:
                print("Conflicting unmanaged agent files detected:", file=sys.stderr)
                for agent_id in file_conflicts:
                    print(f"- {agents_dir / (agent_id + '.toml')}", file=sys.stderr)
            if section_conflicts:
                print("Conflicting unmanaged [agents.<id>] config sections detected:", file=sys.stderr)
                for agent_id in section_conflicts:
                    print(f"- [agents.{agent_id}]", file=sys.stderr)
            print("Re-run with --force only after the user confirms replacement.", file=sys.stderr)
        return EXIT_CONFLICT

    replaced_files: list[str] = []
    replaced_sections: list[str] = []

    if args.force:
        replaced_files = file_conflicts[:]
        replaced_sections = section_conflicts[:]
        stripped_text = remove_conflicting_sections(stripped_text, target_ids)

    try:
        write_agent_files(selected_agents, agents_dir)
        validate_agent_files(selected_agents, agents_dir)
        managed_block = render_registration_block(selected_agents)
        merged_text = merge_registration_block(stripped_text, managed_block)
        config_path.write_text(ensure_trailing_newline(merged_text), encoding="utf-8")
        update_state_file(state_file, project_root, aan_root, selected_agents)
    except Exception as exc:
        print(f"Failed to install agents: {exc}", file=sys.stderr)
        return EXIT_FAILURE

    created_block = BLOCK_START not in existing_text

    if args.json:
        print_json_summary(agents_dir, config_path, selected_agents, replaced_files, replaced_sections, created_block)
    else:
        print_text_summary(agents_dir, config_path, selected_agents, replaced_files, replaced_sections, created_block)

    return EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
