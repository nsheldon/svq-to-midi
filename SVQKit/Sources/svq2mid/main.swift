import Foundation
import SVQKit

let usage = """
Usage: svq2mid [options] <file.svq | folder>...

Converts Roland XP-50/60/80 and Fantom-X SVQ sequence files to Standard MIDI Files.

Options:
  -o, --output <dir>     Write MIDI files to <dir> (default: next to each SVQ file)
  -i, --info             Print song and Performance details instead of converting
      --no-patches       Do not add Bank Select / Program Change for each Part
      --no-mixer         Do not add Part level/pan/reverb/chorus controllers
      --sysex            Add the instrument setup as System Exclusive (XP: the Performance;
                         Fantom-X: every Part's saved Patch/Rhythm Set, Rhythm Sets unverified)
                         on a separate setup track: solo it for the first play, then mute it
      --lead-in <n>      Insert <n> empty measures before the song (default 0)
      --slot <id>=<A-D>  Expansion board SR-JV80-<id> was in slot A-D (repeatable)
      --no-patterns      Do not write separate files for patterns
      --no-off-tracks    Leave out tracks whose Output is set to Off
      --file-names       Name output files after the SVQ file instead of the song name
  -h, --help             Show this help
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var options = SVQConversionOptions()
var outputDirectory: URL?
var infoOnly = false
var writePatterns = true
var useFileNames = false
var inputs: [URL] = []

var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    switch arg {
    case "-h", "--help": print(usage); exit(0)
    case "-o", "--output":
        guard let dir = args.popFirst() else { fail("Missing directory after \(arg)") }
        outputDirectory = URL(fileURLWithPath: dir, isDirectory: true)
    case "-i", "--info": infoOnly = true
    case "--no-patches": options.addPatchSelection = false
    case "--no-mixer": options.addMixerSettings = false
    case "--sysex": options.addPerformanceSysEx = true
    case "--lead-in":
        guard let n = args.popFirst().flatMap(Int.init), n >= 0 else { fail("--lead-in needs a number") }
        options.leadInMeasures = n
    case "--slot":
        let parts = args.popFirst()?.split(separator: "=") ?? []
        guard parts.count == 2, let board = Int(parts[0]),
              let slot = "ABCD".firstIndex(of: Character(parts[1].uppercased())) else {
            fail("--slot expects <board>=<A-D>, e.g. --slot 9=A")
        }
        options.expansionSlots[board] = "ABCD".distance(from: "ABCD".startIndex, to: slot)
    case "--no-patterns": writePatterns = false
    case "--no-off-tracks": options.includeOffTracks = false
    case "--file-names": useFileNames = true
    default:
        if arg.hasPrefix("-") { fail("Unknown option \(arg)\n\n\(usage)") }
        inputs.append(URL(fileURLWithPath: arg))
    }
}
if inputs.isEmpty { print(usage); exit(1) }

// Expand folders.
var files: [URL] = []
for input in inputs {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: input.path, isDirectory: &isDirectory) else {
        fail("No such file: \(input.path)")
    }
    if isDirectory.boolValue {
        let found = FileManager.default.enumerator(at: input, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "svq" } ?? []
        files += found.sorted { $0.path < $1.path }
    } else {
        files.append(input)
    }
}

func safeFileName(_ name: String) -> String {
    let cleaned = name.map { "/:\\".contains($0) ? "-" : $0 }
    return String(cleaned).trimmingCharacters(in: .whitespaces)
}

var failures = 0
for url in files {
    do {
        let svq = try SVQFile(contentsOf: url)
        if infoOnly {
            print("\(url.lastPathComponent): \"\(svq.songName)\" [\(svq.model), \(svq.variant.displayName)]")
            print(String(format: "  %.1f BPM%@, %@, %d notes, %d ticks/quarter, %d:%02d",
                         svq.initialBPM, svq.hasTempoChanges ? " (with tempo changes)" : "",
                         svq.initialTimeSignature.displayString, svq.noteCount, svq.resolution,
                         Int(svq.duration) / 60, Int(svq.duration) % 60))
            let trackList = svq.usedTracks.map { t -> String in
                let output = svq.output(ofTrack: t)
                return output.playsInternally ? "\(t + 1)" : "\(t + 1) (\(output.displayName))"
            }
            print("  Tracks used: " + trackList.joined(separator: ", "))
            if !svq.patterns.isEmpty {
                print("  Patterns: \(svq.patterns.count)\(svq.patternCallCount > 0 ? " (\(svq.patternCallCount) calls expanded into the song)" : "")")
            }
            if let perf = svq.setup {
                let boards = svq.performance?.expansionBoards ?? []
                let quotedName = perf.name.isEmpty ? "" : " \u{201C}\(perf.name)\u{201D}"
                let heading = perf.instrument.contains("mode") ? perf.instrument : "\(perf.instrument) Performance"
                print("  \(heading)\(quotedName):")
                if let note = perf.note { print("  (\(note))") }
                for part in perf.parts {
                    let used = svq.internallyPlayedChannels.contains(UInt8(part.midiChannel)) ? "*" : " "
                    let bank = part.bankSelect(slotForBoard: { options.slot(forBoard: $0, boardsInUse: boards) })
                        .map { "\($0.msb)/\($0.lsb)/\(Int($0.program) + 1)" } ?? "-"
                    let mixer = part.hasMixerSettings
                        ? String(format: "lvl %3d pan %3d rev %3d cho %3d", part.level, part.pan,
                                 part.reverbSendLevel, part.chorusSendLevel)
                        : "(no part mixer)"
                    print(String(format: "   %@Part %3@  ch %2d %@  %-30@ %-10@ %@",
                                 used, part.label, part.midiChannel + 1, part.receiveSwitch ? "  " : "off",
                                 part.displayName, bank, mixer))
                }
            }
            for warning in svq.warnings { print("  warning: \(warning)") }
            continue
        }

        let directory = outputDirectory ?? url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = safeFileName(useFileNames || svq.songName.isEmpty
                                ? url.deletingPathExtension().lastPathComponent : svq.songName)
        let out = directory.appendingPathComponent(base).appendingPathExtension("mid")
        try SVQConverter.midiData(for: svq, options: options).write(to: out)
        print("\(url.lastPathComponent) → \(out.path)")
        if writePatterns {
            for pattern in svq.patterns {
                let patternURL = directory.appendingPathComponent("\(base) - \(pattern.fileLabel.replacingOccurrences(of: "/", with: "-"))")
                    .appendingPathExtension("mid")
                try SVQConverter.midiData(for: svq, pattern: pattern, options: options).write(to: patternURL)
                print("  pattern \(pattern.number) → \(patternURL.lastPathComponent)")
            }
        }
        for warning in svq.warnings { print("  warning: \(warning)") }
    } catch {
        failures += 1
        FileHandle.standardError.write(Data("\(url.lastPathComponent): \(error.localizedDescription)\n".utf8))
    }
}
exit(failures == 0 ? 0 : 1)
