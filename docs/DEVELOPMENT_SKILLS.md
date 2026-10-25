# Development skills installation report

Installed on **2026-10-25**. All seven requested additions were installed successfully for Codex and copied into this project's Claude Code skill directory.

## Installed locations

- Codex: `/home/viridjan/.codex/skills/<skill-name>/`
- Claude Code, project-local: `.claude/skills/<skill-name>/`

Every installation includes its `SKILL.md` and all accompanying files present in that upstream skill folder. The Claude copies were compared against the Codex copies by relative path and SHA-256: all matched.

The five existing skills were retained: `systematic-debugging`, `test-driven-development`, `verification-before-completion`, `godot-best-practices`, and `godot-state-machine`. The setup now covers **12 skills**.

## Seven additions

| Skill | How it helps Summit | Verified files per installation |
| --- | --- | --- |
| [performance-optimization](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/tree/184b72be02884f782a0058f2eeae2ce4277453e4/skills/disciplines/performance-optimization) | Profile frame time before optimizing chase planning, terrain rendering or sound startup. | 2 |
| [code-review](https://github.com/jwynia/agent-skills/tree/e02ec7e226a6e4f8419fd3b88a1d8e472d421b32/skills/tech/development/quality/code-review) | Review correctness, duplication, function responsibilities and coupling before larger changes. | 1 |
| [create-game-assets](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/tree/184b72be02884f782a0058f2eeae2ce4277453e4/skills/disciplines/create-game-assets) | Keep Nori, the Ape, enemies and scenery consistent in palette, proportions, native resolution and animation. | 11 |
| [level-design](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/tree/184b72be02884f782a0058f2eeae2ce4277453e4/skills/disciplines/level-design) | Plan fair jump distances, encounters, rest areas, progression gates and room flow. | 2 |
| [save-systems](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/tree/184b72be02884f782a0058f2eeae2ce4277453e4/skills/disciplines/save-systems) | Guide validation, save versioning, migration, backups and atomic writes. | 2 |
| [godot-ui-control](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/tree/184b72be02884f782a0058f2eeae2ce4277453e4/skills/godot/godot-ui-control) | Improve responsive menus, editor panels, anchors, containers, themes and keyboard/gamepad focus. | 2 |
| [godot-audio](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/tree/184b72be02884f782a0058f2eeae2ce4277453e4/skills/godot/godot-audio) | Guide positional sound, Music/SFX buses, effects, mixing and playback timing. | 2 |

## Project-specific usage

These are assistant instructions and reference material, not runtime game plugins. Installing them does not change gameplay or install their example systems into the project.

Summit's repository instructions and explicit user requests take precedence. In particular, retain the custom whole-pixel movement, 60 Hz timestep, separate movement/interaction/damage boxes, existing World/entity ownership and original asset attribution. Use relevant guidance for each task rather than forcing generic scene/node examples onto the current architecture.

- **performance-optimization:** Use measured before/after timings on the same scenario; preserve movement rules.
- **code-review:** Treat generic complexity/line-count thresholds as prompts for judgment, not reasons for a wholesale rewrite.
- **create-game-assets:** Keep the native pixel grids, established sprite anchors and atlas workflow; inspect assets in-game.
- **level-design:** Derive dimensions from Summit actual movement and verify with its room-safety tools and playtests.
- **save-systems:** Extend the existing Game/Adventure progress model rather than introducing an unrelated replacement manager.
- **godot-ui-control:** Retain existing input actions, touch behavior and readable layouts across screen sizes.
- **godot-audio:** Keep the single SiON driver, independent volume controls, bounded effect voices and original sound design.

## Reproducibility

The seven new installations were pinned to these upstream revisions, rather than an unspecified moving branch:

- `gamedev-skills/awesome-gamedev-agent-skills`: `184b72be02884f782a0058f2eeae2ce4277453e4` (six skills).
- `jwynia/agent-skills`: `e02ec7e226a6e4f8419fd3b88a1d8e472d421b32` (`code-review`).

The installer used was the existing Codex `skill-installer` helper. [tools/install-dev-skills.sh](../tools/install-dev-skills.sh) now lists all seven additions with the same revision pins, alongside the five existing skills.

To preview setup on another machine:

```sh
bash tools/install-dev-skills.sh --dry-run
```

To perform setup:

```sh
bash tools/install-dev-skills.sh
```

The helper uses `CODEX_HOME` when supplied, otherwise `~/.codex`. Existing installations are kept rather than silently overwritten. Consequently, rerunning setup is not an automatic update/downgrade operation. Claude copies live in the git-ignored `.claude/skills/` directory; the tracked setup script reproduces them for another checkout. Downloading and installing may require network/home-directory approval in a restricted environment.

## Verification performed

- All seven Codex installation commands completed successfully (six skills in one request, code review in a second request).
- Each `SKILL.md` exists and its declared name matches the requested skill.
- Every accompanying file has an identical SHA-256 in the corresponding Claude installation.
- `bash -n tools/install-dev-skills.sh` passed.
- The ordinary dry run found all 12 existing installations and preserved them.
- A fresh-install dry run with a temporary `CODEX_HOME` produced 12 install commands, including six game-development revision pins and one code-review revision pin, without installing anything.
- `git diff --check` passed after the report/setup changes.

No gameplay tests were rerun for this installation task: changes are confined to assistant skills, the development setup script and documentation.

## Installed entry-file fingerprints

These SHA-256 values identify the exact `SKILL.md` files verified in both locations:

| Skill | SHA-256 of SKILL.md |
| --- | --- |
| `performance-optimization` | `ce89bd6ffe1515a70ba8fd9302f78fb82a558a423870a09cf7c6b27a7104578f` |
| `code-review` | `fe455d2612aec9b3f82d57b19f77887a9bc52bd7c7838d27327510bef5a8261f` |
| `create-game-assets` | `36cd246a434fefe1e36feff066597a6268d9f63364bee387ee65a22f03838b5d` |
| `level-design` | `9dd60fec5dc09957f7836739da96b5a2bcff2b46ecaab020f0a9ccff7463ba3a` |
| `save-systems` | `17a7e580cdb8ee2fe654fe1b2d9ba3066c57ef1ea6a8cd9cc69141ebaea16224` |
| `godot-ui-control` | `0b2cc92d670cc2274f6579748a1703ec6a2bf70dc3d2875985deea1018f05bdc` |
| `godot-audio` | `9ed39d72403eef39e2cbedb1015262ee8413f4f71c91734ba25f82eece839b5b` |

## Availability

The newly installed Codex skills are available on the next turn. Start a fresh Claude Code session if the current session does not discover the new project-local skill folders.
