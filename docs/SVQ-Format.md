# Roland SVQ sequence format (XP-50/60/80 and Fantom-S/X)

This describes the `.SVQ` song files written by the Roland XP-50, XP-60 and XP-80 sequencer
(model string `XP-80 0105 1.7`, signature `SV00`) and by the Fantom-X6/X7/X8 (model string
`MC-80      1.1.1`, signature `SV03`) and the Fantom-S (model string `MC-80      1.2`, also
`SV03`), with notes on the original Fantom's and MC-80's `SV02`. The Fantom-S/X variant is covered in its own section
at the end; everything before it describes the XP. Roland never published the format. It was
reverse-engineered by comparing SVQ files with MIDI files the XP-80 exported from the same
songs, and checking against the XP-80 Owner's Manual (MIDI Implementation chapter).

The SVQKit decoder reproduces the XP-80's own MIDI exports exactly: every note, gate, velocity,
release velocity, controller, aftertouch, SysEx message and tempo value. It also regenerates
the XP-80's Performance SysEx dump byte for byte, checksums included.

All multi-byte integers are **big-endian**.

## File layout

```
+--------------------------------------+
| u16  header length H                 |  offset 0
| header (H bytes)                     |  offsets 2 ... H+1
|   ... ends with u32 event-data length L
+--------------------------------------+
| event records (L bytes, 8 each)      |  offset H+2
+--------------------------------------+
| u16  length of the rest of the file  |
| u16 40, then 40 bytes                |  zeros in all samples; probably Locate points (below)
| u16 n, then n bytes of pattern names |  see "Pattern names"
| u16 length, "SVD0" directory         |  system and Performance data
+--------------------------------------+
```

## Header

