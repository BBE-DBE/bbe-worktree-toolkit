# Changelog

All notable changes to bbe-worktree-toolkit are documented here. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-05-02

Initial release. Generalises the T-003 worktree architecture from
BBE-DBE's `bbe-coord` repo into a reusable scaffolding toolkit.

### Added

- `install.sh` — idempotent scaffolder that drops the layout YAML, the
  three lifecycle scripts, and (optionally) appends a doctrine rule
  plus rationale to a target repo.
- `templates/WORKTREE_LAYOUT.yaml.tmpl` — per-repo layout config with
  token substitution for `base_path`, `central_state_dir`, and the
  layout directory.
- `templates/worktree-setup.sh` — `create` / `list` / `remove`
  subcommands; refuses dirty worktrees and unmerged branches without
  `--force`; supports tracks `track_a`, `track_b`, `track_c`.
- `templates/worktree-cleanup.sh` — finds merged-or-deleted-branch
  worktrees plus 24h+ stashes; `--dry-run` default, `--execute`
  applies and writes `tmp/worktree-cleanup.log`.
- `templates/worktree-status.sh` — read-only summary, table or
  `--json` view, plus `--check` mode for CI gating.
- `templates/doctrine-snippet.yaml` — optional integration with a
  target repo's `DOCTRINE.yaml` and `DOCTRINE_RATIONALE.md`. Append-
  only with `# >>> bbe-worktree-toolkit T-030 BEGIN/END <<<` markers.
- `tests/test-install.sh`, `test-setup.sh`, `test-cleanup.sh`, plus
  `tests/run-all.sh` and `tests/fixtures/empty-repo/`.
- `docs/QUICKSTART.md`, `docs/ADVANCED.md`, `docs/MIGRATION.md`,
  `docs/TROUBLESHOOTING.md`.
- `PATTERN.md` documents the failure mode that motivated the toolkit
  and the industry precedent (Augment Code, MindStudio, pnpm).

### Constraints (initial release)

- Bash 4+ and GNU sed/awk. macOS / BSD coverage is on the roadmap.
- `git ≥ 2.5` required. `yq` and `jq` recommended but not strict.
- Tested on Linux only; Linux + Bash 5 is the reference platform.

[0.1.0]: https://github.com/BBE-DBE/bbe-worktree-toolkit/releases/tag/v0.1.0
