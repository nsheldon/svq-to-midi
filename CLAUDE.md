# SVQ to MIDI

macOS app (SwiftUI, macOS 13+) that converts Roland sequencer `.SVQ` files from the XP-50/60/80,
Fantom-S and Fantom-X6/X7/X8 to Standard MIDI Files, adding each Part's patch selection from the
Performance saved in the song. Intended for possible sale or distribution.

- `SVQKit/` — Swift package with all format logic (no UI) + `svq2mid` CLI + tests. Do format work here.
- `SVQ to MIDI/` — SwiftUI app (file-system-synchronized group; new files are picked up automatically).
- `SVQ to MIDI.xcodeproj` — hand-written pbxproj (objectVersion 77) referencing SVQKit as a local package.
- `docs/SVQ-Format.md` — the reverse-engineered format. **Keep it updated** when decoding changes.
- `Design/` — `IconArt.swift` draws the app icon (Icon Composer `AppIcon.icon` layers) and About
  banner from a coordinate tracing of `Reference Material/Roland MC-80 top.jpg`; concepts in
  `Design/Icon Concepts`; `Design/install-icon.sh "<concept>"` installs one (currently Platinum).
  Never draw Roland's logo or "MC-80" lettering (trademarks; the app may be sold).

## UI

- Detail pane: header (title, Convert, a status line under Convert whose height is always
  reserved so "Show in Finder" appearing doesn't move anything), then a segmented tab bar:
  Song Setup (stats + Performance table), Phrase Tracks, Pattern Tracks (`TracksView.swift`).
  The tab is `@AppStorage("detailTab")`. `--args -detailTab "Phrase Tracks"` opens on a tab but
  also pins it (the argument domain wins over saved values), so clicking tabs then does nothing.
- Drag out (`MIDIDrag.swift`, `AppModel.dragFile`): sidebar songs (one file per selected song),
  any Part row (all drag the song's setup, `setupMIDIData`), phrase tracks, patterns. The Tempo and
  Beat rows don't drag (alone they import as nothing in Logic; every track's file includes them). Recipe from V-Synth Patch Composer (see its CLAUDE.md,
  "Dragging buffers out as a MIDI file"): per-row `.draggable` with a `FileRepresentation`, file
  in its own temp folder, `.suggestedFileName` without extension (arrives as `.midi`), rows need
  `.contentShape(Rectangle())`. Don't switch List rows to `.onDrag`/drag containers (they broke
  List selection on macOS 26); `.onDrag` + `NSItemProvider` is only the macOS 13 fallback
  (`.suggestedFileName(closure)` is macOS 14+). The Part table branches on `#available` around the
  whole Table (an availability check inside the rows builder doesn't compile): `TableRow.draggable`
  on 14+, `TableRow.itemProvider` on 13. The phrase/pattern track lists are Tables too (resizable
  columns, user's request 2026-11-08): `if row.isDraggable { TableRow(row).draggable(…) } else
  { TableRow(row) }` compiles in the rows builder on 14+; on 13 the item provider returns nil for
  Tempo/Beat. Checked by scripted drags: Track row → Finder file, Tempo row → nothing. Confirmed by the user and by
  scripted drags (2026-11-07): sidebar, Part row, phrase track and pattern to the Finder and Logic.
  Logic asks "Also import tempo information?" on a drop; answer No in tests.
- The window's file drop ignores non-SVQ files, so a MIDI file dragged onto the app's own
  window isn't added.

## Commands

The active developer dir is Command Line Tools, which lacks XCTest, so prefix with Xcode's:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd SVQKit && swift test                          # format/converter tests
swift run svq2mid --info <file.svq | folder>     # inspect songs and Performance parts
swift run svq2mid -o <outdir> <files/folders>    # batch convert
xcodebuild -project "SVQ to MIDI.xcodeproj" -scheme "SVQ to MIDI" -configuration Debug -derivedDataPath <scratch>/dd build
NOTARY_PROFILE=<name> Tools/release/make-dmg.sh   # signed, notarized DMG in build/release (clean tree only)
```

`.venv-re/` (git-ignored) is a Python environment with the Capstone disassembler (5.x includes
SuperH): `python3 -m venv .venv-re && .venv-re/bin/pip install capstone`, then
`capstone.Cs(capstone.CS_ARCH_SH, capstone.CS_MODE_BIG_ENDIAN | capstone.CS_MODE_SH4)` for the
Fantom firmware (SH-4 big-endian; unpacking recipes in docs/SVQ-Format.md). Not used yet.

Version: `MARKETING_VERSION` (1.0) and `CURRENT_PROJECT_VERSION` (build) in the pbxproj, and the beta
label `SVQReleaseLabel` in `SVQ to MIDI/Info.plist` ("beta 2"; shown in About, used by make-dmg.sh).
Beta 1 = build 3 (tag v1.0-beta.1); beta 2 = build 4.

Releases go on GitHub (`origin` = github.com/nsheldon/svq-to-midi, `gh` is signed in) as
pre-releases while in beta; commits use the noreply email set in the repo's git config.

This Mac runs macOS 26: legacy `.appiconset` icons get shrunk into a gray container, so the icon
must stay an Icon Composer `.icon`. `NSWorkspace.icon(forFile:)` caches by path — copy the app to a
new path to see a changed icon.

UI automation is allowed (Terminal has Accessibility, Screen Recording and Automation): post
CGEvents for clicks and drags (drag: mouse down, 0.3 s, ~40 dragged steps, hold 1 s at the target,
then up). The screen is 3840×2160 at 1:1 points. Debug builds open the About window at launch
with `open -a <app> --args -ShowAboutOnLaunch YES`. To check the UI, launch with
`open -a <app> file.svq` and capture the window with `screencapture -l<windowID>` (get the ID
from `CGWindowListCopyWindowInfo`). Wait ~5 s after launch or the capture is a placeholder.

## Website

The promotional page and its upload script are kept out of the repository (git-ignored); how
they work and how to update them is in `CLAUDE.local.md`.

## Reference material (user's files)

- The owner's songs, MIDI exports, manuals and backup folders are listed in `CLAUDE.local.md`
  (personal paths; git-ignored, not published).
- SR-JV80 board names: `Reference Material/SR-JV80 Lists` (sources + `gen_boards.py` →
  `SRJV80Boards.swift`, never hand-edit). All 19 boards + 97/98/99 Experience. 06 Dance is a hand
  transcription (`dance06.txt`); 97/98/99 from synthmania ("*" is part of those names).
- SRX board names: `Reference Material/SRX Lists` (`parse_srx.py` + `parse_jp.py` → `gen_srx.py` →
  `SRXBoards.swift`, never hand-edit). Owner's manuals (Fantom-series list) for 01-12/98, Roland
  Japan's SRXINSTLIST.zip for 99 (LSB 105) and exact spacing; 97 bank only (LSB 97, 12 patches);
  96 unknown. The user's SRX-02/SRX-11 user patches (an XV-5080 Performance dump and a FANS.SVD backup) use SRX waves only;
  no song selects an SRX patch.
- Test fixtures in `SVQKit/Tests/SVQKitTests/Fixtures` are the user's own songs; remove before
  publishing the source if they should stay private.

## Format essentials (details in docs/SVQ-Format.md)

- XP: `SV00`, 96 PPQ, 8-byte records `[step u8][type][ch][track][4 data]`; Performance in `SVD0`/`PRFa`,
  bit-packed **LSB-first**; XP-80 bank depends on patch group + expansion **slot** (user-assigned).
- Fantom-X: `SV03` (model "MC-80 1.1.1"), 480 PPQ; Fantom-S identical (model "MC-80 1.2"; Roland's
  demo songs = fixtures `Fantom-S/FS-DEMO-0…4`, extracted from the Fantom-S 1.09 update's `fans.bin`,
  which `.gitignore` keeps out; STPa 32 bytes = `FantomPerformance.isFantomS`, extra `MSEa` block;
  format labeled "Fantom-S/X", setup "Fantom-S" or "Fantom-X"; Fantom-S map/names compared in
  `Reference Material/Fantom-S Lists/FINDINGS.md`: same model ID and addresses, Setup 46 params/47 B
  and Controller 85/86 B = prefixes of the X's (`fantomSSetupCount`/`fantomSControllerCount`, from
  gen_perf_layout.py), own names `FantomSPatchNames.swift` (gen_fantom_s.py; PR-A..E, S88 PR-F ×8,
  32 PRST)), 12-byte records `[step u16][type][ch][track][7 data]`,
  32-bit gate; `SVD1` blocks bit-packed **MSB-first**; Parts at bit 3186, 288 bits each, store
  bank/PC directly. `PATa`/`RHYa` records 1-16 = Parts, 17-18 = Patch-mode keyboard/pad.
  `STPa` holds Sound Mode (Patch-mode songs use keyboard/pad sounds on ch 1/10, the Fantom-X
  defaults, confirmed by the user; the actual channels are system settings not saved in the song).
- Fantom-X `PATa` records are full Patches: SysEx map order and widths, MSB-first, sections
  byte-aligned, +1 byte before Tone 1, 64-centered params stored re-centered (`FantomPatch`,
  `FantomPatchLayout.swift`). Verified byte-for-byte against two Fantom-X Patch dumps (fixtures `FX-PATCH-1/2.MID`).
  `RHYa` rhythm sets decode with the same rules (unverified — no dump; plausibility-checked).
  The SysEx option sends every Part's saved sound + Patch-mode kbd/pad on a SysEx-only setup
  track (user solos it once, then mutes it); song timing is never shifted (user's request; the
  lead-in is only the explicit option). Channel setup (MSB, LSB, PC, CC7/10/91/93) is on each
  channel's first music track (DAWs like Logic give a track one channel), all at tick 0 in that
  order ahead of the track's own tick-0 events (user's choice 2026-11-07: one tick apart let tick-0
  notes sound before the PC; Logic imports MSB/LSB+PC as one Program event listed before a same-
  position note). Fantom Parts with a dumped sound get no Bank/PC; setup skips anything the song
  itself sends at tick 0.
  Performance Common/MFX×3/Chorus/Reverb/MIDI/Zone/Controller: layout mapped (docs, inferred, no
  dump to verify; `prf_*.mid` in the SNG folder are dump *requests*). The setup track sends it
  (`FantomPerformance.performanceSysExMessages`, tables generated by
  `Reference Material/Fantom-X Map/gen_perf_layout.py`) before the Part sounds; marked
  unverified in code, docs and the track's text event (user's choice 2026-11-07).
  XP `SYSa`/`SYSb` = System settings, mostly mapped (docs). SysEx option sends System Common 00-0A
  (+ scale tunes if on) before the Performance (`XPSystem`); not performer prefs (user's request
  2026-11-08 to send "system setup data", narrowed to sound-shaping settings). Fantom-X sends its
  whole Setup (01 00 00 00, 52 B) first; Fantom-S its 47-B Setup; FA-76 its Setup.
  Option `addControllerSetup` (default off, user's choice 2026-11-08): XP System prefs 0B-51 and
  52-5F (`XPSystem.controllerSysExMessages`), Fantom-S/X and FA-76 Performance Zones + Controller.
- Tempo: `83` numerator / `84` denominator, µs/qn = round(num × PPQ × 1e6 / 24000 / den).
- `87` = pattern call (expanded into the song); `89`…`8E` = pattern bodies after the song.
  Pattern ID = 256 − pattern number (IDs skip for empty patterns). Pattern names: table after the
  event data. Header after the Output bytes: u16-length chunks (Loop, then RPS key assignments).
  Fantom header 0x0C-0x0F = song length (min, sec, frames), checked on all 13 songs.
  Header mask A = probably track PLAY/MUTE (`SVQFile.mutedTracks`): **unconfirmed** (only
  XP song 6 differs, on empty tracks); the app shows mutes but never applies them (user's choice).
- `SV02` = original Fantom FA-76 and MC-80: SV03's header and 12-byte records, the XP's u16 trailer;
  FA-76 saves `SVD1`/`NEXY` STPa (12 B), PRFa (1126 B), MLTa (954 B), no Patches; MC-80 none.
  `FA76Setup`: Sound Mode (0 PERF, 1 PATCH, 2 MULTI…), Parts at bit 3026 × 288 in PRFa and MLTa
  (found from the firmware's preset records). SysEx option: Sound Mode DT1 + temp Multitimbre
  (19 00 xx 00) or Performance (10 00 xx 00), model 00 10, sections byte-aligned (`FA76Layout.swift`
  from gen_fa76_layout.py), Decay Time Offset sent as 64 (its slot holds something else); unverified; names `FA76Names.swift` from
  `Reference Material/Fantom Lists` (parse_fantom.py → gen_fantom.py; FANTOM_MI.pdf text in dl/). Fixtures `Fantom/FA-DEMO-1` (Fantom Medley), `MC80-DEMO-1`, `FA-NEW-SONG`, from
  the FA-76 1.20 firmware (`Reference Material/Fantomv120smf`: SysEx 7-in-8 packing, MIGT4 blocks,
  zlib). Fantom-S firmware (`FantomSv109/…/fans.bin`): LZSS, ring start 0xE2F. Both git-ignored.
  Other versions: record layout picked by `SVQFile.layoutFit`, warning shown, Performance decoded
  only for `XP*`/`FANS` block models (`formatVersion`, `isKnownFormatVersion`, `formatDescription`).
- Fantom-X OS 1.0x and 2.x songs: same format (model string, blocks, sizes; checked 2026-11-08,
  docs "Fantom-X system versions"). 2.x adds PR-I/USAM/CSAM sounds and audio tracks in a sibling
  `.SVA` file (`SThd` + 8 `STrk`; not read).
- Header has 16 per-track Output bytes: bit 7 = internal, bit 0 = MIDI Out (`81` BOTH default).

## Verification standard

Decoding must reproduce the instruments' own MIDI exports exactly (tests compare event
multisets, including release velocity). Fantom stored patch names are cross-checked against the
Sound List. When something is inferred rather than verified, say so in docs/README "Known limits".

## Conventions

- `SVQConversionOptions` is persisted as JSON by the app; it has a tolerant `init(from:)` —
  add every new option there with a default so saved settings survive upgrades.
- Generated name tables (`XPPatchNames.swift`, `FantomPatchNames.swift`) came from the PDFs via
  `pdftotext -layout`; regenerate rather than hand-edit large sections. Known Roland typo fixed:
  GM2 "Elec Perc" is LSB 2.
- Git repo (branch `main`). `.gitignore` keeps out copyrighted material (Roland PDFs/HTML, the MC-80
  photo) and the user's own songs used as test fixtures — never commit those.