| Offset | Size | Meaning |
|---|---|---|
| 0x00 | 2 | Header length H (the bytes that follow, up to the start of the event data) |
| 0x02 | 4 | `SV00` signature |
| 0x06 | 2 | Resolution in ticks per quarter note (96) |
| 0x08 | 8 | Flags (`00 00 00 01 00 00 00 00` on user songs, all zero on Roland's demos) |
| 0x10 | 1 | `FF` |
| 0x11 | 16 | Model and OS string, space padded, e.g. `XP-80 0105 1.7  ` |
| 0x21 | 1+n | Song name, length-prefixed (up to 16 characters) |
| … | 1+n | Comment, length-prefixed (Roland demos store a copyright notice; empty on user songs) |
| … | 8 | Track masks: `10 02`, u16 mask A, `02`, u16 mask B, then `10` (the track count, 16). Bit *n* = track *n*+1. **B** = the tracks that exist (have an End-of-Track record; matches all 30 sample songs). **A** is `FFFF` in every sample but one, XP song 6, where it holds exactly the tracks with data; it is probably the saved track mute status (the manual says mutes are saved with the song, and its Track Information page shows each track as PLAY, MUTE or EMPTY, which fits A = PLAY and B = not EMPTY), with XP song 6's empty tracks muted. Unconfirmed: no sample mutes a track that has data. The app shows such tracks as muted but still converts them |
| … | 16 | Each phrase track's **Output** setting: bit 7 = internal sound generator, bit 0 = MIDI Out (`81` BOTH, the default; `80` INT; `01` MIDI; `00` OFF) |
| … | … | Length-prefixed song settings (u16 length, data), see below |
| H−2 | 4 | Length L of the event data |

### Song settings

Each is a u16 length followed by that many bytes:

1. **Loop** (10 bytes): mode, u32 loop start tick, u32 loop end tick, repeat count. The default is
   mode 0, start 0, end 384 (one measure), repeat `FF`. XP song 5 has mode 1 with bars 9-10; XP songs 6, 2 and 4 have other points with mode 0. Inferred from the manual's Loop window
   (Loop OFF/POINT/1/2/4/8/16, Repeat INFINIT/1/2/…), which the manual says is saved with the song:
   mode 0 = OFF, 1 = POINT, and `FF` = INFINIT are likely but unconfirmed.
2. **RPS setup**: 4 bytes (`00 00 00 00` when unused; XP song 5 `01 00 00 01`, Fantom-X song 6
   `00 00 00 02`; not identified, probably the RPS switch, Trigger Quantize and Velocity Sens),
   then 3-byte entries in key order: key (MIDI note), pattern number − 1 (`FF` = STOP), Playback
   Mode (0 LOOP1, 1 LOOP2, 2 ONCE). An entry whose key has bit 7 set gives that key's Mute Group
   as a u16 instead. XP song 5: C2 STOP; D2-G2 patterns 1-4 ("Beat", "Bass", "Guitar", "MusicBox")
   LOOP2; A2 and B2 its two 2-bar fills, ONCE; and D2, A2 and B2 in Mute Group 1, so the fills
   and the beat never sound together (the manual's own example of a Mute Group). The meanings of
   the mode values follow the manual's order and fit this song; not checked on an instrument.
3. Fantom-X files have more (see the Fantom-X header).

## Event records

The event data is one time-ordered stream holding all 16 tracks, followed by any patterns.
Every record is 8 bytes:

```
byte 0  step   ticks until the NEXT record (the record itself happens at the running time)
byte 1  type   < 0x80: a note (the key number); >= 0x80: see the table
byte 2         MIDI channel (0-15) for notes and channel messages
byte 3         track (0-15) for song events; pattern ID for pattern events
bytes 4-7      data
```

Gaps longer than 255 ticks are filled with `0x80` rest records.

| Type | Meaning | Data (bytes 4-7) |
|---|---|---|
| `00`–`7F` | Note, key = type | velocity, release velocity, gate (u16 ticks) |
| `80` | Rest (only advances time) | — |
| `82` | Time signature | numerator, denominator power of 2, MIDI clocks per click, 32nds per quarter |
| `83` | Tempo numerator | u32 time units (24,000 per second) |
| `84` | Tempo denominator | u32 ticks; always follows an `83` |
| `86` | Key signature | sharps(+)/flats(−) as a signed byte, minor flag, 0, 0 |
| `88` | Size bookkeeping | u32 (event data length − 16 at the start of the song) |
| `89` | Pattern start | u32 byte length of the pattern; byte 3 = pattern ID (`FF`, `FE`, …) |
| `8E` | End of track | byte 3 = track number or pattern ID |
| `8F` | End of song | — |
| `91` | SysEx start | u32 message length (including `F0` and `F7`) |
| `92` | SysEx data | the next 4 message bytes (the last record is zero-padded) |
| `9A` | Polyphonic aftertouch | MIDI status `An`, key, value, 0 |
| `9B` | Control change | MIDI status `Bn`, controller, value, 0 |
| `9C` | Program change | MIDI status `Cn`, program, 0, 0 |
| `9D` | Channel aftertouch | MIDI status `Dn`, value, 0, 0 |
| `9E` | Pitch bend | MIDI status `En`, LSB, MSB, 0 |

`9A` was not seen in any sample file; it is inferred from the `9B`–`9E` pattern.

### Tempo

A tempo is stored as a ratio: an `83` record (time units) immediately followed by an `84`
record (ticks). At the start of a song the pair describes the whole song (for example,
150000 / 1200 at 120 BPM); gradual tempo changes are written as many short pairs. To convert:

```
microseconds per quarter note = round(numerator × resolution × 1,000,000 / 24,000 / denominator)
```

The XP-80 rounds to the nearest microsecond when it exports MIDI, which this matches.

### Patterns

After the song's End-of-Track records, the file may contain patterns (the phrases used by RPS,
Realtime Phrase Sequence). Each starts with an `89` record, has its events tagged with the
pattern ID in byte 3, and ends with an `8E` for that ID. Times within a pattern continue the
running count, so subtract the time of the `89` record. A track can play a pattern with a
pattern-call record (`87`, see the Fantom-X section); the XP-80 manual confirms a phrase track
can hold Pattern Call messages. None of the sample XP songs use calls (Roland's demos keep
patterns only for RPS, and XP song 5's tracks hold copies of its patterns), so the XP call record
is assumed to match the Fantom-X one.

**The pattern ID is the pattern number**: `FF` is pattern 1, `FE` pattern 2, … (`9C` = 100).
Patterns that are empty aren't stored, so the IDs can skip: Fantom-X song 6 has `FF`-`FC`,
`F6`, `F4`, `F3`, and its RPS setup assigns patterns 1-4, 10, 12 and 13.

### The 40-byte block

Zeros in every sample. The manual says the Locate positions are saved with the song: up to
eight (LOC1-8) plus LOC0 (Rec Top) and LOC9 (Rec End), which recording sets automatically.
Ten u32 tick positions would be exactly 40 bytes, but if so, Rec End should be non-zero in
recorded songs, so this is only a candidate.

**Groove templates aren't in the song**: the XP-80 saves user groove templates (USR:001-016)
in their own `.SVT` file. The current quantize settings (template number, timing and velocity
strength) may be among the undecoded System settings (see `SYSa`/`SYSb`).

### Pattern names

After the event data (see the file layout), a u16 length, then one entry per named pattern:
pattern ID, name length, name (up to 10 characters seen). XP song 5: "Beat", "Bass", "Guitar",
"MusicBox", "Beat Fil01", "Beat Fil02"; Fantom-X song 4 "SylkyBels", "808 A", "Seq A",
"Bass A". The same table follows the Fantom-X event data.

## "SVD0" directory

The `0x0363` block holds a small directory in the same format as Roland's `.SVD` data files:

```
u16  directory length (62)        ← offsets below are relative to this field
"SVD0", 10 bytes of zeros
entries, 16 bytes each:  4-char tag, 4-char model, u32 offset, u32 length
```

| Tag | Model | Contents |
|---|---|---|
| `SYSb` | `XP80` | System settings (see below) |
| `SYSa` | `XP80` | System settings, older layout (see below) |
| `PRFa` | `XP50` | The Performance (16-part setup) saved with the song |

Roland's demo songs have no directory; they set up the instrument with SysEx inside the song.

### PRFa: the Performance

The Performance's parameters, in the order of the System Exclusive parameter map in the
XP-80 manual (sections 1-2-1 and 1-2-2), **bit-packed least-significant-bit first**, each
using its bit width from the manual's `0aaa aaaa` notation. Two-byte "nibblized" SysEx values
(Performance Tempo, Patch Number, Transmit Volume) are a single 8-bit field.

- **Common**: 52 bytes (412 bits used). Widths: name 12 × 7, EFX source 4, EFX type 6,
  12 EFX parameters × 7, EFX output 2, 3 sends × 7, control source 4, depth 7, source 4,
  depth 7, chorus 5 × 7, chorus output 2, reverb type 3, level 7, time 7, HF damp 5,
  delay feedback 7, tempo 8, keyboard range switch 1, 16 voice reserves × 7,
  keyboard mode 1, clock source 1.
- **Parts 1-16**: 14 bytes each (107 bits used). Widths: receive switch 1, MIDI channel 4,
  patch group type 2, patch group ID 7, patch number 8, level 7, pan 7, coarse tune 7,
  fine tune 7, output assign 3, mix/EFX send 7, chorus send 7, reverb send 7, receive program
  change 1, receive volume 1, receive hold-1 1, key range lower 7, key range upper 7,
  octave shift 3, local switch 1, transmit switch 1, transmit bank select group 3,
  transmit volume 8.

### Patch groups and Bank Select

| Group type | Group ID | Group | Bank Select MSB / LSB |
|---|---|---|---|
| 0 | 1 | USER | 80 / 0 |
| 0 | 3 | PR-A | 81 / 0 |
| 0 | 4 | PR-B | 81 / 1 |
| 0 | 5 | PR-C | 81 / 2 |
| 0 | 6 | GM | 81 / 3 |
| 1 | — | PCM card | 83 / 0 (from JV-series docs; not verified on the XP-80) |
| 2 | board number | SR-JV80 Wave Expansion board | 84 / slot × 2 (+1 for patches 129-255) |

The program number is `patch number mod 128`. Part 10 holds a Rhythm Set instead of a Patch
and uses the same groups. Expansion boards are stored by board number (for example 9 for
SR-JV80-09 Session), not by slot, so the slot the board was installed in (A-D) has to be
supplied when choosing the Bank Select value.

### SYSa / SYSb: System settings

The XP-80's System settings at the time of saving, bit-packed LSB-first like `PRFa`. `SYSb`
(264 bytes) is the current layout; `SYSa` (263 bytes) is the same data without byte 0x32, and
the `SYSa`/`XP50` copy in `.SVD` files (255 bytes) also omits bytes 0x2A-0x31 (the XP-80-only
settings). These relations hold byte for byte in every sample. Roland's own XP-80 demo song
carries only `SYSa`.

- **Common** (51 bytes in `SYSb`): System Common parameters 00 00-00 51 of the SysEx map in
  order and with the map's widths (Sound Mode, Performance Number, Patch Group/Number of Patch
  mode, Master Tune, switches, control sources, receive switches, Control/Patch channels,
  Preview notes, Tx switches, Transpose, keyboard settings, Pedal 1-2, C1/C2, Hold Pedal,
  Bank Select Groups 1-7). Every value is in range in all 75 blocks seen (songs and `.SVD`
  backups), and the Performance Number matches the user Performance slot holding the song's
  `PRFa` (8 songs checked against `.SVD` backups; also matches a DT1 recorded in a song). Then
  an unidentified 10-bit setting shaped like a controller assignment (CC number 7 bits, 2 bits
  always 3, 1 bit), 9 pad bits (the end of the XP-50 portion, bit 336), Pedal 3-4 (00 52-57,
  identified by their pedal-only values such as TAP-TEMPO and PUNCH-I/O) and the Arpeggio
  settings (00 58-5F), whose Style, Motif and Beat Pattern are stored 7 bits wide rather than
  the map's 6 (with 6 bits the values fall out of range; with 7 they match the manual's style
  table). Arpeggio Octave Range and Part only fit in `SYSb`. The Arpeggio fields are inferred.
