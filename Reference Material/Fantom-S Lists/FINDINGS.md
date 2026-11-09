# Fantom-S vs Fantom-X: parameter map and sound lists

Compared: the Fantom-S/S88 Parameter List (`FANTOM-S_PR.pdf`, MIDI Implementation v1.00, Feb 2003) and Sound List (`FANTOM-S_PA.pdf`) with what the app assumes for `SV03` songs: the Fantom-X map (`../Fantom-X Map/map678.json`) and `FantomPatchNames.swift`. Roland's extracted text is in `dl/` (not committed).

```sh
pdftotext -layout ../FANTOM-S_PR.pdf dl/FANTOM-S_PR.txt
pdftotext -layout ../FANTOM-S_PA.pdf dl/FANTOM-S_PA.txt
python3 -I parse_fs_map.py dl/FANTOM-S_PR.txt fs_map.json   # every section matches its Total Size
python3 -I compare_maps.py                                   # section-by-section diff vs map678.json
python3 -I decode_stpa.py   ../../SVQKit/Tests/SVQKitTests/Fixtures/Fantom-S/FS-DEMO-*.SVQ
python3 -I decode_records.py ../../SVQKit/Tests/SVQKitTests/Fixtures/Fantom-S/FS-DEMO-*.SVQ
python3 -I parse_fs_lists.py dl/FANTOM-S_PA.txt fantoms_lists.json
python3 -I check_firmware_names.py <decompressed FANS.PRG from the 1.09 update>
python3 -I compare_lists.py                                  # names vs FantomPatchNames.swift
```

What the app uses from this:

```sh
python3 -I gen_fantom_s.py                      # -> SVQKit/Sources/SVQKit/FantomSPatchNames.swift
cd "../Fantom-X Map" && python3 gen_perf_layout.py   # reads fs_map.json: checks the Fantom-S Setup and
                                                     # Controller are prefixes of the Fantom-X's and writes
                                                     # fantomSSetupCount / fantomSControllerCount
```

"Verified" means read from Roland's documents, the demo songs or the Fantom-S 1.09 program. "Inferred" means not checked against the instrument.

## 1. Model ID and addresses (verified, documents)

- The Model ID is **`00 6B`**, the same as the Fantom-X's ("Fantom-S/Fantom-S88 (ModelID = 00H 6BH)").
- The top-level address table is identical to the Fantom-X's:
  - Setup `01 00 00 00`, System `02 00 00 00`, Temporary Performance `10 00 00 00`.
  - Parts 1-16 temporary Patch/Rhythm `11 00 00 00` … `14 60 00 00`.
  - `1E 00/01/02/03/11/12/13`: rhythm pattern, arpeggio, chord, rhythm group.
  - Patch mode Part 1/2 `1F 00 00 00` / `1F 20 00 00`.
  - Temporary Rhythm = Temporary Patch + `00 10 00 00`.
  - The sub-section offsets are the same too.
- **The Setup's Total Size is `00 00 00 2F` (47 bytes)**: 46 parameters, 196 bits. The Fantom-X's is `34` (52 bytes, 51 parameters, 213 bits).

## 2. Section-by-section comparison (verified: offsets and masks)

Every section parses to exactly its printed Total Size. Where a range differs only because pdftotext lost it in one of the two parses (masks identical), the difference is ignored.

| Section | Result |
|---|---|
| **Setup** | Same as the FX's addresses `00`-`2E`, identical masks. `16` is **Arp/Ptn Switch** on the FS ("(reserve)" on the FX). `14` D Beam Select is printed 0-5 (FX 0-3; same four values listed). **FX-only:** `2F` reserve (1 bit), `30` reserve (7), `31` Rolled Chord, `32` Rolled Chord Type, `33` Arpeggio Step (17 bits in all). Sound Mode is 0-5 in both (5 = PIANO, S88 only on the FS). |
| Performance Common, MFX, Chorus, Reverb, MIDI, Part, Zone | Identical. The Performance MFX Type is printed 0-127 on the FS and 0-78 on the FX; same 7-bit mask. |
| **Performance Controller** | FS `56` (85 params, 547 bits) vs FX `58` (87, 550 bits). **FX-only:** `56` Rolled Chord, `57` Rolled Chord Type. On the FS, `0D` is Arp/Ptn Switch, `21` Pad Set (0-2) and `22` Pad Base Note (all reserved on the FX). Beam Assign 0-102 (FX 0-104); Knob 1-4 Assign 0-101 (FX 0-103). |
| Patch Common, MFX, Chorus, Reverb, TMT, Tone | Identical |
| Rhythm Common, MFX, Chorus, Reverb, Tone | Identical |
| System Common, Mastering, External Input; Arpeggio, Chord, Rhythm Group | Identical |
| System Controller | Same size. `1A` Pad Set and `1B` Pad Base Note are reserved on the FX. Pedal Assign 0-108 (FX 0-111), Beam 0-102, Knob 1-4 0-101. |

## 3. STPa of the five demo songs

- **Verified:** the header is `[1, 32, 16, 0]`. The FS Setup layout (address order, mask widths, MSB first, no padding, narrow 64-centred values re-centred) uses **196 of 256 bits**, and **all 46 values are in range in all five songs**:
  - Sound Mode 1 (PERFORM); Performance 85/0/0-4 (USER 1-5).
  - Keyboard Patch 87/0/0; pad 86/64/1 or 86/0/0.
  - All effect switches on; transpose and octave at 64.
