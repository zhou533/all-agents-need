#!/usr/bin/env bash
#
# AAN (all-agents-need) 安装器
# 把 AAN 的模块化资源按选择安装到项目级 .claude/ 目录
#
# 用法：
#   1. git submodule add <AAN 仓库> 到项目根
#   2. 在项目根运行：bash <submodule-path>/install/claude/install.sh
#
# 依赖：bash ≥4、jq、gum
#
set -euo pipefail

# ===== 常量 =====
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly AAN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly SCHEMA_VERSION_SUPPORTED="1"

# ===== 资源注册表 =====
# 格式: type_id|aan_source|target_kind|target_path|handler
readonly RESOURCE_REGISTRY=(
  "skills|skills|dir|.claude/skills|handle_copy_tree"
  "agents|agents|file|.claude/agents|handle_copy_file"
  "commands|commands|file|.claude/commands|handle_copy_file"
  "rules|rules|file|.claude/rules|handle_copy_file_preserve_path"
  "output-styles|output-styles|file|.claude/output-styles|handle_copy_file"
  "hooks|hooks/hooks.json|json_field|.claude/settings.json|handle_hooks_merge"
  "mcps|mcp/mcp-servers.json|json_field|.mcp.json|handle_mcp_merge"
)

registry_types() {
  local entry
  for entry in "${RESOURCE_REGISTRY[@]}"; do
    echo "${entry%%|*}"
  done
}

registry_get() {
  local type_id="$1" field="$2"
  local entry id src kind path handler
  for entry in "${RESOURCE_REGISTRY[@]}"; do
    IFS='|' read -r id src kind path handler <<< "$entry"
    if [[ "$id" == "$type_id" ]]; then
      case "$field" in
        source)  echo "$src" ;;
        kind)    echo "$kind" ;;
        target)  echo "$path" ;;
        handler) echo "$handler" ;;
        *) return 1 ;;
      esac
      return 0
    fi
  done
  return 1
}

# ===== 日志函数 =====
log_info()    { printf '\033[36m[AAN]\033[0m %s\n' "$*" >&2; }
log_warn()    { printf '\033[33m[AAN WARN]\033[0m %s\n' "$*" >&2; }
log_error()   { printf '\033[31m[AAN ERROR]\033[0m %s\n' "$*" >&2; }
log_success() { printf '\033[32m[AAN OK]\033[0m %s\n' "$*" >&2; }

die() {
  log_error "$@"
  exit 1
}