- **Scale Tune**: 17 sets (Parts 1-16, then Patch mode, order assumed from the map since every
  value is 64 in the samples) of 12 × 7-bit values, each set padded to 11 bytes.
- **Tail**: 26 bytes, not decoded. Only two variants exist in the samples (the owner's XP-80, and
  Roland's files), differing in 11 bits; probably the System settings that have no SysEx address
  (LCD contrast, Device ID, Local/Remote, Rx SysEx, sequencer sync, metronome). Identifying them
  would need songs saved after changing one setting at a time. The sequencer's quantize
  settings (Groove template number, strengths) are also candidates.

No XP-80 System bulk dump was available, so this is checked by consistency, not byte for byte.

With the SysEx option, the converter sends the part of these settings that shapes the song's
sound, before the Performance: System Common 00-0A in one message (Sound Mode, Performance
Number, Patch mode's Patch, Master Tune, Scale Tune switch, EFX/Chorus/Reverb switches) and, when
the Scale Tune switch is on, the 17 Scale Tune sets (00 00 10 00 … 20 00). The player's
preferences are sent only with the controller option: System Common 0B-51 (receive and transmit
switches, control channel, controller and pedal assignments, keyboard, preview notes, Bank Select
Groups) as one message from bit 37, then 52-5F (Pedal 3-4 and the arpeggio, from bit 336; just
52-5D from a `SYSa` block). Some, such as Receive Bank Select, could stop the converted song's own
setup from working, which is why they're optional.

## Format versions and firmware

The two digits after `SV` are a format version:

| Signature | Written by | Event records | After the events |
|---|---|---|---|
| `SV00` | XP-50, XP-60, XP-80 | 8 bytes, 96 ticks a quarter | u16 lengths (see the file layout) |
| `SV02` | original Fantom (FA-76), MC-80 | 12 bytes, 480 ticks a quarter, as in `SV03` | u16 lengths, as in `SV00` |
| `SV03` | Fantom-S, Fantom-X | 12 bytes, 480 ticks a quarter | u32 lengths |

Roland's firmware shows this. Neither update was decompiled; only data in them was read.

- **Fantom (FA-76) 1.20** (the SysEx-in-SMF update, 32 files; the floppy update holds the same
  blocks): each Data Set message carries 56 bytes packed into 64 seven-bit bytes, a byte of top bits
  (bit *k* for byte *k*) before each 7. The image holds `MIGT4` blocks, each a version, unpacked
  size, packed size and a zlib stream (the loader includes zlib 1.1.3). The 5.6 MB main program
  lists `SV02` and `SV00` as the song signatures it accepts, and holds three `SV02` songs: its
  blank new-song template (model `MC-80 0001  1.00`), its demo song "Fantom Medley" (model
  `MC-80 0.47 1.3`) and an MC-80 demo song, "Demo for VE-GS" (model `MC-80 0118 1.0`).
- **Fantom-S 1.09** (`fans.bin`): `SUBHEAD FILE` records (u32 size at +12, path at +16, data at
  +0x110) holding five `SV03` demo songs, samples, panel images and `FANS.PRG`. The program is
  LZSS-compressed after a header (`Roland FNTMS application program`, `LLZ98L016`, u32 unpacked
  size, date): flag bytes read from bit 0, 1 = literal; a reference is 2 bytes, position = byte 1 |
  (byte 2 & 0xF0) << 4 in a 4096-byte ring, length = (byte 2 & 0x0F) + 3; the ring starts at
  0xE2F (not the textbook 0xFEE), established from the new-song template it holds. It lists
  `SV00`, `SV02` and `SV03` as the signatures it loads, and its template is `SV03`.

In `SV02` the header is laid out exactly as in `SV03` (the same 0xB9-byte header with the song
length, track masks, Output bytes, Loop and RPS chunks), and the records are the same. After the
events come the XP's u16 lengths: the rest of the file, an empty length-prefixed block (40 bytes
on the XP), the pattern-name table, and the `SVD1` directory's length. The MC-80 saves no sound
settings (its sounds were on a VE-GS board). The original Fantom saves an `SVD1` directory with
model `NEXY` and three blocks: `STPa` (Setup, one 12-byte record), `PRFa` (Performance, 1126
bytes) and `MLTa` (Multitimbre, 954 bytes). It saves no Patches with the song, so like the XP's,
its songs select sounds by Bank Select and Program Change.

The blocks pack the parameters of the Fantom's own MIDI Implementation map most-significant-bit
first, like the Fantom-S/X's, after the same 16-byte block header:

- `STPa` (Setup): Sound Mode (3 bits: 0 PERFORM, 1 PATCH, 2 MULTI, 3 GM1, 4 GM2, 5 GS; a different
  order from the Fantom-S/X's), then 7-bit Bank Select MSB, LSB and program for the Multitimbre,
  the Performance and the Patch, then the effect switches, transpose and octave shift.
- `PRFa` and `MLTa` begin with the 12-character name. Both hold 16 Parts at **bit 3026**, 288
  bits each (Part 16 runs 2 bits past the end of `MLTa`), in the map's Part order: receive
  channel (4), receive switch (1), receive MIDI 1 and 2 (1 each), Bank Select MSB, LSB, program,
  level, pan (7 each), coarse and fine tune, mono/poly, legato, bend range, portamento switch and
  time (8), cutoff/resonance/attack/release offsets, octave shift (3 bits, 4 = 0), velocity sense,
  key range and fade widths, mute, dry, chorus send (bit 149), reverb send (bit 156), output…
  Worked out from the 16 preset Multitimbres and 64 preset Performances stored in the same form in
  the Fantom 1.20 firmware (every Part's channel, Bank Select and key range is plausible, and
  "GM2 Template" has GM2 Patches with a GM2 kit on Part 10) and from the demo song, whose own SysEx
  sets Sound Mode = MULTI and Part sounds at the map's Part offsets.

Banks: MSB 87 LSB 0 = USER Patches, 71-75 = PR-A to PR-E; MSB 86 LSB 0 = USER Rhythm Sets, 71 =
PRST; MSB 121/120 = GM2 Patches/Rhythm Sets; MSB 93/92 = SRX. Factory names come from the
Fantom's MIDI Implementation (Patch List and Rhythm Set List): all 640 preset Patch names were
found in the firmware's preset Patches (three of them with a double space the printed list
loses), and its GM2 list differs from the Fantom-X's in two names (slot 13 "Wurly", 104
"Strings"). User Patches aren't saved with the song, so they're shown by number only.

