# Vendored fonts

`inter-latin-wght.woff2`: Inter variable font, latin subset only (weights 100 to 900 in one file). Google Fonts path version v20; the font's own version is 4.001.

- Source: `https://fonts.gstatic.com/s/inter/v20/UcC73FwrK3iLTeHuS_nVMrMxCp50SjIa1ZL7.woff2`
- Licence: SIL Open Font License 1.1, copyright The Inter Project Authors; the full notice travels with the font in `LICENSE.txt`.
- sha256: `3100e775e8616cd2611beecfa23a4263d7037586789b43f035236a2e6fbd4c62` (48,256 bytes)
- Regenerate: download the URL above and compare the sha256.
- Loaded by `app/fonts.ts` through `next/font/local`; `test/no-network-fonts.test.ts` forbids the network font loader.
- Non-latin glyphs fall back to the system font stack. The previous config was latin-only too, so nothing changed.
- `plugins/soleur/docs/fonts/inter.woff2` is the same file for the docs site; the two are separate sub-projects (different Docker/build contexts) and bump independently.
- Frozen asset, no scheduled refresh: a later Inter version changes nothing the app needs.
