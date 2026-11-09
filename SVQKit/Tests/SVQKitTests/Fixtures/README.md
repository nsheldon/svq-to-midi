# Test fixtures

The tests compare the decoder against real SVQ files and the MIDI files the instruments exported
from them. Those files are the author's own songs (and Roland's demo songs) and aren't in the repository; tests that need a
missing fixture are skipped (the synthetic-file tests always run). The files are given generic
names here.

To run the full suite, place these files here:

| File | What it is |
|---|---|
| `XP-01.SVQ`, `XP-01.mid` | XP-80 song and its XP-80 MIDI export (with Performance SysEx dump); its Performance is named after the song |
| `XP-02.SVQ`, `XP-02.mid` | XP-80 song and export (with Performance SysEx dump) |
| `XP-03.SVQ`, `XP-03.mid` | XP-80 song with SysEx recorded in the song, and its export |
| `XP-04.SVQ`, `XP-04.mid` | XP-80 song and export |
| `XP-05.SVQ` | XP-80 song with named patterns and an RPS setup |
| `Fantom-X/FX-01.SVQ`, `.MID` | Fantom-X song (GM2 Parts) and its Fantom-X export |
| `Fantom-X/FX-02.SVQ`, `.MID` | Fantom-X song and export |
| `Fantom-X/FX-03.SVQ`, `.MID` | Fantom-X song in 3/4 and export |
| `Fantom-X/FX-04.SVQ` | Fantom-X song with pattern calls and named patterns |
| `Fantom-X/FX-05.SVQ` | Fantom-X song saved in Patch mode |
| `Fantom-X/FX-06.SVQ` | Fantom-X song with MIDI-Out and Off tracks, pattern IDs that skip, and an RPS setup |
| `Fantom-S/FS-DEMO-0.SVQ` … `FS-DEMO-4.SVQ` | Roland's five Fantom-S demo songs: `ROLAND/SEQ/SNG/song0.svq` … `song4.svq` inside `fans.bin` of Roland's Fantom-S System Update 1.09 (a file record "SUBHEAD FILE", u32 size at +12, path at +16, data at +0x110) |
| `Fantom/FA-DEMO-1.SVQ`, `MC80-DEMO-1.SVQ`, `FA-NEW-SONG.SVQ` | `SV02` songs inside Roland's Fantom (FA-76) 1.20 firmware: its demo song "Fantom Medley", an MC-80 demo song and the blank new-song template. Unpack the SysEx update (56 bytes per Data Set message, a top-bits byte before each 7), then zlib-inflate the main program's `MIGT4` block (see docs/SVQ-Format.md, "Format versions and firmware"); each song starts at the u16 header length before `SV02` and runs to the end of the u16 "rest of file" length after its events |
| `Fantom-X/FX-07.SVQ`, `FX-PATCH-1.MID`, `FX-PATCH-2.MID` | Song and two Fantom-X Patch dumps for the byte-exact Patch test (`FX-PATCH-1` is the Part 1 Patch of `FX-04`, `FX-PATCH-2` that of `FX-07`) |