**The whole record**: both records hold the map's sections, each starting on a byte boundary, in
this order: Common (44 bytes), MFX 1, 2, 3 (78 each), Chorus (26), Reverb (42), MIDI × 16 (2
each), Part × 16 (36 each, after 2 undocumented bits, hence bit 3026), and in the Performance
also Zone × 16 (9 each) and Controller (28). Parameters use the map's bit widths, MSB first, and
narrow 64-centered parameters are stored re-centered, as on the Fantom-S/X. That accounts for
exactly 954 (Multitimbre) and 1126 (Performance) bytes, and across the firmware's 80 preset
records and the demo song all 118,208 decoded values are within the map's ranges. The
Multitimbre's sections are the Performance's (Common, MFX and Chorus are identical in the map; the
Reverb, MIDI and Part pages don't parse cleanly but agree where they do). One slot doesn't hold
what the map puts there: each Part's Decay Time Offset reads 126 in 940 of the 1024 preset Parts
and 2 in the rest, matching the Part's 2 lead bits (`11` or `10`, the latter in five template-like
Performances), so it is something undocumented; the converter sends 64 (no offset) instead.

With the SysEx option, the converter sends the Setup (`01 00 00 00`: Sound Mode first, as Roland's
demo song itself does, then the selected Multitimbre, Performance and Patch, effect switches,
transpose and octave shift; its map heading shares a line with another table, so its 15
parameters are written into `gen_fa76_layout.py` by hand), then the saved Multitimbre to the temporary Multitimbre (`19 00 xx 00`) or the
Performance to the temporary Performance (`10 00 xx 00`), model ID `00 10`. **Unverified**: no
Fantom dump was available to compare with. The tables are generated by
`Reference Material/Fantom Lists/gen_fa76_layout.py` from the map (`parse_fa76_map.py`).
No MIDI export of any `SV02` song was available, so `SV02` conversions are checked for
consistency (every record type known, every note converted), not against the instrument.