# ===== Stage 0: preflight =====
preflight() {
  local missing=()

  command -v jq  >/dev/null 2>&1 || missing+=("jq")
  command -v gum >/dev/null 2>&1 || missing+=("gum")

  if ((${#missing[@]} > 0)); then
    log_error "缺少必需工具：${missing[*]}"
    cat >&2 <<'HINT'

安装提示：
  macOS:   brew install jq gum
  Linux:   jq  → https://jqlang.github.io/jq/download/
           gum → https://github.com/charmbracelet/gum#installation

安装后请重新运行本脚本。
HINT
    exit 1
  fi

  log_success "前置工具就绪：jq / gum"
}

# ===== Stage 1: detect_context =====
detect_context() {
  # 项目根：优先 git superproject（submodule 场景），回退 pwd
  local project_root=""
  if command -v git >/dev/null 2>&1; then
    project_root="$(git rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  fi
  [[ -z "${project_root}" ]] && project_root="$(pwd)"

  readonly PROJECT_ROOT="${project_root}"
  readonly CLAUDE_DIR="${PROJECT_ROOT}/.claude"
  readonly MCP_FILE="${PROJECT_ROOT}/.mcp.json"

  # AAN 源数据文件
  readonly MANIFESTS_JSON="${AAN_ROOT}/install/manifests.json"
  readonly HOOKS_JSON="${AAN_ROOT}/hooks/hooks.json"
  readonly MCP_SERVERS_JSON="${AAN_ROOT}/mcp/mcp-servers.json"

  # 校验源文件存在
  [[ -f "${MANIFESTS_JSON}" ]]   || die "未找到 manifests.json: ${MANIFESTS_JSON}"
  [[ -f "${HOOKS_JSON}" ]]       || die "未找到 hooks.json: ${HOOKS_JSON}"
  [[ -f "${MCP_SERVERS_JSON}" ]] || die "未找到 mcp-servers.json: ${MCP_SERVERS_JSON}"

  log_info "AAN 源路径:  ${AAN_ROOT}"
  log_info "项目根路径:  ${PROJECT_ROOT}"
  log_info "安装目标:    ${CLAUDE_DIR}"
}

# ===== Stage 2: load_manifests =====
load_manifests() {
  local schema
  schema="$(jq -r '."$schema_version" // "missing"' "${MANIFESTS_JSON}")"

  if [[ "${schema}" != "${SCHEMA_VERSION_SUPPORTED}" ]]; then
    die "manifests.json schema 版本 \"${schema}\" 不受支持（当前仅支持 \"${SCHEMA_VERSION_SUPPORTED}\"）"
  fi

  local module_count
  module_count="$(jq -r '.modules | length' "${MANIFESTS_JSON}")"

  log_info "manifests schema: v${schema}"
  log_info "识别到 ${module_count} 个模块"
}

# ===== Stage 3: init_registry =====
init_registry() {
  log_info "资源注册表（${#RESOURCE_REGISTRY[@]} 项）："
  local type_id
  while IFS= read -r type_id; do
    log_info "  - ${type_id} → $(registry_get "${type_id}" target)"
  done < <(registry_types)
}

# ===== Stage 4: select_modules =====
# 输出：把最终选中的模块 ID（含 required + 用户选择）放入全局 SELECTED_MODULES 数组
select_modules() {
  # required 模块（自动加入，不在 UI 展示）
  local required_list
  required_list="$(jq -r '.modules | to_entries[] | select(.value.required == true) | .key' "${MANIFESTS_JSON}")"

  # 打印可选模块（带描述）
  log_info "可选模块："
  jq -r '.modules | to_entries[]
    | select(.value.required != true)
    | "  • \(.key): \(.value.description)"' "${MANIFESTS_JSON}" >&2
  echo >&2

  log_info "请选择要安装的模块（空格勾选，回车确认；required 模块已自动包含）"
  local optional_names
  optional_names="$(jq -r '.modules | to_entries[]
    | select(.value.required != true)
    | .key' "${MANIFESTS_JSON}")"

  local chosen=""
  if [[ -n "${optional_names}" ]]; then
    chosen="$(echo "${optional_names}" | gum choose --no-limit || true)"
  fi

  # 合并 required + chosen，去重（保持 required 在前）
  local merged
  merged="$(printf '%s\n%s\n' "${required_list}" "${chosen}" | awk 'NF && !seen[$0]++')"

  SELECTED_MODULES=()
  while IFS= read -r m; do
    m="${m%$'\r'}"     # 防御 CRLF
    [[ -n "$m" ]] && SELECTED_MODULES+=("$m")
  done <<< "${merged}"

  if ((${#SELECTED_MODULES[@]} == 0)); then
    die "未选择任何模块，退出"
  fi

  log_info "初选模块（${#SELECTED_MODULES[@]} 个）：${SELECTED_MODULES[*]}"
}

# ===== Stage 5: resolve_deps =====
# 输入：SELECTED_MODULES
# 输出：RESOLVED_MODULES（含依赖闭包、已去重）
resolve_deps() {
  local seeds_json
  seeds_json="$(printf '%s\n' "${SELECTED_MODULES[@]}" | jq -R . | jq -s .)"

  local closure
  closure="$(jq -r --argjson seeds "${seeds_json}" '
    . as $manifest |
    def deps($m): $manifest.modules[$m].depends_on // [];
    def walk($m; $seen; $stack):
      if ($stack | index($m)) then
        error("循环依赖：" + ($stack + [$m] | join(" → ")))
      elif ($seen | index($m)) then $seen
      else
        (reduce deps($m)[] as $d
          ($seen; walk($d; .; $stack + [$m]))) + [$m]
      end;
    reduce $seeds[] as $x ([]; walk($x; .; [])) | unique | .[]
  ' "${MANIFESTS_JSON}")" || die "依赖解析失败（见上方错误）"

  RESOLVED_MODULES=()
  while IFS= read -r m; do
    [[ -n "$m" ]] && RESOLVED_MODULES+=("$m")
  done <<< "${closure}"

  local added=()
  local m
  for m in "${RESOLVED_MODULES[@]}"; do
    local found=0
    local s
    for s in "${SELECTED_MODULES[@]}"; do
      [[ "$s" == "$m" ]] && { found=1; break; }
    done
    ((found == 0)) && added+=("$m")
  done

  if ((${#added[@]} > 0)); then
    log_info "依赖闭包自动加入：${added[*]}"
  fi

  log_info "最终模块集合（${#RESOLVED_MODULES[@]} 个）：${RESOLVED_MODULES[*]}"
}

# ===== Stage 6: confirm_plan =====
confirm_plan() {
  log_info "资源概览："
  local mods_json
  mods_json="$(printf '%s\n' "${RESOLVED_MODULES[@]}" | jq -R . | jq -s .)"

  local type_id
  while IFS= read -r type_id; do
    local count
    count="$(jq -r --arg t "${type_id}" --argjson mods "${mods_json}" '
      [ $mods[] as $m | .modules[$m][$t][]? ] | unique | length
    ' "${MANIFESTS_JSON}")"
    log_info "  - ${type_id}: ${count}"
  done < <(registry_types)

  log_info "目标目录: ${CLAUDE_DIR}"
  log_info "MCP 文件: ${MCP_FILE}"

  if ! gum confirm "确认安装以上资源到目标项目？"; then
    log_warn "用户取消，退出"
    exit 0
  fi
}

# ===== Handlers：文件型资源落盘 =====

# 整目录覆盖（skills）
handle_copy_tree() {
  local source_root="$1" target_root="$2" name="$3"
  local src="${source_root}/${name}"
  local dst="${target_root}/${name}"

  [[ -d "${src}" ]] || die "源目录不存在：${src}"

  mkdir -p "${target_root}"
  rm -rf "${dst}"
  cp -R "${src}" "${dst}"
}

# 单文件覆盖（agents / commands / output-styles）
handle_copy_file() {
  local source_root="$1" target_root="$2" name="$3"
  local src="${source_root}/${name}"
  local dst="${target_root}/${name}"

  [[ -f "${src}" ]] || die "源文件不存在：${src}"

  mkdir -p "${target_root}"
  cp "${src}" "${dst}"
}

# 保留相对子目录结构（rules/common/testing.md → .claude/rules/common/testing.md）
handle_copy_file_preserve_path() {
  local source_root="$1" target_root="$2" relpath="$3"
  local src="${source_root}/${relpath}"
  local dst="${target_root}/${relpath}"

  [[ -f "${src}" ]] || die "源文件不存在：${src}"

  mkdir -p "$(dirname "${dst}")"
  cp "${src}" "${dst}"
}

# ===== Stage 7a: apply_file_resources =====
apply_file_resources() {
  log_info "开始落盘文件型资源..."

  local module type_id kind source target handler items item count=0

  for module in "${RESOLVED_MODULES[@]}"; do
    while IFS= read -r type_id; do
      kind="$(registry_get "${type_id}" kind)"
      [[ "${kind}" == "json_field" ]] && continue

      source="${AAN_ROOT}/$(registry_get "${type_id}" source)"
      target="${PROJECT_ROOT}/$(registry_get "${type_id}" target)"
      handler="$(registry_get "${type_id}" handler)"

      items="$(jq -r --arg m "${module}" --arg t "${type_id}" \
        '.modules[$m][$t] // [] | .[]' "${MANIFESTS_JSON}")"

      while IFS= read -r item; do
        [[ -z "${item}" ]] && continue
        "${handler}" "${source}" "${target}" "${item}"
        count=$((count + 1))
      done <<< "${items}"
    done < <(registry_types)
  done

  log_success "已落盘 ${count} 个文件型资源条目"
}

# ===== Stage 7b: apply_hooks =====
# 合并 hooks 到 .claude/settings.json
# 规则："AAN 拥有 hooks.json 中出现的所有 id"
#   - 每次运行：先从 settings.json 剔除所有 AAN 拥有的 id，再注入本次选中的
#   - 用户自己加的 hook id 不动
apply_hooks() {
  log_info "开始合并 hooks 到 settings.json..."

  # 1. 拷贝 scripts 目录（hooks 的 node bootstrap 依赖 scripts/lib/utils.js）
  local scripts_src="${AAN_ROOT}/scripts"
  local scripts_dst="${CLAUDE_DIR}/scripts"
  if [[ -d "${scripts_src}" ]]; then
    mkdir -p "${CLAUDE_DIR}"
    rm -rf "${scripts_dst}"
    cp -R "${scripts_src}" "${scripts_dst}"
    log_info "已拷贝 scripts 目录 → .claude/scripts/"
  else
    log_warn "AAN 源无 scripts 目录，hooks bootstrap 可能无法工作"
  fi

  # 2. 收集本次选中的 hook id（所选模块 hooks 数组的并集）
  local mods_json wanted_ids_json all_aan_ids_json
  mods_json="$(printf '%s\n' "${RESOLVED_MODULES[@]}" | jq -R . | jq -s .)"

  wanted_ids_json="$(jq -c --argjson mods "${mods_json}" '
    [ $mods[] as $m | .modules[$m].hooks[]? ] | unique
  ' "${MANIFESTS_JSON}")"

  # 3. 收集 AAN 拥有的所有 hook id（在 hooks.json 中出现的）
  all_aan_ids_json="$(jq -c '
    [ .hooks | to_entries[] | .value[] | .id ] | unique
  ' "${HOOKS_JSON}")"

  local wanted_count all_count
  wanted_count="$(echo "${wanted_ids_json}" | jq -r 'length')"
  all_count="$(echo "${all_aan_ids_json}" | jq -r 'length')"
  log_info "AAN 全部 hook id: ${all_count} 个；本次选中: ${wanted_count} 个"

  # 4. 准备 settings.json（首次创建或备份现有）
  local settings="${CLAUDE_DIR}/settings.json"
  mkdir -p "${CLAUDE_DIR}"
  if [[ ! -f "${settings}" ]]; then
    echo '{}' > "${settings}"
    log_info "创建新 settings.json"
  else
    local ts backup
    ts="$(date +%Y%m%d-%H%M%S)"
    backup="${settings}.aan-backup-${ts}"
    cp "${settings}" "${backup}"
    log_info "已备份原 settings.json → ${backup##*/}"
  fi

  # 5. jq 合并
  local tmp
  tmp="$(mktemp)"
  jq --slurpfile hooks_src "${HOOKS_JSON}" \
     --argjson want "${wanted_ids_json}" \
     --argjson own  "${all_aan_ids_json}" '
    (.hooks // {}) as $cur_hooks
    | ($hooks_src[0].hooks // {}) as $src_hooks
    # a) 从当前 settings.hooks 剔除所有 AAN 拥有的 id
    | .hooks = (
        $cur_hooks
        | to_entries
        | map(.value |= map(select(.id as $i | $own | index($i) | not)))
        | from_entries
      )
    # b) 按事件注入本次选中的 hooks，并把 command 里 ${CLAUDE_PLUGIN_ROOT}
    #    替换为 ${CLAUDE_PROJECT_DIR}/.claude（项目级模式下 Claude Code 不展开
    #    ${CLAUDE_PLUGIN_ROOT}，所以由 install.sh 预先做字符串替换）
    | reduce ($src_hooks | to_entries[]) as $evt (
        .;
        .hooks[$evt.key] = (
          (.hooks[$evt.key] // [])
          + ($evt.value
             | map(select(.id as $i | $want | index($i) != null))
             | map(
                 .hooks |= map(
                   if .type == "command" then
                     .command = (.command
                       | split("${CLAUDE_PLUGIN_ROOT}")
                       | join("${CLAUDE_PROJECT_DIR}/.claude"))
                   else . end
                 )
               )
            )
        )
      )
    # c) 清理空事件
    | .hooks |= (to_entries | map(select(.value | length > 0)) | from_entries)
    # d) 清理 AAN 旧版本遗留的全局 env.CLAUDE_PLUGIN_ROOT
    #    仅当值 == AAN 之前写的字面量时才删，避免误伤用户自己写的
    | if (.env.CLAUDE_PLUGIN_ROOT // null) == "${CLAUDE_PROJECT_DIR}/.claude"
      then del(.env.CLAUDE_PLUGIN_ROOT) else . end
    | if (.env // {}) == {} then del(.env) else . end
  ' "${settings}" > "${tmp}" && mv "${tmp}" "${settings}"

  log_success "hooks 合并完成（注入 ${wanted_count} 个 hook id）"
}

# ===== Stage 7c: configure_mcp_optional =====
# 两级交互：是否装 MCP → 选哪些
# 占位符保留原样；末尾列出需手填的清单
configure_mcp_optional() {
  log_info "=== MCP 安装 ==="

  if ! gum confirm "是否安装 MCP？"; then
    log_info "已跳过 MCP 安装"
    return 0
  fi

  # 1. 从 mcp-servers.json 读所有可选 MCP
  log_info "MCP 选项："
  jq -r '.mcpServers | to_entries[]
    | "  • \(.key): \(.value.description // "(无描述)")"' "${MCP_SERVERS_JSON}" >&2
  echo >&2

  log_info "请选择要安装的 MCP（空格勾选，回车确认；直接回车=全不选）"
  local all_names
  all_names="$(jq -r '.mcpServers | keys[]' "${MCP_SERVERS_JSON}")"
  local chosen
  chosen="$(echo "${all_names}" | gum choose --no-limit || true)"

  if [[ -z "${chosen}" ]]; then
    log_info "未选择任何 MCP，跳过"
    return 0
  fi

  local chosen_names=()
  while IFS= read -r name; do
    name="${name%$'\r'}"     # 防御 CRLF：剥离尾部 \r
    [[ -n "${name}" ]] && chosen_names+=("${name}")
  done <<< "${chosen}"

  log_info "选中 ${#chosen_names[@]} 个 MCP：${chosen_names[*]}"

  # 2. 抽出选中 MCP 的原始配置（保留占位符原样）
  local chosen_names_json filled_mcps_json
  chosen_names_json="$(printf '%s\n' "${chosen_names[@]}" | jq -R . | jq -s .)"
  filled_mcps_json="$(jq -c --argjson names "${chosen_names_json}" '
    .mcpServers | with_entries(select(.key as $k | $names | index($k)))
  ' "${MCP_SERVERS_JSON}")"

  # 3. 合并到 <project>/.mcp.json
  local all_aan_names_json
  all_aan_names_json="$(jq -c '.mcpServers | keys' "${MCP_SERVERS_JSON}")"

  if [[ ! -f "${MCP_FILE}" ]]; then
    echo '{"mcpServers": {}}' > "${MCP_FILE}"
    log_info "创建新 .mcp.json"
  else
    local ts backup
    ts="$(date +%Y%m%d-%H%M%S)"
    backup="${MCP_FILE}.aan-backup-${ts}"
    cp "${MCP_FILE}" "${backup}"
    log_info "已备份原 .mcp.json → ${backup##*/}"
  fi

  local tmp
  tmp="$(mktemp)"
  jq --argjson filled "${filled_mcps_json}" \
     --argjson own "${all_aan_names_json}" '
    .mcpServers = (.mcpServers // {})
    | .mcpServers |= with_entries(select(.key as $k | $own | index($k) | not))
    | .mcpServers += $filled
  ' "${MCP_FILE}" > "${tmp}" && mv "${tmp}" "${MCP_FILE}"

  log_success "MCP 合并完成（写入 ${#chosen_names[@]} 个）"

  # 4. 末尾占位符清单
  local placeholders_list
  placeholders_list="$(jq -r --argjson names "${chosen_names_json}" '
    .mcpServers
    | to_entries[]
    | select(.key as $k | $names | index($k))
    | .key as $name
    | [.value | tostring | scan("YOUR_[A-Z0-9_]+_HERE|<[A-Z_]+_PLACEHOLDER>|__FILL_ME__")] as $phs
    | select($phs | length > 0)
    | "  - \($name): \($phs | unique | join(", "))"
  ' "${MCP_SERVERS_JSON}")"

  if [[ -n "${placeholders_list}" ]]; then
    log_warn "以下 MCP 包含占位符，请手动编辑 ${MCP_FILE} 填入真实值后 MCP 方可用："
    echo "${placeholders_list}" >&2
  fi
}

# ===== Stage 7d: apply_scan_deny =====
# 把 AAN 子模块目录加入 .claude/settings.json 的 permissions.deny
# 目的：在该项目里跑 Claude Code 时不扫描 AAN 目录，避免上下文污染
apply_scan_deny() {
  log_info "=== 屏蔽 AAN 目录扫描 ==="

  # 1. 计算 AAN 相对项目根的路径
  local rel="${AAN_ROOT#${PROJECT_ROOT}/}"
  if [[ "${rel}" == "${AAN_ROOT}" || -z "${rel}" ]]; then
    log_warn "AAN 路径不在项目根之下（${AAN_ROOT}），非 submodule 场景，跳过 scan-deny"
    return 0
  fi

  log_info "AAN 子模块路径：${rel}"
  log_info "写入后，Claude Code 在该项目运行时将不会扫描/读写该目录，避免污染上下文。"

  if ! gum confirm "是否把该目录加入 .claude/settings.json 的 permissions.deny？"; then
    log_info "已跳过 scan-deny 写入"
    log_info "如需手动操作，可编辑 ${CLAUDE_DIR}/settings.json："
    log_info "  • 添加：在 .permissions.deny 数组中写入 \"Read(${rel}/**)\" 等条目"
    log_info "  • 删除：从 .permissions.deny 数组中移除对应条目"
    return 0
  fi

  # 2. 组装 AAN 拥有的 deny 条目集合（对应当前 REL）
  local owned_json
  owned_json="$(jq -nc --arg r "${rel}" '
    ["Read", "Edit", "Write", "Glob", "Grep"]
    | map("\(.)(\($r)/**)")
  ')"

  # 3. 准备 settings.json（apply_hooks 通常已创建；此处做防御）
  local settings="${CLAUDE_DIR}/settings.json"
  if [[ ! -f "${settings}" ]]; then
    mkdir -p "${CLAUDE_DIR}"
    echo '{}' > "${settings}"
    log_info "创建新 settings.json"
  fi

  # 4. jq 合并：
  #    a) 从 .permissions.deny 剔除所有属于 AAN 拥有集合的条目（幂等重写）
  #    b) 追加本次 5 条
  #    c) unique 去重
  #    d) 清理空 deny / 空 permissions
  local tmp
  tmp="$(mktemp)"
  jq --argjson owned "${owned_json}" '
    .permissions = (.permissions // {})
    | .permissions.deny = (
        ((.permissions.deny // []) | map(select(. as $x | $owned | index($x) | not)))
        + $owned
        | unique
      )
    | if (.permissions.deny // []) == [] then del(.permissions.deny) else . end
    | if (.permissions // {}) == {} then del(.permissions) else . end
  ' "${settings}" > "${tmp}" && mv "${tmp}" "${settings}"

  log_success "scan-deny 写入完成（注入 5 条规则，路径：${rel}/**）"
}

# ===== Stage 8: summary =====
summary() {
  echo "" >&2
  log_info "========================================"
  log_info "  AAN 安装完成"
  log_info "========================================"
  log_info "  模块（${#RESOLVED_MODULES[@]} 个）：${RESOLVED_MODULES[*]}"
  log_info ""

  local mods_json
  mods_json="$(printf '%s\n' "${RESOLVED_MODULES[@]}" | jq -R . | jq -s .)"

  log_info "  资源落盘数："
  local type_id count
  while IFS= read -r type_id; do
    count="$(jq -r --arg t "${type_id}" --argjson mods "${mods_json}" '
      [ $mods[] as $m | .modules[$m][$t][]? ] | unique | length
    ' "${MANIFESTS_JSON}")"
    log_info "    - ${type_id}: ${count}"
  done < <(registry_types)

  log_info ""
  log_info "  产物位置："
  log_info "    ${CLAUDE_DIR}/                    (所选文件型资源)"
  log_info "    ${CLAUDE_DIR}/settings.json       (hooks + permissions.deny 可屏蔽 AAN 目录扫描)"
  log_info "    ${CLAUDE_DIR}/scripts/            (hooks 依赖的 node 脚本)"
  [[ -f "${MCP_FILE}" ]] && \
    log_info "    ${MCP_FILE}                      (MCP 配置)"
  log_info "========================================"
  log_info ""
  log_info "  下一步：在该项目目录启动 Claude Code 即可使用 AAN 能力。"
}

# ===== main =====
main() {
  log_info "AAN 安装器启动"
  preflight
  detect_context
  load_manifests
  init_registry
  select_modules
  resolve_deps
  confirm_plan
  apply_file_resources
  apply_hooks
  configure_mcp_optional
  apply_scan_deny
  summary
}

main "$@"