- **Verified (bits):** the remaining 60 bits are `0 0111100 0 00 000000`, then the first 43 bits of the Fantom-X's 59-bit undocumented tail. This is exactly what Fantom-X songs hold in `2F`-`33` and after when Rolled Chord is off.
- **Inferred:**
  - The FS stores the FX's Setup structure, truncated by 2 bytes.
  - Sending 47 bytes (the first 196 bits) to `01 00 00 00` would match the FS Setup exactly. (The app now does this.)
  - The FX's 52 bytes would write 5 bytes past the FS Setup.

## 4. Bank Select (verified, "Bank Select and Program Change Correspondence Chart")

| | MSB | LSB | Notes |
|---|---|---|---|
| USER / CARD Patches | 87 | 0-1 / 32-33 | 256 each |
| PR-A … PR-E | 87 | 64-68 | **5 preset groups** (FX: PR-A…PR-H at 64-71, PR-I at 72) |
| PR-F (Fantom-S88 only) | 87 | 69 | **8 Patches** (PC 1-8) |
| GM2 Patches / Rhythm Sets | 121 / 120 | 0- / — | 256 Patches; 9 kits, PC 1-57. MSB 0-63 also select GM Patches on receive. |
| USER / CARD / PRST Rhythm Sets | 86 | 0 / 32 / 64 | 32 each (FX PRST: 40) |
| SRX Patches / Rhythm Sets (XP-A…XP-D) | 93 / 92 | per board | As on the FX |
| USER / CARD / PRST Performances | 85 | 0 / 32 / 64 | 64 each |

There are no USAM/CSAM banks (64/65).

## 5. Sound List vs `FantomPatchNames.swift` (`fantoms_lists.json`)

Spellings checked against the firmware:
- All 640 PR-A…E names, the 8 PR-F names and the 32 PRST kits match the preset records in the Fantom-S 1.09 program. They are packed like `PATa`/`RHYa` names, at a 664- or 10928-byte stride.
- All 256 GM2 Patch names and 9 GM2 kit names occur in the program as 12-character text.
- GM2 LSB/PC follow the GM2 standard. The printed "Elec Perc" LSB 1 is the same Roland typo as in the Fantom-X list (it is really 2).

| Group | vs Fantom-X table |
|---|---|
| PR-A | 7 differ: 13 FS Rhodes (FX FS 70'EP), 14 StageRhdTrem (StageEP Trem), 16 Tine Rhodes (Tine EP), 17 LEO Rhodes (LEO EP), 21 Crystal Rhd (Crystal EP), 35 FM Rhodes (FM EP), 98 HarWonderca (Harmonderca) |
| PR-B | 1: 8 Hurtling Gtr (Hurting Gtr) |
| PR-C | 2: 66 Vliolin Lead (Violin Lead), 90 "Q" DualSaws (Q DualSaws) |
| PR-D | 2: 5 Alpha Retro (Alfa Retro), 16 Fred&Barney (Loonacy) |
| PR-E | 3: 11 "2 Point 2" (2 Point 2); 54 FS AlphaRave (FX FS Alfa Rave; pdftotext gives "FS Alpha Rave"); 99 `OutOf  sortz` (FX `OutOf sortz`, spacing only) |
| PR-F | FS has 8; 1-5 match FX PR-F 1-5; 6-8 Rhodes mkI / Stage Rhodes / P-330EnsemEP (FX EP mkI / Stage EP / MKS20EnsemEP). FX 9-128 don't exist on the FS. |
| PR-G/H/I | Don't exist on the FS |
| GM2 Patches | Identical except 13 (LSB 3, PC 4): **60's Rhodes** (FX 60's EP) |
| PRST Rhythm Sets | 1-32 identical; FX 33-40 don't exist on the FS |
| GM2 Rhythm Sets | Identical except 8: **GM2 ORCHSTRA** (FX GM2 ORCHESTRA) |

Inferred: "GM2 ORCHESTRA" (13 characters) and `OutOf sortz` are probably wrong in the Fantom-X table too.

## 6. Other points relevant to conversion

- **Verified (Owner's Manual):**
  - "Save Song" stores "the data of the temporary area" in the .SVQ.
  - Samples are saved separately, as `smpl####.wav/aif` files, by "Save Song+Samples".
  - Wave Group Type can be SAMPLE or MULTISAMPLE. None of the demos' 184 active tones are (all INT).
- **Verified (decode):** with the FS map and the app's packing rules, `PRFa`/`PATa`/`RHYa` decode fully (345,065 values in non-empty records). Values below their ranges, which the 13 Fantom-X songs never show:
  - Rhythm Tone "Aftertouch Time Ctrl Sens" is 0 on all 88 keys of every saved kit (1,584 values; range 1-127).
  - LFO Step 1-16 is 0 in 44 tones of 7 Patches (704 values; range 28-100).
  - Inferred: the FS leaves these at 0, and a dump would send them as 0.
- **Verified:** `PRFa` is 1220 bytes. The FS Controller ends 3 bits earlier than the FX's, and those bits are 0. The app sends the FS Controller as 86 bytes (its section's size).
- **Inferred:** `MSEa` (14 bytes, identical in all demos) decodes as System Mastering (`02 00 02 00`):
  - All 18 parameters are in range: attack 20, release 10, ratio 6, level 3 in every band; split 3/3.
  - That uses 94 bits, leaving 18 bits `111001000000000000`.
  - Fantom-X songs have no `MSEa` block.
- **Observation:** in two demos, Parts 11-16 select 87/64/0 (PR-A 1 "So true...") but their `PATa` records are named "St.Concert". Unresolved.
- The MIDI Implementation is v1.00, while the demos come from 1.09. Parameters added later wouldn't be in this map.