Any other version is read with whichever record layout fits its data best (the share of records
with a known type, and the song's end record), with a warning; its sound settings are decoded only
if its directory names data the decoder knows (`XP50`/`XP60`/`XP80`, or `FANS` for the
Fantom-S/X). The pattern-name table is used only if its entries fill it exactly and each names a
pattern in the file.

## Fantom-S/X variant (`SV03`)

The Fantom-S writes the same format as the Fantom-X. Roland's five Fantom-S demo songs (inside
the Fantom-S 1.09 system update) have model `MC-80      1.2`, 480 ticks a quarter, and the same
`SVD1` blocks with the same record sizes (`PRFa` 1220, `PATa` 664, `RHYa` 10928 bytes), so they
decode completely with everything below: names, Parts, saved Patches. No Fantom-S MIDI export of
the demo songs was available to compare the conversions with. The rest of this section was worked
out on Fantom-X files.

The Fantom-S/S88 Parameter List (MIDI Implementation 1.00) gives the same Model ID (`00 6B`), the
same addresses and the same sections as the Fantom-X's, with three differences:

- **Setup** (`01 00 00 00`) is 47 bytes (46 parameters, 196 bits): the Fantom-X's without its last
  five (two reserved, Rolled Chord, Rolled Chord Type, Arpeggio Step). Its `16` is Arp/Ptn Switch,
  reserved on the Fantom-X. The `STPa` record is 32 bytes (34 on the Fantom-X), which is how the
  decoder tells the two apart (`FantomPerformance.isFantomS`). Its first 196 bits hold the Setup:
  all 46 values are in range in the five demo songs. The 60 bits left over match what Fantom-X
  songs hold from `2F` on when Rolled Chord is off.
- **Performance Controller** is 86 bytes (85 parameters): the Fantom-X's without Rolled Chord and
  Rolled Chord Type. Arp/Ptn Switch, Pad Set and Pad Base Note fill slots that are reserved on the
  Fantom-X, and a few assign ranges are shorter. Every stored width matches, so the Performance
  record (1220 bytes) is the same, its Controller ending 3 bits earlier.
- **Factory sounds**: PR-A to PR-E (87/64-68), plus PR-F (87/69, 8 Patches) on the Fantom-S88
  only; 32 PRST Rhythm Sets; no PR-G/H/I and no sample banks. 15 names in PR-A to PR-E and PR-F
  006-008 differ from the Fantom-X's ("FS Rhodes" for "FS 70'EP", …), and so do one GM2 Patch ("60's Rhodes") and one GM2
  kit ("GM2 ORCHSTRA"). `FantomSPatchNames.swift` is generated from the Fantom-S Sound List
  (`Reference Material/Fantom-S Lists/gen_fantom_s.py`), spelled as the 1.09 program stores them.

The demo songs also have one more block, `MSEa` (14 bytes, the same in all five). It decodes as
System Mastering (`02 00 02 00`, all 18 parameters in range), but it isn't used. In two of the
demos, Parts 11-16 select PR-A 001 "So true..." while their saved Patch is named "St.Concert";
the saved Patch is what plays and what the converter sends.

**Fantom-X system versions.** Songs saved by Fantom-X system 1.0x and by 2.x (the Audio Track
Expansion) are the same format. Fantom-X song 8 was saved in February 2004, under 1.0x. Four other
songs must have been saved under 2.x: songs 2, 6 and 7 select PR-I Patches (87/72), which came
with 2.0, and song 9 has an audio track. All of them have the same model string (`MC-80      1.1.1`,
evidently the sequencer engine's version, not the system's), the same 17 `SVD1` blocks with the
same record counts and sizes, and the same 34-byte Setup, Rolled Chord and Arpeggio Step included.
The bits where song 8 differs from the four are ordinary settings (Voice Reserve, the keyboard
Patch), not a version mark. What 2.x adds is content, which the decoder already handles:

- PR-I Patches (87/72) and the USAM/CSAM sample Patch banks (MSB 64/65).
- **Audio tracks**, saved beside the song in a file with the same name and the extension `.SVA`
  (see "Audio tracks (`.SVA`)" below). The `.SVQ` itself shows no trace of them.

### Audio tracks (`.SVA`)

