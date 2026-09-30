# Aggreao!!

World of Warcraft addon. Work in progress.

Supported clients (see `Aggreao.toc`): Retail, TBC Anniversary, Classic Era and
the Classic "Forever" beta. Development targets Forever for now.

## Install (development)

Copy or symlink this repo's root as `Aggreao` into the client's AddOns folder:

```
World of Warcraft/_classic_beta_/Interface/AddOns/Aggreao/
```

## Development

Layout, like [Completao!!](../Completao): `Aggreao.lua` (entry point),
`Localization/`, `Modules/`, a `*.test.lua` next to every module, `test/` (game API
mock and a local test runner) and `setupTests.lua`.

```
lua test/busted.lua                 # tests, no busted install needed (Lua 5.1+)
busted -p ".test.lua" .             # tests with busted (what CI runs, Lua 5.1)
luacheck Aggreao.lua Localization Modules test setupTests.lua
```

CI (`.github/workflows/ci.yml`) runs luacheck and busted on every push and pull
request.

## Release

`Release to CurseForge` (`.github/workflows/release.yml`, run by hand from the
Actions tab) packages the repo with [BigWigsMods/packager](https://github.com/BigWigsMods/packager)
as the `Aggreao` folder (`.pkgmeta`) and uploads it to CurseForge using the
`X-Curse-Project-ID` in the TOC. Needs the `CF_API_KEY` repository secret.

### Description images

Screenshots in `images/screencaps/*.png` are resized, optimized and rsynced by
`.github/workflows/sync-media.yml` (on push to `master` touching that folder, or
by hand) to `https://media.joanvilarino.online/aggreao/images/screencaps/`;
`CURSEFORGE_DESCRIPTION.md` references them by that URL. Needs the
`AGGREAO_MEDIA_SSH_KEY` repository secret.

## License

GPL-3.0, see `LICENSE`.
