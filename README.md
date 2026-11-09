# SVQ to MIDI

A macOS app that converts Roland XP-50, XP-60, XP-80, Fantom (FA-76), Fantom-S, Fantom-X6/X7/X8
and MC-80 sequencer songs (`.SVQ` files) to Standard MIDI Files. It also reads the Performance saved with each song and
adds Bank Select and Program Change messages, so every Part gets the patch it used on the
instrument. It can also add the instrument's setup as System Exclusive: the XP-80 Performance, or
every Fantom-S/X Part's complete saved Patch or Rhythm Set.

## Features

- Converts all 16 tracks: notes (including release velocity), controllers, program changes,
  aftertouch, pitch bend, and SysEx recorded in the song, plus tempo, tempo changes, meter and key.
- Expands pattern calls, so tracks built from patterns play as they did on the instrument.
- Handles Fantom-X songs saved in Patch mode by selecting the keyboard Patch and pad sound
  instead of the Performance.
- Reads each track's Output setting (internal, MIDI Out, both, off). Tracks that played an
  external instrument through MIDI Out are labeled and don't get the instrument's Part setup. Tracks
  set to Off are included by default (labeled "Off") and can be left out.
- Shows each song's Performance: every Part's channel, patch name, Bank Select/Program, level,
  pan and effect sends. XP Preset, GM and Rhythm Set names come from the XP-80 manual, and
  SR-JV80 expansion-board patch and rhythm set names for all 19 boards plus the three
  Experience demo boards (97, 98, 99) (see `Reference Material/SR-JV80 Lists`). Fantom-X
  files store each Part's patch with the song, so even user patch names are shown; GM2 names
  come from the Fantom-X Sound List, and SRX expansion-board names (SRX-01 to SRX-12, SRX-98 and
  SRX-99) from Roland's lists (see `Reference Material/SRX Lists`).
- Adds the following at the start of the MIDI file (each can be turned off):
  - Bank Select MSB/LSB and Program Change for every channel the song plays
  - Part level (CC 7), pan (CC 10), reverb send (CC 91) and chorus send (CC 93)

  These go at the very start of the first track that plays each channel, in order (MSB, LSB,
  Program Change, then the mixer) and ahead of that track's first notes, so the first notes
  already play the right sound. Each channel's setup is on its own track, so a DAW keeps the
  order (Logic Pro imports it as one Program event with its Bank Select, ahead of the notes). A
  controller or Program Change the song itself sends at the start is left to the song.
  - The setup as SysEx, on a separate "Setup SysEx" track so the song keeps its original timing
    and measure count. XP songs: the saved System settings that shape the sound (Sound Mode,
    selected Performance, Master Tune, scale tunes, effect switches), then the Performance (Common
    plus 16 Parts), byte-identical to what the XP-80 transmits. Fantom songs start with their
    saved Setup (Sound Mode and selections). Fantom-X songs: every Part's saved Patch or Rhythm Set, plus Patch mode's
    keyboard and pad sounds, sent after the Bank Select/Program Change so the song plays with
    exactly the sounds it was saved with, including user patches and unsaved edits. Solo the
    setup track and play it through once, then mute it and play the song. Fantom-X Parts whose
    sound is sent this way get no Program Change, which would replace it on later plays. For
    Fantom-X songs saved in Performance mode, the Performance itself (effects, Part, zone and
    controller settings) is sent first; this part is unverified (see Known limits).
  - Optionally, the player's controller and keyboard settings saved with the song: the XP's
    System preferences (receive switches, control channel, pedal and controller assignments,
    keyboard, arpeggio) and the Fantom Performances' keyboard Zones and Controller section. Off by
    default, since some of them (such as receive switches) can stop the song's own setup working.
  - Optional empty lead-in measures before the song
- Lets you assign XP SR-JV80 Wave Expansion boards to slots A-D, which determines their Bank Select.
- Saves patterns (XP RPS phrases, Fantom-X patterns) as separate MIDI files, named with the
  pattern's number and name, and shows each pattern's RPS key assignment.