Fantom-X system 2.x (the Audio Track Expansion) adds eight stereo audio tracks to the sequencer.
When a song has any, saving it also writes a file with the song's name and the extension `.SVA`
(Audio Track Expansion Addendum, "Saving your audio tracks"). An audio track holds no audio:
it holds *sample events*, each saying "play User (or Card) sample number x here" (up to 256 per
track, one sounding at a time), and the samples stay in the instrument's sample memory and the
card's `ROLAND/SMPL` folder. The converter doesn't read `.SVA` files; the app and `svq2mid` only
note that a song has one.

Only one `.SVA` was available (Fantom-X song 9: one audio track with one event), so the layout
below is a first reading. Integers are big-endian.

| Chunk | Bytes | Value in song 9 | Meaning |
|---|---|---|---|
| `SThd` | 4 + u32 | `SThd`, `00 00 00 44` | File header, 68 bytes of data |
| | 4 | `01 08 00 08` | Probably a version (1) and the track count (8) |
| | 64 | zeros | Unused here |
| `STrk` × 8 | 4 + u32 | `STrk`, `00 00 00 28` (used) / `00 00 00 1C` (empty) | One per audio track: 24 bytes of settings + 12 per event, plus this u32 |
| | u32 | `00 00 00 18` | Size of the settings (24) |
| | 2 | `02 01` | Unknown, the same on every track |
| | u16 | `00 00` … `00 07` | Track number, 0-7 |
| | 12 | `Card 0549` / spaces | Track Name (up to 12 characters); the used track carries its sample's name |
| | 1 | `03` | Probably Output Assign (MFX 1-3, A, B, MON: 3 = A) |
| | 1 | `4A` (74); empty tracks `64` (100) | Track Level, 0-127 |
| | 1 | `40` | Track Pan, 64 = center (L64-63R) |
| | 1 | `00` | Probably Track Reverb Send Level |
| | 1 | `00` | Probably Track Chorus Send Level |
| | 1 | `40` | Probably Audio Track Key Shift, 64 = 0 (-24 to +24) |
| | 2 | `FF FF` | Unknown (solo/mute switches?) |
| | 12 each | `00 00 3C 00  AD 00 00 03  02 25  02 26` | Sample events |

Level and Pan are clear (the used track's level is the only value off its default). The other
settings are placed by matching the Addendum's Audio Track Mixer list (Level, Pan, Rev, Cho,
Solo, Mute, Output Assign, Key) with the default values. In the one event, `00 00 3C 00` is
15360, bar 9 at 480 ticks a quarter in 4/4, so probably the event's position in ticks; `02 25` is
549, matching the track name "Card 0549", so probably the Card sample's number, with `02 26`
(550) perhaps its 1-based number or an end marker; `AD 00 00 03` is unknown (an event can start
playing partway through its sample, so possibly an offset or a length). A second song with audio
tracks would settle these.

`PCMa` (18 one-byte records: Parts 1-16, then the Patch-mode keyboard and pad) and `PFMa` (one
byte) look like flags, perhaps "edited", for the saved Patches and the Performance: `PFMa` is 0
only in the song saved in Patch mode. They don't follow the system version either.

The Fantom-X uses the MC-80 sequencer engine. Its files have the same overall layout as the
XP's, widened for 480-tick resolution, and were checked the same way: decoding three Fantom-X
songs reproduces the Fantom-X's own MIDI exports event for event, including release
velocities, polyphonic aftertouch and pitch bend.

### Header

Same structure as the XP header: `SV03` signature, resolution 480 at offset 6, the model
string `MC-80      1.1.1` at 0x11, then the length-prefixed song name (stored as 46
space-padded characters) and comment, ending with the u32 event-data length.

Bytes 0x08-0x0F are `00 00 00 01`, then the **song's length as a time**: hours?, minutes,
seconds, frames (the largest frame value seen is 26). The minutes and seconds match the length
computed from the events and tempo map in all 13 sample songs (Fantom-X song 4: `00 01 05 0D` = 1:05).
The XP leaves these four bytes zero.

The track masks, Output bytes, Loop and RPS settings are as on the XP, except that the Loop
settings put the repeat count second (mode, repeat, u32 start, u32 end; one measure is 1920
ticks). More length-prefixed settings follow (a 22-byte block that holds what look like two
more tick positions with switches, e.g. Fantom-X song 3: `01 01 01 00 00 CA 80 01 00 01 7E 80…`,
probably Punch In/Out; then `00 08 00 04 02 04 14 32 00 00`, `00 10` + 16 zero bytes and `01 0A`
in every sample). Not decoded.

After the event data come a u32 length of the rest of the file, the pattern-name table (as on
the XP, with no 40-byte block before it), and a u32 length before the `SVD1` directory.

### Event records

Records are **12 bytes**:

```
bytes 0-1   step (u16)
byte 2      type (same codes as the XP)
byte 3      MIDI channel
byte 4      track / pattern ID
bytes 5-11  data (7 bytes)
```

The data bytes mean what they mean on the XP, with these differences:

| Type | Fantom-X data (bytes 5-11) |
|---|---|
| Note | velocity, release velocity, 0, gate (u32) |
| `82` | numerator, denominator power of 2, `78` (120), 0… (the MIDI exports use 24 clocks per click) |
| `83`/`84`/`88`/`89`/`91` | the u32 value is in bytes 8-11 |
| `87` | **Pattern call**: byte 5 = ID of the pattern this track plays from here |
| `92` | 7 SysEx bytes per record |

