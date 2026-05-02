# Changelog

All notable changes to bbe-worktree-toolkit are documented here. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] — 2026-05-02

Bare-repo layout becomes a first-class option in `install.sh`, the
layout YAML, and every lifecycle template. v0.1.x sibling-mode
consumers (notably `bbe-sprint-machine` v0.1.0 / T-040) keep working
unchanged — all v0.2.0 changes are additive on top of the v0.1.x
codepath. v0.2.0 also ships an NPM wrapper so the toolkit is
installable via `npx @bbe-dbe/worktree-toolkit init` without
cloning.

### Added

- **`install.sh --layout auto|sibling|bare`** — auto detects the
  target repo's layout via `<root>/.bare/` plus the
  `git rev-parse --git-common-dir` shortcut. Sibling is the default
  when no explicit flag is given on a regular repo. `bare` on a
  non-bare repo exits 1 with an instruction to run
  `scripts/migrate-to-bare.sh` first.
- **`layout_mode: sibling | bare`** field in `WORKTREE_LAYOUT.yaml`.
  Optional in v0.1.x layouts (lifecycle scripts default to sibling
  when the field is absent), required in v0.2.0 fresh installs.
- **`worktree-setup.sh`** picks up `layout_mode` from the layout
  file and resolves relative `base_path` against the bare-layout
  root in bare mode (parent of `.bare/`) instead of
  `git rev-parse --show-toplevel` (which is always the active
  worktree). Sibling mode behaviour is unchanged.
- **`worktree-cleanup.sh`** carries a defensive guard: never flag a
  peer worktree on `main` or `master` for removal, even if its
  branch passes the merged-to-`origin/main` check. The guard is a
  no-op in sibling layouts (the main repo is always the current
  worktree, already skipped) and prevents cleanup-from-feature in
  bare layouts from removing the `main/` peer.
- **`worktree-status.sh --info`** — emits a JSON object with
  `layout_mode`, `layout_file`, and `main_root`. Layout-level
  metadata is exposed here so the existing `--json` output can stay
  a top-level array (preserving the `jq '.[] | ...'` pattern in
  `docs/ADVANCED.md`).
- **`tests/test-bare-mode.sh`** — 11 new tests covering
  auto-detection in both modes, explicit overrides, the
  --layout-bare-on-non-bare refusal, bare-mode setup path
  resolution, status `--info`, idempotency, structural match
  against v0.1.x templates, and the cleanup defensive guard.
- **NPM wrapper** (T-051). Toolkit installable via
  `npx @bbe-dbe/worktree-toolkit init` without cloning. The wrapper
  is a thin Node.js bin (`bin/bbe-worktree.js`) that exec's
  `install.sh` inside the installed package, so the scaffolder
  remains the single source of truth. Subcommands: `init` / `check`
  / `uninstall` / `version` / `help`. Bin names: `bbe-worktree`
  and `worktree-toolkit`.
- `package.json` declares the `@bbe-dbe/worktree-toolkit` package
  with a whitelist `files` field that ships only `install.sh`,
  `VERSION`, `templates/`, `bin/`, `LICENSE`, `README.md`,
  `CHANGELOG.md`, and `PATTERN.md`. `tests/`, `docs/`, and `.git*`
  are excluded from the tarball.
- `tests/test-npm-wrapper.sh` — 14 checks covering help/version/
  unknown exit codes, init forwarding, idempotency through the
  wrapper, the `--layout-dir` pass-through, `npm pack` tarball
  contents, and a full extract-then-init round-trip from the
  packed tarball.
- `README.md` — npx quickstart section (clone path retained for
  existing consumers).

### Changed

- **`scripts/migrate-to-bare.sh`** reads VERSION from `VERSION`
  instead of hardcoding `0.1.1`. The `--i-understand-the-risk`
  gate is **deliberately retained** — the v0.1.1 changelog said it
  would drop in v0.2.0, but the migration is irreversible at the
  `.git`-layout level and a typo on a production repo is
  unrecoverable; safety beats convenience here. CHANGELOG keeps
  the audit trail of the decision.
- **`tests/test-migrate-to-bare.sh`** — `check_version_flag` reads
  the toolkit `VERSION` file dynamically instead of asserting the
  literal `"0.1.1"`. Same idiom `tests/test-install.sh` already
  uses.

### Backwards compatibility

- v0.1.x installs that re-run `install.sh` after upgrading to
  v0.2.0 stay sibling-mode. The lifecycle scripts get refreshed
  with v0.2.0 templates (which add bare-mode awareness as
  additive code paths), but the YAML's `layout_mode` defaults to
  `sibling` and the sibling codepath in every script is
  byte-equivalent to v0.1.x behaviour.
- `bbe-sprint-machine` v0.1.0 / T-040 is verified to still work
  unmodified — its consumer assumes sibling mode and does not
  inspect `layout_mode`.
- The `--json` output of `worktree-status.sh` stays a top-level
  array. New layout-level metadata lives under the new `--info`
  subcommand instead.

### Soft decisions (documented for the audit trail)

1. **Bit-identical interpretation.** "v0.1.x install outputs must
   stay bit-identical after v0.2.0 install" is interpreted as
   *behavioural equivalence + structural compatibility for sibling
   consumers*, not byte-level diff equivalence. Adding bare-mode
   support necessarily adds new helpers + the `layout_mode` field;
   no v0.1.x code path is altered, so consumers cannot observe a
   functional difference. `tests/test-bare-mode.sh` includes a
   "structural match" check that confirms rendered v0.2.0
   sibling-mode scripts equal v0.1.x templates after `{{LAYOUT_DIR}}`
   substitution (the v0.1.x guarantee).
2. **`--i-understand-the-risk` retained.** The v0.1.1 docstring
   announced this gate would go away in v0.2.0; v0.2.0 keeps it
   because the migration is irreversible. Operators who want
   automated migrations can set `WTT_MIGRATE_CONFIRM=1` in CI.
3. **`--info` for layout-level metadata, not wrapped JSON.** The
   alternative was wrapping `--json` output in
   `{"layout_mode": ..., "worktrees": [...]}`. That would break the
   `docs/ADVANCED.md` example `jq '.[] | ...'`. The `--info`
   subcommand is the additive choice.

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
- v0.2.0 keeps the `--i-understand-the-risk` gate (announced as
  "will drop in v0.2.0" by v0.1.1, retained deliberately — see the
  `[0.2.0]` Soft decisions section).

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

[0.2.0]: https://github.com/BBE-DBE/bbe-worktree-toolkit/releases/tag/v0.2.0
[0.1.1]: https://github.com/BBE-DBE/bbe-worktree-toolkit/releases/tag/v0.1.1
[0.1.0]: https://github.com/BBE-DBE/bbe-worktree-toolkit/releases/tag/v0.1.0