- Converts in batches: drop files or whole folders on the window, or open `.svq` files from the Finder.
- Shows each song in three tabs: **Song Setup** (song details and the Performance), **Phrase
  Tracks** (the Tempo and Beat tracks plus each phrase track's output, channels, sound, notes,
  key range, measures and other events, and the patterns it plays) and **Pattern Tracks** (each
  pattern's length, contents and the tracks that play it).
- Drag and drop to the Finder or a DAW such as Logic Pro, using the current options:
  - a song in the sidebar, for the whole song (several selected songs give one file each);
  - any Part in the Song Setup list, for the setup alone: the setup SysEx track, then one track
    per channel with its Bank Select, Program Change and mixer settings (every Part drags the
    same file);
  - a phrase track, with the song's tempo, meter and key and its channel setup (no setup SysEx);
  - a pattern.

  Dropped files end in `.midi` (the receiving app adds the extension for the MIDI type).

## Project layout

| Path | Contents |
|---|---|
| `SVQ to MIDI.xcodeproj` | The Xcode project for the app |
| `SVQ to MIDI/` | SwiftUI app sources, Info.plist, entitlements, assets |
| `SVQKit/` | Swift package that does the decoding and conversion (no UI), with unit tests |
| `SVQKit/Sources/svq2mid/` | Command-line converter built from the same package |
| `docs/SVQ-Format.md` | The reverse-engineered SVQ file format |
| `Design/` | Icon and About-art generator (`IconArt.swift`), the four concepts, and `install-icon.sh` |
| `Reference Material/` | Sources and generator scripts for the patch-name tables and the Fantom-X parameter map (the Roland documents themselves aren't included) |

## Building

Open `SVQ to MIDI.xcodeproj` in Xcode and run the **SVQ to MIDI** scheme. The app requires
macOS 13 or later.

To run the format tests and the command-line tool:

```sh
cd SVQKit
swift test
swift run svq2mid --info ~/path/to/SONG.SVQ
swift run svq2mid -o ~/Desktop/MIDI ~/path/to/SVQs        # converts a whole folder
swift run svq2mid --sysex --slot 9=A ~/path/to/SONG.SVQ    # adds SysEx, board 09 in slot A
swift run svq2mid --no-off-tracks ~/path/to/SONG.SVQ       # leaves out tracks set to Off
```

If `swift test` reports that XCTest is missing, the command-line tools are selected instead of
Xcode. Run `sudo xcode-select -s /Applications/Xcode.app` or prefix the command with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

The tests compare the decoder against MIDI files the XP-80 and Fantom-X exported from the
same songs. Those are the author's own songs, so they're kept out of the repository (see
`SVQKit/Tests/SVQKitTests/Fixtures/README.md`); without them the fixture-based tests are skipped.

Third-party reference documents (Roland's manuals and patch listings, and the MC-80 photo the
icon is traced from) are also kept out of the repository; `Reference Material/SR-JV80 Lists/README.md`
lists where they came from.

## Distribution checklist

- `Tools/release/make-dmg.sh` builds the downloadable copy: Developer ID signed, notarized and
  stapled, in a DMG with the license and an Applications link. Run it with `check` first; it
  needs a Developer ID Application certificate and a `notarytool` login (`NOTARY_PROFILE`).
- In **Signing & Capabilities**, choose your team. The project is set to sign locally
  ("Sign to Run Locally") until you do.
- The app is sandboxed and uses only user-selected file access. Hardened Runtime is on, so it
  can be notarized for distribution outside the Mac App Store, or submitted to the App Store.
- The app icon is an Icon Composer file (`SVQ to MIDI/AppIcon.icon`) generated from
  `Design/IconArt.swift`. Four 1990s-style concepts (Platinum, Neon Grid, Memphis, Dot Matrix)
  are in `Design/Icon Concepts`, with `preview-macOS.png` showing how macOS renders each one.
  Switch with `Design/install-icon.sh "<concept>"`. Platinum is installed. The artwork traces the
  MC-80's shape and layout but omits Roland's logo and model lettering, and the About window
  carries a trademark notice.
- The bundle identifier is `com.nathansheldon.SVQtoMIDI`. Change it if needed.

## License and notices

SVQ to MIDI is released under the [MIT License](LICENSE). It is provided as is, without
warranty of any kind.

**Not affiliated with Roland.** Roland, MC-80, XP-50, XP-60, XP-80 and Fantom are trademarks of
Roland Corporation. SVQ to MIDI is an independent project; it is not affiliated with, sponsored
or endorsed by Roland Corporation, and Roland's names are used only to say which instruments and
files it works with.

**Roland data.** To name sounds and generate SysEx, the app includes data taken from Roland's
published documentation: the XP-80 and Fantom-X preset, GM and Rhythm Set names; the SR-JV80
and SRX expansion-board patch and rhythm set names; and the parameter layouts from the
instruments' MIDI Implementation charts. These names and specifications are Roland's and are
included only for compatibility with Roland's own files and instruments; the MIT License covers
this project's own code and documentation, not Roland's material. A few board lists come from
other public transcriptions (see `Reference Material/SR-JV80 Lists/README.md` and
`Reference Material/SRX Lists/README.md` for every source). The `.SVQ` format was worked out
independently, by comparing files with the MIDI the instruments themselves exported, for
interoperability; no Roland software or firmware was decompiled.

The app icon and About artwork are original drawings of a hardware sequencer's general shape and
layout; they don't reproduce Roland's logo or model lettering.

## Known limits

- Tested with XP-80 files (`SV00`, `XP-80 0105 1.7`) and Fantom-X files (`SV03`,
  `MC-80      1.1.1`) against the instruments' own MIDI exports. Fantom-S songs (`SV03`,
  `MC-80      1.2`) use the same format and data blocks: Roland's five Fantom-S demo songs (from
  the Fantom-S 1.09 system update) decode completely, but no Fantom-S MIDI export was available to
  compare them with. Fantom-S songs get the Fantom-S's own sound names and Setup and Controller
  sizes, from its Sound List and Parameter List. Other Roland sequencers that write `.SVQ` files may differ: MC-80 files will
  probably work, while files from the original Fantom (FA-76), MC-50mkII and JV-1000 are
  untested. The original Fantom (FA-76) and the MC-80 write `SV02`, worked out from three `SV02`
  songs inside the Fantom's own firmware. Their song data converts, and the original Fantom's
  saved Multitimbre or Performance gives each Part's sound (named from the Fantom's Patch and
  Rhythm Set Lists), Bank Select, Program Change and mix; but no MIDI export of an `SV02` song was
  available to compare with, and the layout comes from the firmware's presets and one song. The
  SysEx option sends the original Fantom's saved Multitimbre or Performance (after its Sound
  Mode); it's unverified (no Fantom dump was available), and each Part's Decay Time Offset is sent
  as 64 because its slot in the file holds something else. The MC-80 saves no sound settings (its
  sounds came from a VE-GS board). Sample files from these instruments would help.