Tempo uses the same `83`/`84` ratio and formula as the XP, with resolution 480.

### Patterns and pattern calls

Patterns follow the song exactly as on the XP (`89` … `8E`). Unlike the XP's RPS phrases,
Fantom-X songs can play them: an `87` record on a track starts the given pattern at that
point. A call plays until the pattern ends, the same track's next call, or that track's
End-of-Track, whichever comes first. Pattern events keep their own MIDI channels.

### "SVD1" directory

After the pattern-name table comes an `SVD1` directory in the same layout as the XP's `SVD0` (u16 length 254, `SVD1`, 10 zero bytes, 15 entries of
tag, model `FANS`, offset, length):

| Tag | Contents |
|---|---|
| `STPa` | Setup |
| `PRFa` | The Performance |
| `PATa` | 18 Patches with all their parameters: Performance Parts 1-16, then Patch mode's keyboard and pad parts |
| `RHYa` | 18 Rhythm Sets, in the same order |
| `ARPa`, `CHDa`, `PTNa`, `PGPa` | Arpeggio, chord form, rhythm pattern and rhythm group data |
| `PFMa`, `PCMa`, `RHMa`, `APMa`, `CDMa`, `PTMa`, `PGMa` | Small index blocks (not decoded) |

Each block starts with a 16-byte header: u32 record count, u32 record size, u32 header size
(16), u32 zero. Parameters are bit-packed **most-significant-bit first** (the XP packs least
significant first). Names are twelve 7-bit characters at the start of a record.

### PRFa: the Performance

One record of 1220 bytes. It begins with the Performance Common (the name is the first
84 bits). The 16 Parts start at **bit 3186** and are **288 bits** each. Within a Part:

| Bits | Width | Parameter |
|---|---|---|
| 0 | 4 | Receive channel |
| 4 | 1 | Receive switch |
| 5 | 7 | Bank Select MSB |
| 12 | 7 | Bank Select LSB |
| 19 | 7 | Program Change (0-based) |
| 26 | 7 | Level |
| 33 | 7 | Pan |
| 40-146 | | Coarse/fine tune, mono/poly, legato, bend range, portamento, tone offsets, octave, velocity sense, reserved, mute, dry send |
| 147 | 7 | Chorus send |
| 154 | 7 | Reverb send |
| 161-287 | | Output Assign (4), Output MFX Select (2), an undocumented 7-bit value, vibrato rate/depth/delay, 12 scale tunes, then 7 bits that are probably Decay Time Offset |

The fields were identified from the order in the Fantom-X Owner's Manual parameter map and
confirmed across all 208 Parts of the sample songs. The manual's bit masks are not always the
stored widths (Octave Shift, for example, is stored in 3 bits as value − 60).

**The whole record** holds the SysEx map's Performance sections, packed with the `PATa` rules
below (address order within a section, mask widths, MSB first, each section byte-aligned,
multi-nibble values combined, narrow 64-centered values re-centered), but the sections are not
in address order:

| Byte | Size | Section |
|---|---|---|
| 0 | 48 | Common (367 bits, then a constant `1` bit and two zero bytes) |
| 48 | 3 × 78 | MFX 1, 2, 3 (same layout as a Patch's MFX) |
| 282 | 42 | Chorus |
| 324 | 42 | Reverb |
| 366 | 16 × 2 | MIDI (receive switches, phase lock, velocity curve) |
| 398 | 16 × 36 | Parts; each begins with 2 undocumented bits, hence bit 3186 + 288n |
| 974 | 16 × 11 | Zones (key ranges, external zone settings); each ends with 15 undocumented bits (`1111`, the zone index, a flag) |
| 1150 | 70 | Controller (pads, D Beam, switches) |

Evidence: every section's parameters regenerate exactly the manual's section size in SysEx
bytes; across 87 Performances (the 13 sample songs, Roland's 7 factory demo songs and the
Performances in five `.SVD` libraries) every name is readable and the song's selected
Performance has its Sound List name; MIDI records read "all receive switches on"; Zones read
0-127; the Controller's pad notes are the GM drum map. Of about half a million decoded values,
three lie outside the manual's ranges. The 7-bit Part value after Output MFX Select, where the
manual puts Decay Time Offset, holds 31, 63 or 95 depending only on the Part number, so Decay
Time Offset is taken to be the 7 bits at the end of the Part (always 64, the centre). The MFX
1/2/3 order is inferred from which blocks the Parts route through (111 consistent, 12 not, all
templates; the best other order scores 96/27). **Unverified:** no Fantom-X Performance dump was
available. The `prf_*.mid` files beside the songs are dump *requests* (RQ1); `prf_all_.mid` asks
for the temporary Performance and its 16 Part Patches, so capturing a Fantom-X's reply to it would
give the byte-exact reference. With the SysEx option on, the converter sends this Performance
(Data Set 1 messages to the temporary Performance, `10 00 xx 00`, in the order stored) before the
Parts' saved sounds, and says in the setup track that it is unverified. The 16 Zones and the
Controller (keyboard ranges, pads, D Beam, switches) are sent only with the controller option: 38
messages without it, 55 with it (a Fantom-S song's Controller message is 2 bytes shorter). The original Fantom's Performance is treated the same way.

A Fantom-X Part stores its Bank Select directly, so no group-to-bank table is needed:

| MSB | LSB | Group |
|---|---|---|
| 87 | 0-1 | USER patches 1-128, 129-256 |
| 87 | 32-33 | CARD patches |
| 87 | 64-71 | PR-A … PR-H patches |
| 87 | 72 | PR-I patches (added by the Audio Track Expansion) |
| 64 / 65 | 0- | USAM / CSAM sample patches (Audio Track Expansion) |
| 86 | 0 / 32 / 64 | USER / CARD / PRST rhythm sets |
| 121 / 120 | — | GM2 patches / rhythm sets |
| 93 / 92 | per board | SRX expansion patches / rhythm sets (e.g. SRX-07 patches 11-14, one LSB per 128; SRX-99 is 105) |

The name of Part *n*'s sound is in record *n* of `PATa` (or `RHYa` for rhythm sets). This was
confirmed against the Fantom-X Sound List: the stored names of all 173 preset-bank Parts in the
sample songs match the factory names for their Bank Select and Program numbers. GM2 sounds are
not saved with the song; their records are empty, so names come from the Sound List. (The Sound
List prints GM2 "Elec Perc" at LSB 1; it is LSB 2, as in the GM2 standard.)

### PATa: the saved Patches

Each record (664 bytes) is a complete Patch: the parameters of the SysEx parameter map's Patch
sections in address order (Common, MFX, Chorus, Reverb, Tone Mix Table, Tones 1-4), bit-packed
MSB first with the bit widths of the manual's masks, except:

- every section starts on a byte boundary, and one extra byte precedes Tone 1;
- a parameter whose SysEx value is centered on 64 but whose mask is narrower than 7 bits
  (Octave Shift, the keyfollow and envelope-depth parameters) is stored re-centered:
  stored = value − 64 + 2^(bits−1) (so Octave Shift 64 is stored as 4 in 3 bits);
- multi-nibble SysEx values (MFX/Chorus/Reverb parameters, wave numbers) are stored as one
  value of the combined width (16 bits for four nibbles).

That accounts for 5,168 bits; the remaining 144 bits take one of two fixed patterns and aren't
parameters. Verified byte for byte: the "Sylky Bells" and "DrkUltmtGrnd" Patches saved in the
sample songs regenerate the Fantom-X's own 9-message dumps of those Patches (two Patch dumps captured from the instrument), checksums included. The Fantom-X's Model ID is `00 6B`; a Performance Part's
temporary Patch is at `11 00 00 00` + Part offset (`11 00`, `11 20`, `11 40`, `11 60`, `12 00`, …
`14 60`), Patch mode's keyboard and pad Patches at `1F 00 00 00` and `1F 20 00 00`.

`RHYa` records are Rhythm Sets: Common (18 SysEx bytes), MFX, Chorus and Reverb (identical to
the Patch sections), then 88 Rhythm Tones (keys 21-108, 195 bytes each, at offsets `00 10`,
`00 12` … `01 3E` in 7-bit address arithmetic), with the same packing rules but no extra byte
before the first tone. **Unverified:** no Rhythm Set dump was available, but across all 234 saved
kits in the sample songs every Rhythm Tone name decodes as readable text and every other value
lies within the manual's documented range. A Part's temporary Rhythm Set is its temporary Patch
address + `00 10 00 00` (Part 10: `13 30 00 00`).

### STPa: Setup and Sound Mode

One 34-byte record: the manual's Setup section (`01 00 00 00`) in address order, MSB first,
without section padding, 213 bits: Sound Mode (3 bits: 0 PATCH, 1 PERFORM, 2 GM1, 3 GM2, 4 GS),
7-bit Bank Select MSB, LSB and Program for the Performance, the keyboard Patch and the pad
Patch, then the effect switches, Patch-mode chorus/reverb sources, Transpose, Octave Shift,
D Beam and knob selects, the arpeggio, rhythm pattern and chord settings, part selects, Rolled
Chord and Arpeggio Step. The last 59 bits are undocumented; they take one of two patterns, the
second exactly when Rolled Chord is off. Everything after the sound selections is inferred
from the map order and value ranges.

With the SysEx option, a Fantom-X song's whole Setup section (52 bytes) is sent to `01 00 00 00`
before the Performance; the dumps that follow replace the Performance and Patches it selects. A
Fantom-S song's 47-byte Setup is sent the same way (see "Fantom-S/X variant").

A song saved in **Patch mode** plays the keyboard Patch and pad sound rather than the
Performance. Those are records 17 and 18 of `PATa`/`RHYa`: for example, Fantom-X song 8's keyboard
Patch 87/69/60 is "La Seine" in both the Setup and `PATa` record 17. They play on the
"Kbd Patch Rx/Tx Ch" and "Pad Patch Rx/Tx Ch" system settings, which aren't saved with the
song. The converter uses the Fantom-X defaults, channels 1 and 10.

### Track outputs

The per-track Output bytes in the header (see the header table) were identified from Fantom-X song 6, where track 3 played a V-Synth: track 3 is `01` (MIDI Out only) and the Fantom-X Part on
its channel has its Receive switch off, tracks 1, 2, 5 and 10 are `80` (internal only) and play
Parts with deliberately chosen patches, and track 16, which holds a V-Synth SysEx setup dump, is
`00` (Off). Every track in the other sample songs, XP and Fantom-X, is `81` (BOTH). The
converter keeps the data of every track by default (Off tracks can be left out), names MIDI-Out
and Off tracks accordingly, and sends
the instrument's Part setup only on channels played by tracks that use the internal sound
generator.
