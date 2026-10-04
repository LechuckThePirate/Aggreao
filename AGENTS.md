# Aggreao!! — agent guide

World of Warcraft addon: a small, movable aggro window for your target (who has the aggro, in order, class colors, tank/healer/dps
and pet icons, sound alert when you are about to pull, optional "other mobs in combat" section). Targets Retail, TBC Anniversary,
Classic Era and the Classic "Forever" beta (`## Interface: 120100, 20506, 11509, 16001`); development targets Forever first.
Public repo `LechuckThePirate/Aggreao` (branch `master`), GPLv3, CurseForge project id 1720655. Siblings with the same conventions:
`Completao` (the template this repo was cloned from) and `Embolsao`, under `D:\Source\WowAddons\`.

## How to work with the maintainer

- **Chat in Spanish from Spain** ("tú", never Argentine voseo: not "tenés", "contame", "dale"). **Everything committed is in English**:
  code comments, test names, docs, workflow comments, commit messages. Spanish only in the esES/esMX table of `Localization/Locale.lua` (the `esMX` TOC notes
  are Spanish too).
- Windows machine. Prefer the PowerShell tool over Bash. Multi-line commit messages: write a file and use `git commit -F <file>`.
- Work happens in git worktrees (`.claude/worktrees/<name>`, branch `claude/<name>`). **After every change (tests green) commit and
  push** (`git push origin HEAD`). **Merging to `master` and releasing only happen when the maintainer asks.**
- Keep the maintainer informed in one or two short lines during long tasks.

## Layout

Addon files at the repo root, packaged as the folder `Aggreao` (`.pkgmeta`):

- `Aggreao.toc` (load order), `Aggreao.lua` (entry point: events and `/aggreao`, `/agg`; loaded last)
- `Localization/Locale.lua` — English text is the key, with the Spanish (esES/esMX) table; more locales can be added as files
- `Modules/{Settings,Threat,Alert,UI}/` — every `X.lua` has `X.test.lua` next to it
  (Threat = who has the aggro and the fallbacks per client, Alert = the "about to pull" sound/border, UI = meter, layout, menu,
  minimap button, preferences, welcome/changelog window)
- `test/` (WoW API mock + local runner), `setupTests.lua`, `Icons/`, `images/screencaps/` (CurseForge description images)

How well it works depends on what each client tells addons about threat: where `UnitDetailedThreatSituation` is available it
lists everybody's threat; otherwise it falls back to the mob's current target as the one holding the aggro.

## Commands (PowerShell, repo root)

```powershell
lua test/busted.lua                       # all tests, no busted install needed (Lua 5.1+)
busted -p ".test.lua" .                   # real busted (what CI runs, Lua 5.1)
luacheck Aggreao.lua Localization Modules Aggreao.test.lua test setupTests.lua   # if installed
```

No deploy script: copy or symlink the repo root as `Aggreao` into
`D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\` (without `test/`, `images/`, `*.test.lua`, `setupTests.lua`), then
`/reload`. (Another copy of the addon is also installed in the other clients' AddOns folders.)

## Code conventions

- Lua 5.1. Shared namespace: `local ADDON, ns = ...` in every file; no new globals (see `.luacheckrc`).
- English text is the localization key: `ns.L["Some text"]`; translations go in `Localization/`.
- Every module gets a `*.test.lua` next to it, starting with `dofile("setupTests.lua")`. CI runs luacheck and busted on Lua 5.1.
- Comments explain *why*, are short, and match the surrounding density. Match surrounding naming and idiom.
- Commit style: `feat(scope):`, `fix(scope):`, `perf(scope):`, `release: X.Y.Z -- short summary`.
- User-visible changes go in `CHANGELOG.md` (newest first, `New:` / `Fix:` bullets, plain sentences).

## Infra and release

- **CI:** `.github/workflows/ci.yml` (luacheck + busted on every push and PR).
- **Release** (only when asked): one commit `release: X.Y.Z -- short summary` that bumps `## Version` in `Aggreao.toc`, adds the section
  to `CHANGELOG.md` and updates `LATEST_CHANGELOG_TEXT` in `Modules/UI/Welcome.lua`; then `git tag vX.Y.Z`, push `master` and the tag, and
  `gh workflow run release.yml --repo LechuckThePirate/Aggreao --ref vX.Y.Z` (workflow_dispatch only; BigWigsMods/packager uploads to
  CurseForge with repo secret `CF_API_KEY` and creates the GitHub release). Watch with `gh run watch`.
- **Screenshots:** `images/screencaps/*.png` are shrunk and rsynced by `.github/workflows/sync-media.yml` (push to master touching that
  path, or `gh workflow run sync-media.yml`; skipped while there is no PNG) to
  `https://media.joanvilarino.online/aggreao/images/screencaps/`, which `CURSEFORGE_DESCRIPTION.md` references. Secret
  `AGGREAO_MEDIA_SSH_KEY` (restricted rsync-only user on the maintainer's VPS; the media host itself is configured in the Embolsao repo).
- `.pkgmeta` keeps images, tests and `CURSEFORGE_DESCRIPTION.md` out of the package.
