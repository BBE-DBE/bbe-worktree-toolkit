#!/usr/bin/env node
// bbe-worktree — npm wrapper around install.sh.
//
// The toolkit's behaviour lives in install.sh (see TOOLKIT_DIR sibling
// files: VERSION, templates/, LICENSE). This wrapper exists so the
// operator can run:
//
//   npx @bbe-dbe/worktree-toolkit init
//
// without cloning the repo. We resolve install.sh inside the installed
// package (one directory up from this file) and exec bash with the
// user's args. Anything not understood as a subcommand is forwarded
// verbatim, so install.sh remains the source of truth for flags.
//
// Exit codes: 0 success, 64 usage, 66 install.sh missing, otherwise
// whatever install.sh exits with.

'use strict';

const { spawnSync } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');

const PACKAGE_ROOT = path.resolve(__dirname, '..');
const INSTALL_SH = path.join(PACKAGE_ROOT, 'install.sh');
const VERSION_FILE = path.join(PACKAGE_ROOT, 'VERSION');
const PACKAGE_JSON = path.join(PACKAGE_ROOT, 'package.json');

function fail(msg, code = 1) {
  process.stderr.write(`bbe-worktree: ${msg}\n`);
  process.exit(code);
}

function showHelp() {
  process.stdout.write(`bbe-worktree-toolkit — npm wrapper around install.sh

Usage:
  npx @bbe-dbe/worktree-toolkit <command> [options]

Commands:
  init [options]   Scaffold the toolkit into the current git repo. Any
                   options are forwarded to install.sh. Examples:
                     npx @bbe-dbe/worktree-toolkit init
                     npx @bbe-dbe/worktree-toolkit init --layout-dir .bbe-coord
                     npx @bbe-dbe/worktree-toolkit init --base-path ../wt
  check            Print install state in the current repo.
                   (forwards to install.sh --check)
  uninstall        Remove toolkit-installed files.
                   (forwards to install.sh --uninstall)
  version          Print the npm package version + the bundled
                   toolkit VERSION.
  help             Show this message.

The toolkit's full flag set is documented in install.sh (--help) and
in README.md / docs/QUICKSTART.md.
`);
}

function readVersionFile() {
  try {
    return fs.readFileSync(VERSION_FILE, 'utf8').trim();
  } catch {
    return 'unknown';
  }
}

function readPackageVersion() {
  try {
    return JSON.parse(fs.readFileSync(PACKAGE_JSON, 'utf8')).version;
  } catch {
    return 'unknown';
  }
}

function execInstallSh(args) {
  if (!fs.existsSync(INSTALL_SH)) {
    fail(`install.sh not found at ${INSTALL_SH} — package may be corrupted`, 66);
  }
  const result = spawnSync('bash', [INSTALL_SH, ...args], {
    stdio: 'inherit',
    cwd: process.cwd(),
  });
  if (result.error) {
    if (result.error.code === 'ENOENT') {
      fail('bash not found on PATH — bash >= 4 is required', 66);
    }
    fail(result.error.message, 1);
  }
  process.exit(result.status === null ? 1 : result.status);
}

function main(argv) {
  const args = argv.slice(2);
  const cmd = args[0];
  const rest = args.slice(1);

  if (cmd === undefined || cmd === 'help' || cmd === '-h' || cmd === '--help') {
    showHelp();
    process.exit(0);
  }

  switch (cmd) {
    case 'init':
      execInstallSh(rest);
      return;
    case 'check':
      execInstallSh(['--check', ...rest]);
      return;
    case 'uninstall':
      execInstallSh(['--uninstall', ...rest]);
      return;
    case 'version':
    case '-v':
    case '--version': {
      const pkgV = readPackageVersion();
      const tkV = readVersionFile();
      process.stdout.write(`bbe-worktree-toolkit npm package: ${pkgV}\n`);
      process.stdout.write(`bbe-worktree-toolkit toolkit:     ${tkV}\n`);
      process.exit(0);
      return;
    }
    default:
      fail(
        `unknown command: ${cmd}\n  valid: init | check | uninstall | version | help`,
        64,
      );
  }
}

main(process.argv);