- Fantom-X Patch SysEx is verified byte-for-byte against Fantom-X Patch dumps. Rhythm Set SysEx
  uses the same rules and decodes plausibly (all names readable, all values in range), but no
  Rhythm Set dump was available to verify it. The Fantom-X Performance (Common, three MFX,
  chorus, reverb, Parts, zones, controller) is sent too, but its layout is inferred from the
  manual and checked only for plausibility across 87 saved Performances: no Fantom-X
  Performance dump was available. Capturing the instrument's reply to `prf_all_.mid` would
  verify it.
- Tracks that were probably muted when the song was saved are shown with a muted speaker, but
  still converted. This reading of the file is unconfirmed (no sample mutes a track with data).
- A full Fantom-X setup is about 385 SysEx messages and takes roughly 27 seconds to send. The setup
  track overlaps the start of the song, so it has to be played on its own (soloed) the first time;
  a song shorter than its setup is lengthened to fit it.
- Fantom-X pattern calls were checked against the pattern data but not against a Fantom-X MIDI
  export, because none of the sample songs that use them had one. XP pattern calls are assumed
  to use the same record, since none of the sample XP songs contain one. The XP-80 manual
  confirms phrase tracks can hold Pattern Call messages; one XP song with six patterns
  holds copies of four of them in its tracks rather than calls.
- The RPS key assignments shown in Pattern Tracks (pattern, playback mode, mute group) are read
  from one XP and one Fantom-X song. The playback-mode and mute-group values follow the manual's
  order and fit those songs, but haven't been checked on an instrument. Pattern numbers (which
  can skip, as on the instrument) and pattern names are consistent across every sample.
- The meaning of the track Output bits comes from one Fantom-X song plus the defaults in
  all the others; it's consistent with everything in that song, but no other sample changes it.
- Fantom-X audio tracks (system 2.x, the Audio Track Expansion) are saved in a separate `.SVA`
  file beside the song, which isn't read: audio has no MIDI equivalent (the app notes when a song
  has one). Songs saved by Fantom-X
  system 1.0x and 2.x are otherwise the same format.
- For Fantom-S/X songs saved in Patch mode, the keyboard and pad receive channels are system
  settings that aren't in the file, so the Fantom-X defaults (1 and 10) are used. A song made
  on a Fantom-X whose system channels were changed would need those channels instead.
- A few SR-JV80 names come from scans or transcriptions rather than exact text: the Dance board
  (hand-transcribed from a manual scan) and the Experience boards (synthmania.com). Every name
  that could be checked against an XP-80 dump or an independent source matches.
- SRX names come from Roland's documents but haven't been checked against a song, since none of
  the sample songs selects an SRX patch. SRX-97's patches are shown by number only (no list could
  be found), and SRX-96 isn't recognized (no list or Bank Select found). Some early SRX boards
  may show "Rhodes" where Roland's revised lists say "EP"; a song shows its own saved name anyway.
- Bank Select for PCM card patches (MSB 83) comes from JV-series documentation and hasn't
  been checked on an XP-80. None of the sample songs use a PCM card.
- The XP's `SYSa`/`SYSb` blocks (the System settings saved with a song) are mostly decoded; the
  SysEx option sends the ones that shape the sound (Sound Mode, selected Performance, Master Tune,
  scale tunes, effect switches), not the player's preferences. The System Common settings, pedals and scale
  tunes are mapped from the manual's parameter list (checked for consistency across 75 copies;
  no System dump was available to verify them byte for byte), and the arpeggio settings are
  inferred. A 10-bit setting and a 26-byte tail at the end are still unidentified (probably
  settings with no SysEx address, such as LCD contrast, Device ID or the sequencer's quantize
  settings). See `docs/SVQ-Format.md`.
- Dragging has been tested with the Finder and Logic Pro on macOS 26. On macOS 13 the app falls
  back to an older drag method, which hasn't been tried.
