# SR-JV80 patch name sources

`SVQKit/Sources/SVQKit/SRJV80Boards.swift` is generated from these documents:

| Boards | Source |
|---|---|
| 02, 04, 05, 08, 10-14, 16, 18, 19 | `lists/` — Roland's "Original Patch/Rhythm Set Data List" pages from the SRX-06 to SRX-09 CD-ROMs (archive.org item `roland-srx-cd`, folder `SRJVData`) |
| 09 Session | `JV-1010 Owner's Manual.pdf` — the JV-1010 has the Session board built in ("XP-A (Session)" list) |
| 01 Pop, 03 Piano | `POP_P.pdf`, `PIANO_P.pdf` — Roland US patch listings (1996) from cdn.roland.com, proofread against the page images; obvious typesetting errors in the Piano listing are corrected in `gen_boards.py` |
| 06 Dance | `SR-JV80-06_OM.pdf` page 5 (a scan), transcribed by hand into `dance06.txt`. Phrase-loop patches include their BPM in the name; the repeated letters in rows 180-184 are a best reading |
| 07 Super Sound Set | `SR-JV80-07 SOUND_P.pdf` (Roland listing; text layer proofread against the page image, four typesetting errors fixed in `gen_boards.py`) |
| 15 Special FX | `SR-JV80-15 EFX_P1.pdf` (Roland listing; rows 10/11 are misnumbered on the sheet and are assigned by position) |
| 17 Country | `SR-JV80-17 cntryp.pdf` (Roland listing, exact text) |
| 97 Experience III, 98 Experience II, 99 Experience | `exp_lists.py` — transcriptions from synthmania.com; the leading "*" is part of the patch names |

To regenerate (from this folder):

```sh
pdftotext -layout "JV-1010 Owner's Manual.pdf" jv1010.txt
python3 s09.py          # -> session09.json
python3 scan.py         # -> scans.json (Pop, Piano)
python3 parse07.py      # -> sss07_raw.json (Super Sound Set)
python3 parse_vc.py     # -> vc_lists.json (Special FX, Country)
python3 parse_lists.py  # -> archive_lists.json
python3 gen_boards.py   # -> ../../SVQKit/Sources/SVQKit/SRJV80Boards.swift
```

