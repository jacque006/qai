## Context

We are building **QAI**: a style/configuration layer on top of the LOUD AI modification for Supreme Commander: Forged Alliance (SCFA). The name is a nod to the in-universe Quantum AI from Supreme Commander lore — the rogue intelligence that infiltrates other AIs and bends them to new purposes, which is precisely what this project does to LOUD (non-rogue, at the user's pleasure). The long-term vision is that a user describes a play style in natural language ("zerg rush me," "make me feel under siege at Helm's Deep"), an external tool compiles that into a declarative config, and the LOUD AI plays that way. **The current milestone is the vertical slice**: prove that an external config file measurably changes LOUD's in-game behavior, end to end.

The eventual architecture (for context, not for now): a Lua "style governor" inside the game reads a declarative config at game start and bends LOUD's existing decision-making toward it. Right now the config is a hand-written Lua file living in the LOUD install; later, a local LLM compiler will generate it. Do not build the LLM, containers, or any network components now.

## Environment facts (reported by the player; you cannot verify them directly)

- OS: Ubuntu Linux. Game runs via **Steam Proton**.
- Game install: `$HOME/.steam/steam/steamapps/common/Supreme Commander Forged Alliance`.
- LOUD is installed as a **full parallel game tree** inside that directory: `LOUD/bin/`, `LOUD/gamedata/`, `LOUD/doc/`, `LOUD/maps/`, `LOUD/usermaps/`, plus a modern launcher `LOVE-LOUD.exe` (LÖVE/SDL-based) at the game root alongside `lua51.dll`, `love.dll`, `SDL3.dll`.
- Iteration loop is **AI vs. AI**: QAI-configured LOUD in one slot, stock LOUD in the other, small map, high game speed, replays saved.
- SCFA is a **deterministic lockstep simulation**. Any Lua we add runs inside the sim on all clients. All changes must be deterministic and must be active from game start (loaded during init), never conditionally injected mid-game.
- **The in-game Lua environment is sandboxed**: `io` and `os` libraries are restricted. Our Lua code cannot read arbitrary files or spawn processes. The config must be a Lua file the game's own file-loading mechanism can load, inside the game/LOUD directory tree.

## Collaboration protocol (this repo has no CI; the player is the executor)

You write code and scripts; the player runs them on the game machine and commits the outputs. Every script you write must follow these rules:

1. **Scripts are zero-assumption.** They must locate paths themselves (probe `$HOME/.steam/steam/steamapps/common/Supreme Commander Forged Alliance`, honor `STEAM_LIBRARY` env var override if set), be idempotent, and print exactly what they did.
2. **Observations come back as files in `observations/`.** Scripts you write for the player to run must write their output into an `observations/` directory with a dated filename (e.g. `observations/2026-11-02-discovery-1.txt`) suitable for committing. Scripts must print a reminder to the player: "commit this file and tell the agent it's ready."
3. **Never expect interactive feedback mid-script.** If a script needs a decision, it should stop and write a question into its output file.
4. **License hygiene is law.** This repo is PUBLIC, licensed **Unlicense** (public domain dedication) — but that dedication covers only THIS repository's original contents. It must contain no LOUD code or game assets. Discovery scripts may excerpt small snippets (a few consecutive lines, ≤15 lines per excerpt) into observation files for analysis, but must NOT bulk-copy LOUD source, docs, `.scd` archives, maps, or any game files into the repo. When in doubt, capture paths, sizes, line numbers, and structure rather than content. If a script's raw output would contain bulk LOUD material, the script must sanitize it before writing (paths + short excerpts only).
5. **Privacy and data minimization are equally mandatory.** See the dedicated section below. Every script that produces output destined for this repo must pass through the sanitizer described there. This is not optional and not deferrable.

## Privacy, PII, and machine-fingerprint rules (MANDATORY — read before writing any script)

**Threat model.** This repository is public. Observation files are committed to git, which means anything that lands there is permanent, world-readable, and effectively irretrievable — removing a file in a later commit does not remove it from history. The project intends to onboard third-party testers, whose machines must not be identifiable or distinguishable from one another by anything they commit. Assume every byte a script writes will be published.

**Absolute prohibitions — scripts must never collect, log, echo, hash, or transmit:**

- Usernames, real names, email addresses, or account handles (`whoami`, `id`, `$USER`, `$LOGNAME`, git config, shell prompts).
- Hostnames, machine IDs, `/etc/machine-id`, DMI/product UUIDs, serial numbers, MAC addresses, IP addresses, SSIDs, or any network configuration.
- Steam account identifiers: SteamID64, SteamID3, friend codes, or anything under `~/.steam/steam/userdata/`. Never traverse that directory at all.
- Absolute home-directory paths in expanded form (see normalization below).
- Environment variable dumps (`env`, `printenv`, `set`) — these routinely contain API tokens, secrets, and account identifiers.
- Process listings (`ps`, `top`, `systemctl`), installed-package inventories, GPU/CPU serial identifiers, or anything describing software beyond the game install itself.
- Browser data, SSH keys, dotfiles, shell history, clipboard, or any other userspace file outside the game install tree.
- Absolute file timestamps that reveal activity patterns (see normalization below).

**Read scope is narrowly bounded.** Scripts may read only: the resolved game install directory, and — for the sole purpose of locating log files — the specific Proton `compatdata` prefix directory associated with the game's Steam app ID. Within the prefix, scripts may stat and read `*.log` files only; they must not enumerate the prefix's broader directory tree, and must not read registry files, config files, or anything else there. Nothing outside these bounds may be opened, statted, or listed. Scripts must never *write* anywhere except the repo's own `observations/` directory (and, for the installer only, the LOUD tree itself, with backup).

**Path normalization (required).** All output must be normalized before writing so that two different machines produce structurally identical text:

- Replace the expanded home directory with the literal token `$HOME` (e.g. `$HOME/.steam/steam/...`).
- Replace any other absolute path segment that embeds a username with `<user>`.
- Replace hostname-derived strings with `<host>`.
- Convert absolute file modification times to relative ages (e.g. `modified: 2h ago`, `modified: 3d ago`) rather than printing dates. Relative ages convey "is this log recent?" without fingerprinting a timezone or a sleep schedule.
- Normalize locale-, timezone-, and terminal-dependent output: force `LC_ALL=C`, disable color, disable any progress bars or spinner characters, and avoid `ls` column formatting that varies by terminal width.

**Sanitizer implementation requirement.** Write the sanitizer once as a reusable, auditable function — `tools/sanitize.sh` (or a Python module if you prefer, but it must be invocable standalone) — and route every observation file through it. It must:

- Apply the normalization rules above.
- Redact anything matching a denylist of patterns: email addresses, IPv4/IPv6 literals, MAC addresses, 17-digit Steam IDs, `/home/<anything>` and `/Users/<anything>` paths, and common API-key shapes (`sk-`, `ghp_`, `AKIA`, long base64/hex blobs).
- Support a `--check` mode that scans an existing file and exits nonzero, listing offending line numbers, if anything suspicious remains. Every capture script must invoke `--check` on its own output as a final step and refuse to leave a failing file in place (delete it and report instead).
- Be conservative: when in doubt, redact. A false positive costs one unusable line; a false negative costs a stranger's privacy permanently.

**Game logs need specific scrubbing.** SCFA logs can contain player display names, chat text, and lobby names. The `qai capture` step must extract only `QAI:`-prefixed lines and game-mechanical data (timings, unit counts, build orders), and must drop chat content, player names, and lobby identifiers entirely. If a `QAI:` line itself somehow embeds a player name, redact it.

**Verification duty.** Before you (the agent) treat any observation file as usable, scan it for the prohibited classes above and say so explicitly in your response. If you find a violation in a file that has already been committed, do not merely ask for a follow-up commit: state plainly that the exposure persists in git history and that remediation requires either history rewriting or deleting and recreating the repository. Flag it prominently.

**Third-party testers.** Maintain `TESTERS.md` documenting, in plain language: what the scripts read, what they never read, that all output is normalized and sanitized, that committed observations are public and permanent, and that a tester should read the script before running it. Do not ask testers for any personal information, and do not build features that require it. If a future feature seems to need machine-identifying data, propose an alternative or ask the player first — never collect it silently.

## Phase 0 — Remote discovery (do this before writing any feature code; budget significant effort here)

Since you cannot read the game tree, your first deliverable is a **discovery harvester**: `tools/discover_local.sh` (bash, stdlib only, no deps) that the player runs on the game machine. It must pipe all output through `tools/sanitize.sh` and write to `observations/<date>-discovery-N.txt`. It should collect:

1. **Tree map:** directory listings of `LOUD/` (top two levels), plus any `lua/` or AI-related directories inside `LOUD/gamedata/` or `LOUD/bin/`, with filenames that hint at AI behavior (`AI`, `Sorian`, `platoon`, `builder`, `engineer`, `brain`, LOUD-specific names). Paths normalized.
2. **Documentation digest:** the table of contents / headings of every file in `LOUD/doc/` — filenames, section headers, and ≤15-line excerpts ONLY where a header references AI customization, tuning, personalities, difficulty, or configuration.
3. **Candidate knob hunt:** grep results (normalized path + line number + one-line excerpt) for likely tunable values: factory build ratios, engineer count targets, attack/platoon timers, aggression or threat thresholds, tech-level gating, experimental-unit conditions.
4. **Log location probe:** search the game directory and the app-ID-specific Proton compatdata prefix for recent `*.log` files; report normalized paths, sizes, and relative modification ages.

Write the script defensively: if something is absent, report "NOT FOUND" and continue, never crash. After the player commits the observation file, YOU analyze it and iterate the script if the first pass missed obvious structure (expect 2–3 rounds). Record your findings and conclusions — hook points, the load-point for new Lua files, three concrete numeric knobs with normalized file paths — in `docs/discovery.md`, citing which observation file and line each conclusion came from.

If any Phase 0 answer stays ambiguous after two harvester rounds, record the ambiguity, choose the most conservative interpretation, and proceed. Do not stall the project on perfect certainty.

## Phase 1 — Vertical slice (current milestone)

1. **Config format.** Author `styles/style_schema.lua` defining a table with the knobs confirmed in Phase 0. Keep it small — 5 to 15 numeric/boolean fields max. Include a `meta` sub-table: `name`, `description`, `version`.
2. **Governor.** Author `lua/qai_governor.lua`: loads the chosen style config, validates it (fail loudly to the log with the `QAI:` prefix if a field is missing or out of range, falling back to defaults), and applies the knob values at the LOUD hook points found in Phase 0. Every applied value is logged once at game start: `QAI: applied aggression=0.9 from style 'zerg_rush'`. The governor must be a thin layer — it assigns values; it does not reimplement AI logic. It cannot read files at runtime beyond what the game's loader provides, so the style selection must ride the file tree (see below).
3. **Two starter styles.** `styles/zerg_rush.lua` — maximally aggressive early spam: high aggression, early constant attacks, minimal expansion, delayed/no teching past a threshold. `styles/turtle_siege.lua` — the opposite: defensive posture, slow expansion, late big pushes. Both must stay within the validated ranges of the knobs.
4. **Selection mechanism.** Simplest possible: a single `styles/active_style.lua` (or a tiny `styles/_selected.lua` that returns one of the style tables by name). The governor loads only that. Switching styles = the player editing one file via the `qai` CLI + restarting the skirmish.
5. **Installer.** `install/install.sh` / `install/uninstall.sh`. The installer must first create a timestamped backup of any LOUD file it will modify (or of the whole target area if modifications are scattered), then install. `uninstall.sh` restores the most recent backup. Every modified file must be tracked in `docs/modified-files.md`. After install, print a preflight checklist: which files went where, where the log should appear, exactly how to launch the test game (map suggestion, slots, speed).
6. **Python CLI (`tools/qai.py`).** Commands: `qai list`, `qai validate <name>`, `qai select <name>`, `qai doctor` (verifies install: files present, backup exists, log locatable — the doctor command runs ON the game machine, invoked by the player). No LLM, no network. Stdlib only. All output sanitized.
7. **Observation capture for testing.** Extend the CLI (or `install.sh`) with `qai capture` — a small script the player runs AFTER a test game that extracts only `QAI:`-prefixed log lines plus basic game-mechanical result info (timings, unit counts, outcome) into `observations/<date>-match-N.txt` for committing. It must strip chat, player names, and lobby identifiers, run the sanitizer, and self-check with `--check` before finishing. This is how you, the agent, see the results of each playtest.
8. **Test plan (`test/test-plan-tonight.md`).** A concrete scripted check: AI vs. AI, QAI-styled LOUD in one slot vs. stock LOUD in the other (the stock slot selects the `default` passthrough style so it behaves as stock), small map, fixed settings, high speed. Define observable pass/fail criteria per style, drawn from data the `qai capture` step can actually gather (log timestamps, applied-values confirmation) plus a short qualitative checklist the player fills in by hand after watching the replay, e.g.: for `zerg_rush`, "first attack noticeably earlier than stock baseline"; for `turtle_siege`, "visibly fewer expansions by mid-game."

## Rules of engagement

- **Modify LOUD files minimally and reversibly.** Prefer additive files plus a handful of one-line hook insertions over rewrites. Every insertion point documented in `docs/modified-files.md`.
- **Determinism is law.** No randomness beyond what LOUD already does, no time-of-day calls, nothing that could desync a multiplayer game.
- **No game assets or LOUD code in the repo.** Short quoted excerpts (≤15 lines) in `docs/` and `observations/` are acceptable for analysis; bulk copying is not.
- **No PII, no machine fingerprints, no sensitive userspace data.** See the privacy section. Every committed artifact must be normalized and sanitized, and must be indistinguishable from the equivalent artifact produced on a different machine.
- **Log everything with the `QAI:` prefix.** Quiet failure is the enemy of a one-evening project.
- When unsure about LOUD internals, **request another harvester round** rather than guessing. The tree on the player's machine is ground truth, not general knowledge about Supreme Commander modding — base-game conventions and LOUD's conventions may differ.
- Commits should be small and coherent, one logical unit each, with messages that the player could read aloud to understand what changed. Maintain a `docs/session-log.md` where each work session's state is summarized, so a future session (possibly a different agent context) can resume without re-reading the whole repo.

## Definition of done for this milestone

The installer runs clean on the player's machine; an AI-vs-AI skirmish produces `QAI:` lines in the committed match observations confirming the selected style and its values; the same scenario run with `zerg_rush` versus `turtle_siege` produces observably different AI behavior per the test plan; uninstall restores the pristine tree; `docs/discovery.md` records LOUD's structure well enough that the knob set can be extended next session without redoing discovery; and every committed observation file passes the sanitizer's `--check` with no PII, no machine identifiers, and no expanded home paths.

Begin by writing `tools/sanitize.sh` FIRST (nothing else can be trusted until it exists), then the Phase 0 harvester script, then the README (three paragraphs: what QAI is, the architecture, current status — acknowledge the lore name up front). Commit those, and end your turn with a short instruction to the player: exactly which command to run on their machine and what to do with the output.
