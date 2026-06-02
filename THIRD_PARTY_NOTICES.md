# Third-Party Notices

This file records third-party software, assets, and reference materials used by
TravelPin. It separates third-party rights from the proprietary repository
license declared in [LICENSE](LICENSE).

Status note:

- This is an initial draft created from files and documentation currently
  present in the repository on 2026-06-02.
- Entries marked `Needs verification` require the team to confirm the original
  source page, license text, or redistribution terms before release.

## Software Dependencies

### AppGallery Connect and HarmonyOS OHPM Packages

Component: Huawei AppGallery Connect and HarmonyOS OHPM dependencies
Source: OHPM registry entries recorded in `frontend/oh-package-lock.json5` and
`frontend/entry/oh-package-lock.json5`
Version:
- `@hw-agconnect/auth` `1.0.5`
- `@hw-agconnect/auth-component` `1.0.1`
- `@hw-agconnect/cloud` `1.0.2`
- `@hw-agconnect/hmcore` `1.0.5`
- `@ohos/hypium` `1.0.24`
- `@ohos/hamock` `1.0.0`
- transitive packages including `protobufjs`, `long`, `bignumber.js`,
  `@protobufjs/*`, and `@types/node` as resolved in lockfiles
License: Needs verification from upstream package pages / Huawei SDK terms
Used In:
- runtime auth and cloud features in the HarmonyOS app
- unit test tooling for `hypium` and `hamock`
Redistributed In Repo: Lockfiles only
Packaged In App: Yes for runtime packages; No for test-only packages
License Text Location:
- `frontend/oh-package-lock.json5`
- `frontend/entry/oh-package-lock.json5`
Notes:
- The repository contains version and registry metadata, but not complete
  license texts for these OHPM packages.
- Verify Huawei SDK redistribution and attribution requirements before release.

### dependency-cruiser

Component: `dependency-cruiser`
Source: npm
Version: `17.3.10`
License: `MIT`
Used In: architecture analysis and dependency graph tooling
Redistributed In Repo: package manifest and lockfile only
Packaged In App: No
License Text Location:
- `package.json`
- `package-lock.json`
- local installed metadata observed in `node_modules/dependency-cruiser/package.json`
Notes:
- Development-only dependency; not part of the shipped HarmonyOS app package.

## Reference Demo Materials

### HarmonyOS Official Sample References

Component: README notes under `references/demos/`
Source: `https://gitee.com/harmonyos-cases/cases`
Version: not pinned in this repository
License: Needs verification from the upstream `harmonyos-cases/cases` repository
Used In: internal study and implementation reference only
Redistributed In Repo: Yes
Packaged In App: No
Files:
- `references/demos/addressrecognize/README.md`
- `references/demos/API/README.md`
- `references/demos/foldablescreencases/README.md`
- `references/demos/operaterdbintaskpool/README.md`
- `references/demos/photopickandsave/README.md`
- `references/demos/sharebutton/README.md`
Notes:
- Current repo copies README-style reference notes, not the full upstream demo
  projects.
- Confirm whether attribution text from the upstream repository is required.

## Audio Assets

### Replay BGM Files Bundled in the App

Component: replay background music files under
`frontend/entry/src/main/resources/rawfile/`
Source: Mixed; some filenames suggest third-party music libraries
Version: not applicable
License: Needs verification per file
Used In: replay feature background music
Redistributed In Repo: Yes
Packaged In App: Yes
Files:
- `frontend/entry/src/main/resources/rawfile/lofidreams-city-lights-chill-lofi-365944.mp3`
- `frontend/entry/src/main/resources/rawfile/vibedepot-jazz-night-419811.mp3`
- `frontend/entry/src/main/resources/rawfile/jaystacksbeats-travel-vlog-_-tropical-chill-002-451749.mp3`
- `frontend/entry/src/main/resources/rawfile/sigmaeffect-cinematic-ambient-atmosphere-463222.mp3`
- `frontend/entry/src/main/resources/rawfile/welc0mei0-180126-ambient-morning-chill-with-birds-21348.mp3`
- `frontend/entry/src/main/resources/rawfile/South-East-Traveling.mp3`
License Text Location:
- `documents/features/replay/assets/music-attribution.md`
- `frontend/entry/src/main/ets/common/replay/ReplayMusicCatalog.ets`
Notes:
- `ReplayMusicCatalog.ets` records authors for five tracks:
  `welc0mei0`, `lofidreams`, `vibedepot`, `jaystacksbeats`, and `sigmaeffect`.
