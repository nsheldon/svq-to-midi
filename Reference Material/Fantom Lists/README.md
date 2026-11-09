# Original Fantom (FA-76) sound names

`SVQKit/Sources/SVQKit/FA76Names.swift` is generated from the Fantom's MIDI Implementation
(`FANTOM_MI.pdf`, Roland's document, not committed): its Patch List (USER, PR-A to PR-E, GM2) and
Rhythm Set List (PRST, GM2). Never hand-edit the Swift file.

```sh
mkdir -p dl && pdftotext -layout ../FANTOM_MI.pdf dl/FANTOM_MI.txt
python3 parse_fantom.py   # -> fantom_lists.json
python3 gen_fantom.py     # -> ../../SVQKit/Sources/SVQKit/FA76Names.swift
```

Checks:

- `parse_fantom.py` requires 128 names in each preset group, 16 preset and 9 GM2 kits, and all
  256 GM2 entries with the GM2 standard's Bank Select LSB and program (taken from the app's
  Fantom-X GM2 table and matched entry by entry).
- The 640 preset Patch names were compared with the Fantom 1.20 system update, which stores every
  preset Patch with its name: 637 match as printed; three are stored with a double space that the
  printed list (or pdftotext) loses, and `gen_fantom.py` uses the stored spacing.
- The Fantom's GM2 names match the Fantom-X's except slot 13 ("Wurly", not "60's EP") and slot
  104 ("Strings", not "Orche str"), so the Fantom has its own GM2 table.
- The factory USER Patch list isn't used: user Patches aren't saved with a song, and the owner may
  have replaced them.

## Parameter map (for the SysEx setup)

`parse_fa76_map.py` reads the MIDI Implementation's Parameter Address Map (two columns of tables
per page; each page is cut at its column split) into `fa76_map.json`, and `gen_fa76_layout.py`
writes `SVQKit/Sources/SVQKit/FA76Layout.swift`: the Performance's Common, MFX, Chorus, Reverb,
MIDI, Part, Zone and Controller parameters with their SysEx byte counts and stored bit widths.

```sh
python3 parse_fa76_map.py   # prints each section's size against the map's Total Size
python3 gen_fa76_layout.py  # checks the sizes and the Multitimbre/Performance match, then writes the Swift file
```

How the saved records use these sections, and what is unverified, is in `docs/SVQ-Format.md`
("Format versions and firmware").
