#!/usr/bin/env bash
# Developer setup utility, separate from the game. Installs external coding skill instructions into tool-specific directories; --dry-run prints operations without downloading or copying.
# Reading help: docs/CODE_GUIDE.md.

# Network access and writes to the global skills directory may require approval.
# Installs for Codex (~/.codex/skills) and copies them to .claude/skills/ for Claude Code (git-ignored).
# Uses the bundled Codex installer; downloads skill directories and their resources.
set -euo pipefail

skills_dry_run=false
case "${1:-}" in
  '') ;;
  --dry-run) skills_dry_run=true ;;
  *) printf 'Usage: bash %s [--dry-run]\n' "$0" >&2; exit 2 ;;
esac

skills_codex_root="${CODEX_HOME:-$HOME/.codex}"
skills_installer="$skills_codex_root/skills/.system/skill-installer/scripts/install-skill-from-github.py"
skills_destination="$skills_codex_root/skills"
# Claude Code reads project skills from here (git-ignored: third-party code, recreated by this script).
skills_project_dir="$(cd "$(dirname "$0")/.." && pwd)/.claude/skills"
skills_installed=()

if [[ ! -f "$skills_installer" ]]; then
  printf 'Bundled Codex skill installer not found: %s\n' "$skills_installer" >&2
  exit 2
fi

# Install one requested skill only when its destination is safe; dry-run mode prints the command instead.
install_one_skill() {
  local skill_repo="$1" skill_path="$2" skill_name="${2##*/}"
  local skill_ref="${3:-main}"  # Optional revision pin makes newly added skills reproducible.
  skills_installed+=("$skill_name")
  if [[ -f "$skills_destination/$skill_name/SKILL.md" ]]; then
    printf 'Already installed; keeping existing version: %s\n' "$skill_name"
    return
  fi
  if [[ -e "$skills_destination/$skill_name" || -L "$skills_destination/$skill_name" ]]; then
    printf 'Destination exists without SKILL.md; leaving it untouched: %s\n' "$skills_destination/$skill_name" >&2
    return 2
  fi
  local skill_command=(python3 "$skills_installer" --repo "$skill_repo" --path "$skill_path" --ref "$skill_ref" --dest "$skills_destination")
  if "$skills_dry_run"; then
    printf '%q ' "${skill_command[@]}"
    printf '\n'
  else
    "${skill_command[@]}"
    if [[ ! -s "$skills_destination/$skill_name/SKILL.md" ]]; then
      printf 'Installation did not produce a valid entry file: %s\n' "$skill_name" >&2
      return 2
    fi
  fi
}

# Coding quality: investigation, focused regression tests, evidence before completion.
install_one_skill obra/superpowers skills/systematic-debugging
install_one_skill obra/superpowers skills/test-driven-development
install_one_skill obra/superpowers skills/verification-before-completion
# Godot 4 / GDScript conventions, architecture, performance and scene organization.
install_one_skill jwynia/agent-skills skills/tech/game-development/godot/godot-best-practices
# Godot player/enemy state lifecycles with bundled GDScript reference implementations.
install_one_skill gaoyuan-taka/godot-action-adventure-skills godot-state-machine

# Additional skills reviewed for Summit. Pin upstream revisions so a fresh setup gets the same instructions.
skills_gamedev_ref=184b72be02884f782a0058f2eeae2ce4277453e4
skills_review_ref=e02ec7e226a6e4f8419fd3b88a1d8e472d421b32
install_one_skill gamedev-skills/awesome-gamedev-agent-skills skills/disciplines/performance-optimization "$skills_gamedev_ref"
install_one_skill jwynia/agent-skills skills/tech/development/quality/code-review "$skills_review_ref"
install_one_skill gamedev-skills/awesome-gamedev-agent-skills skills/disciplines/create-game-assets "$skills_gamedev_ref"
install_one_skill gamedev-skills/awesome-gamedev-agent-skills skills/disciplines/level-design "$skills_gamedev_ref"
install_one_skill gamedev-skills/awesome-gamedev-agent-skills skills/disciplines/save-systems "$skills_gamedev_ref"
install_one_skill gamedev-skills/awesome-gamedev-agent-skills skills/godot/godot-ui-control "$skills_gamedev_ref"
install_one_skill gamedev-skills/awesome-gamedev-agent-skills skills/godot/godot-audio "$skills_gamedev_ref"

for skill_name in "${skills_installed[@]}"; do
  if [[ -f "$skills_project_dir/$skill_name/SKILL.md" ]]; then
    continue
  fi
  if "$skills_dry_run"; then
    printf 'cp -r %q %q\n' "$skills_destination/$skill_name" "$skills_project_dir/"
  else
    mkdir -p "$skills_project_dir"
    cp -r "$skills_destination/$skill_name" "$skills_project_dir/"
  fi
done

if "$skills_dry_run"; then
  printf 'Dry run only: no skills were downloaded or installed.\n'
else
  printf 'Skills installed. They will be available on your next Codex turn.\n'
fi