- Repository docs recommend tracking replay music provenance in
  `documents/features/replay/assets/music-attribution.md`, but that file still
  contains only a template.
- `South-East-Traveling.mp3` also exists at
  `references/media/music/South-East-Traveling.mp3`; source and license are not
  documented in the repo and must be verified before release.
- File naming suggests some tracks may originate from Pixabay Music, but the
  exact source URLs are not yet recorded in this repository.

## Image Assets

### Unsplash-Named Reference Photos

Component: reference photos under `references/media/photos/` with `-unsplash`
in the filename
Source: likely Unsplash, based on filenames
Version: not applicable
License: Needs verification from each original source page
Used In: repository documentation, design reference, and mock visual material
Redistributed In Repo: Yes
Packaged In App: No unless copied elsewhere
Files:
- `references/media/photos/darmau-5-k1_mBljB0-unsplash.jpg`
- `references/media/photos/darmau-BYPHnneWj3M-unsplash.jpg`
- `references/media/photos/darmau-RjSf0IZOyiM-unsplash.jpg`
- `references/media/photos/darmau-TW5bZE4fkPw-unsplash.jpg`
- `references/media/photos/darmau-W2X8IJyI_LU-unsplash.jpg`
- `references/media/photos/dl314-lin-VlfrM9BSDPM-unsplash.jpg`
- `references/media/photos/joshua-fernandez-dJ1TGyNr5I0-unsplash.jpg`
- `references/media/photos/oskar-kadaksoo-FCtxHTGLId8-unsplash.jpg`
- `references/media/photos/ricardo-wu-4oXGOWjUIzA-unsplash.jpg`
- `references/media/photos/robert-bye-xQdUIo_MSQ4-unsplash.jpg`
- `references/media/photos/vincent-chan-04Kmj0pru5M-unsplash.jpg`
- `references/media/photos/vincent-lin-6YS2inATv3E-unsplash.jpg`
- `references/media/photos/vincent-lin-QuNvb14G6mo-unsplash.jpg`
- `references/media/photos/weichao-deng-Ghx11XtiiR4-unsplash.jpg`
Notes:
- Photographer names are embedded in filenames, but the original image URLs and
  exact license terms are not stored in the repository.
- Verify whether these files remain documentation-only or are reused in the app.

### App-Packaged Media with Unverified Provenance

Component: media files under `frontend/entry/src/main/resources/base/media/`
Source: mixed; likely team-created and project-specific, but provenance is not
fully documented in the repository
Version: not applicable
License: internal or third-party status needs verification
Used In: packaged HarmonyOS app resources
Redistributed In Repo: Yes
Packaged In App: Yes
Files:
- `background.png`
- `foreground.png`
- `search_destination_marker.png`
- `startIcon.png`
- `photo_1.jpg`
- `photo_2.jpg`
- `photo_3.jpg`
- `photo_4.jpg`
- `photo_5.jpg`
- `photo_6.jpg`
License Text Location: none currently recorded
Notes:
- If these are entirely created by the TravelPin Team, they can be removed from
  this notice file after internal confirmation.
- If any file was sourced from a stock library, icon set, or external designer,
  add a dedicated entry with the original source URL and license terms.

## Follow-Up Checklist

- Confirm upstream license / terms for Huawei OHPM packages used in the app.
- Fill `documents/features/replay/assets/music-attribution.md` with one section
  per bundled audio file and add original source URLs.
- Verify provenance of `South-East-Traveling.mp3`.
- Verify provenance of `photo_1.jpg` through `photo_6.jpg`,
  `search_destination_marker.png`, and app icon / branding assets.
- Record exact source URLs for all Unsplash-named files if they remain in the
  repository.
