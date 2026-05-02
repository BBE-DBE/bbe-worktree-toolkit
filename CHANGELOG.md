# Changelog

All notable changes to bbe-worktree-toolkit are documented here. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] — 2026-05-02

Documentation + skeleton tooling for the v0.2.0 bare-repo layout.
`install.sh` and the v0.1.0 templates are unchanged — this release
is purely additive.

### Added

- `docs/BARE_REPO_PATTERN.md` — sibling vs. bare-repo layout
  comparison with ASCII diagrams, when-to-pick-which guidance, and
  industry references (pnpm, MindStudio, dev.to, Augment Code).
- `docs/MIGRATION.md` — new "From Sibling to Bare-Repo" section
  with step-by-step migration walkthrough, risks, and rollback path.
- `scripts/migrate-to-bare.sh` — five-stage migration script
  (Backup → Detect → Convert → Reattach → Verify). Default mode is
  `--dry-run`; `--execute` is gated behind
  `--i-understand-the-risk` (or `WTT_MIGRATE_CONFIRM=1`).
  Idempotent: a second run detects the bare layout and exits 0.
- `tests/test-migrate-to-bare.sh` — six lifecycle tests in the
  `/tmp/wtt-migrate-test-$$/` sandbox, including a full
  `--execute` round-trip that verifies the bare layout is created
  and worktrees are reattached.

### Notes

- VERSION bumped to 0.1.1 (patch). Strict SemVer would call this
  MINOR because new files are added, but `install.sh` and the
  templates are untouched and the migration tool is explicitly
  marked experimental, so v0.1.x continues until v0.2.0 promotes
  bare-repo layout to first-class.
- v0.2.0 will drop the `--i-understand-the-risk` gate and add
  `install.sh --bare` for fresh bare-repo installs.

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

[0.1.1]: https://github.com/BBE-DBE/bbe-worktree-toolkit/releases/tag/v0.1.1
[0.1.0]: https://github.com/BBE-DBE/bbe-worktree-toolkit/releases/tag/v0.1.0
