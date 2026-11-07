# SRX patch name sources

`SVQKit/Sources/SVQKit/SRXBoards.swift` is generated from these documents. Fantom-X songs select
SRX sounds with Bank Select MSB 93 (patches) or 92 (rhythm sets) plus an LSB that Roland assigned
to each board, so unlike SR-JV80 boards on the XP the slot a board sits in doesn't matter.

| Boards | Source |
|---|---|
| 01-12, 98 | Roland's owner's manuals, `https://static.roland.com/assets/media/pdf/SRX-NN_OM.pdf`. Each manual's patch list for the Fantom series is used; several manuals print a different list for the RD series/MC-909, and SRX-12 prints one specifically for the Fantom-X/Fantom-S/JUNO-G. The Bank Select LSBs come from the same pages. Exact spacing comes from Roland Japan's lists (below). |
| 99 Special SRX Board 2004 | Roland Japan's text list `srx-99.txt` in `https://static.roland.com/jp/media/zip/SRXINSTLIST.zip` (2010; the zip also has SRX-01 to 12). 64 patches, Bank Select LSB **105**. The leading "#" is part of patches 1-39's names. |
| 97 Rock Organ | Bank Select only: 12 patches at LSB 97, from Roland's Supplemental Note SN 132 v3.00 (2007, `https://static.roland.com/assets/media/pdf/Selecting_SRX_Sounds_0707.pdf`). No patch list could be found: the owner's manual isn't downloadable, and the only full list seen (a 2007 forum post) was an image that no longer exists. Three names appear in a demo artist's notes on Roland Japan's 2007 campaign page ("In Time ORG", "SuperDistLd1", "Velo Rock ORG"; the last is 13 characters, so not exact); they aren't used. |
| 96 World Collection & Legendary XP Essentials | Nothing: no list and no documented Bank Select (a forum guess of LSB 96 is unconfirmed, and SRX-99 shows the LSB isn't always the board number). Songs using it show "SRX" and the program number. |

Downloaded documents go in `dl/` and are not committed.

Checks:

- Banks and counts of SRX-01 to SRX-12, 97 and 98 match Roland's Supplemental Note SN 132,
  "Selecting Internal and SRX-Series Sounds Via MIDI" (v2.00 in the Fantom-X8 Instructions folder
  as "Fantom-X Selecting SRX Patches via MIDI.pdf"; v3.00 adds SRX-11, 12, 97 and 98), including
  its two examples (SRX-03 #17, SRX-06 #271).
- `parse_srx.py` requires every list to be numbered 1-N without gaps, every name to be at most 12
  characters, and every name to be followed by a column gap in the source text (so none is cut short).
- `parse_jp.py` compares the manuals with Roland Japan's lists for SRX-01 to 12. Apart from spacing
  (pdftotext collapses the double spaces that pad names like "Kick 1  Menu"; the generator takes
  Roland Japan's spacing), they differ in:
  - "Rhodes" names. Roland Japan's list has the original names ("Stage Rhodes", "TouchRhdsSRX",
    "Rhd Chd Menu", ...) where the manuals, revised in 2006, say "EP" ("Stage EP 2",
    "Touch EP SRX", "EP Chd Menu", ...): 5 patches on SRX-03, 6 on SRX-05, 8 on SRX-07, 1 on
    SRX-08. The manuals' names are used. Which names a given board shows depends on its
    production run; a song that uses one of these patches shows the name saved in the song anyway.
  - SRX-07 has 465 patches in Roland Japan's list and 475 in the manual and SN 132; the manual is used.
  - Text glitches in Roland Japan's list ("Sick Bass" for the printed "Si<n>ck Bass",
    "OthrCym Men", a quoted "1,2,3,4! SRX"); the manuals are used.
- 136 of the 144 SRX-07 names on synthmania.com's partial list match exactly. Of the other eight,
  two were a parser bug, since fixed (names ending in "SRX" had been cut short), and four are
  "/" in the manual where synthmania has "-" (the page images show "/"). "SeventhHeavn" is
  printed that way in the manual (synthmania: "SeventHeavn").
- Corrections in `gen_srx.py`: "TB3O3 Reso" is printed with a letter O ("TB303 Reso"); "H2O" is
  three words on the page ("H 2 O", as in Roland Japan's list), which `pdftotext -layout` runs
  together. A comparison with `pdftotext -raw` found no other dropped spaces.
- Names are kept exactly as printed, including "^", "`", "~" and "<n>", which appear in the page
  images too.

To regenerate (from this folder):

```sh
mkdir -p dl && cd dl
for b in 01 02 03 04 05 06 07 08 09 10 11 12 98; do
  curl -sSLO -A "Mozilla/5.0" "https://static.roland.com/assets/media/pdf/SRX-${b}_OM.pdf"
  pdftotext -layout "SRX-${b}_OM.pdf" "SRX-${b}_OM.txt"
done
curl -sSLO -A "Mozilla/5.0" "https://static.roland.com/jp/media/zip/SRXINSTLIST.zip"
mkdir -p SRXINSTLIST && unzip -o -d SRXINSTLIST SRXINSTLIST.zip
cd ..
python3 parse_srx.py   # -> srx_lists.json (owner's manuals)
python3 parse_jp.py    # -> jp_lists.json, special_lists.json (Roland Japan; prints the differences)
python3 gen_srx.py     # -> ../../SVQKit/Sources/SVQKit/SRXBoards.swift
```

`parse_srx.py` selects lists by line number in the `pdftotext -layout` output, so a different
version of a manual or of pdftotext may need the ranges adjusting; the script stops with an
error rather than produce a wrong list.
