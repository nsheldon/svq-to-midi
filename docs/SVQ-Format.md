# Roland SVQ sequence format (XP-50/60/80 and Fantom-X)

This describes the `.SVQ` song files written by the Roland XP-50, XP-60 and XP-80 sequencer
(model string `XP-80 0105 1.7`, signature `SV00`) and by the Fantom-X6/X7/X8 (model string
`MC-80      1.1.1`, signature `SV03`). The Fantom-X variant is covered in its own section
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
The converter doesn't use these blocks.

## Fantom-X variant (`SV03`)

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
(55 Data Set 1 messages to the temporary Performance, `10 00 xx 00`, in the order stored)
before the Parts' saved sounds, and says in the setup track that it is unverified.

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
