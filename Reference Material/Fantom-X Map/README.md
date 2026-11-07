# Fantom-X parameter map

`map678.json` is the Parameter Address Map from the Fantom-X6/X7/X8 Owner's Manual (MIDI
Implementation, from p. 298): every SysEx section with its parameters' offsets, bit masks and
ranges. `gen_perf_layout.py` turns its Performance sections into
`SVQKit/Sources/SVQKit/FantomPerformanceLayout.swift` (never hand-edit that file).

To rebuild the JSON, extract the manual's MIDI Implementation pages with `pdftotext -layout` into
`dl/fx678_imp.txt` (not committed: Roland's text), then:

```sh
python3 parse_map.py        # -> map678.json
python3 gen_perf_layout.py  # -> ../../SVQKit/Sources/SVQKit/FantomPerformanceLayout.swift
```

How the Performance record is laid out, and what is and isn't verified, is in
`docs/SVQ-Format.md` ("PRFa: the Performance"). In short: the layout was worked out from this
map and 87 saved Performances, with the packing rules verified for Patches; no Fantom-X
Performance dump was available to check it byte for byte.
