import SVQKit
import SwiftUI

/// One row of the Phrase Tracks or Pattern Tracks list.
struct TrackRowData: Identifiable {
    let id: String
    let content: AppModel.DragContent
    var icon: String
    var name: String
    var column2 = ""
    var channels = ""
    var sound = ""
    var notes = ""
    var keys = ""
    var column7 = ""
    var contents = ""
    var help = ""
    /// Shown dimmed (a track the instrument didn't play, or one that isn't converted).
    var isDimmed = false
    /// Whether the row can be dragged out as a MIDI file. The Tempo and Beat tracks can't: on their
    /// own they make a file with no notes, which a DAW imports as nothing.
    var isDraggable = true
}

/// The column titles; the second and seventh columns differ between phrase tracks and patterns.
struct TrackColumnTitles {
    var name: String
    var column2: String
    var column7: String
    /// The seventh column's width ("Bars" is narrow, "Played by" wider).
    var column7Width: CGFloat = 64
}

/// A row's cells in fixed columns, shared by the header so the two line up.
private struct TrackColumns: View {
    var icon: String?
    var name: String
    var column2: String
    var channels: String
    var sound: String
    var notes: String
    var keys: String
    var column7: String
    var contents: String
    var column7Width: CGFloat = 64
    var isHeader = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon ?? "music.note.list")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .opacity(icon == nil ? 0 : 1)
                Text(name).fontWeight(isHeader ? .regular : .medium)
            }
            .frame(width: 128, alignment: .leading)
            Text(column2).frame(width: 64, alignment: .leading)
            Text(channels).frame(width: 52, alignment: .leading)
            Text(sound).frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            Text(notes).frame(width: 52, alignment: .trailing)
            Text(keys).frame(width: 64, alignment: .leading)
            Text(column7).frame(width: column7Width, alignment: .leading)
            Text(contents).frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .monospacedDigit()
    }
}

/// A list of tracks, each draggable to the Finder or a DAW as a MIDI file.
struct TrackList: View {
    @EnvironmentObject private var model: AppModel
    let item: SVQItem
    let titles: TrackColumnTitles
    let rows: [TrackRowData]
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            List {
                Section {
                    ForEach(rows) { row in
                        TrackColumns(icon: row.icon, name: row.name, column2: row.column2, channels: row.channels,
                                     sound: row.sound, notes: row.notes, keys: row.keys, column7: row.column7,
                                     contents: row.contents, column7Width: titles.column7Width)
                            .foregroundStyle(row.isDimmed ? .secondary : .primary)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .help(row.help)
                            .midiDrag(isEnabled: row.isDraggable) { model.dragFile(row.content, of: item) }
                    }
                } header: {
                    TrackColumns(icon: nil, name: titles.name, column2: titles.column2, channels: "Ch",
                                 sound: "Sound", notes: "Notes", keys: "Keys", column7: titles.column7,
                                 contents: "Other events", column7Width: titles.column7Width, isHeader: true)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
}

// MARK: - Phrase tracks

struct PhraseTracksView: View {
    @EnvironmentObject private var model: AppModel
    let item: SVQItem
    let svq: SVQFile

    var body: some View {
        TrackList(item: item, titles: TrackColumnTitles(name: "Track", column2: "Output", column7: "Bars"),
                  rows: rows,
                  note: "Drag a phrase track to the Finder or a DAW to save it as a MIDI file, with the "
                      + "song\u{2019}s tempo, meter and key and its channel setup.")
    }

    private var rows: [TrackRowData] {
        var rows = [tempoRow, beatRow]
        for track in svq.usedTracks {
            rows.append(phraseRow(track))
        }
        return rows
    }

    private func bars(_ summary: SVQEventSummary) -> String {
        guard let first = summary.firstTick, let end = summary.endTick else { return "" }
        return svq.measureRangeText(from: first, to: end)
    }

    private var tempoRow: TrackRowData {
        let events = svq.tempoEvents
        let summary = SVQEventSummary(events: events)
        let bpms = events.compactMap { e -> Double? in
            if case .tempo(let us) = e.kind { return 60_000_000 / Double(us) } else { return nil }
        }
        var sound = bpms.first.map(bpmText) ?? ""
        if let low = bpms.min(), let high = bpms.max(), high - low >= 0.05 {
            sound = "\(bpmText(low).dropLast(4))–\(bpmText(high))"
        }
        let changes = max(0, events.count - 1)
        return TrackRowData(id: "tempo", content: .conductor(.tempo), icon: "metronome", name: "Tempo",
                            sound: sound, column7: bars(summary),
                            contents: changes == 0 ? "No changes" : "\(changes) change\(changes == 1 ? "" : "s")",
                            help: "The Tempo track: \(events.count) tempo event\(events.count == 1 ? "" : "s"). "
                                + "Each track\u{2019}s file includes it.",
                            isDraggable: false)
    }

    private var beatRow: TrackRowData {
        let events = svq.beatEvents
        let summary = SVQEventSummary(events: events)
        var parts = [svq.initialTimeSignature.displayString]
        if let key = events.first(where: { if case .keySignature = $0.kind { return $0.tick == 0 } else { return false } }),
           case .keySignature(let sf, let minor) = key.kind {
            parts.append(keySignatureName(sharpsFlats: sf, minor: minor))
        }
        let meterChanges = max(0, summary.meterChanges - 1)
        let keyChanges = max(0, summary.keyChanges - 1)
        let contents = [meterChanges > 0 ? "\(meterChanges) meter" : nil, keyChanges > 0 ? "\(keyChanges) key" : nil]
            .compactMap { $0 }.joined(separator: ", ")
        return TrackRowData(id: "beat", content: .conductor(.beat), icon: "music.quarternote.3", name: "Beat",
                            sound: parts.joined(separator: " · "), column7: bars(summary),
                            contents: contents.isEmpty ? "No changes" : contents + " change\(meterChanges + keyChanges == 1 ? "" : "s")",
                            help: "The Beat track: meter (time signature) and key. Each track\u{2019}s file includes it.",
                            isDraggable: false)
    }

    private func phraseRow(_ track: Int) -> TrackRowData {
        let summary = SVQEventSummary(events: svq.events(onTrack: track))
        let output = svq.output(ofTrack: track)
        var contents = summary.compactOtherEventsText
        var patterns = ""
        let calls = svq.patternCalls.filter { $0.track == track }
        if !calls.isEmpty {
            let numbers = Array(Set(calls.compactMap(\.patternNumber))).sorted().map(String.init)
            patterns = "Pattern\(numbers.count == 1 ? "" : "s") \(numbers.joined(separator: ", "))"
            contents = [patterns, contents].filter { !$0.isEmpty }.joined(separator: "; ")
        }
        let excluded = output == .off && !model.options.includeOffTracks
        let muted = svq.mutedTracks.contains(track)
        let sound = soundText(svq, summary.channels, output)
        var help = ["Track \(track + 1), Output \(output.displayName)"
                    + (output == .midi ? ": played an external instrument, so it gets no Part setup" : "")]
        if excluded { help.append("Not converted: the options leave out tracks set to Off") }
        if muted {
            help.append("Muted when the song was saved (probably: this reading of the file is unconfirmed). "
                        + "It is still converted; mute it in your DAW if you like.")
        }
        if !summary.channels.isEmpty { help.append("Channel \(channelsText(summary.channels)): \(sound)") }
        help += [patterns.isEmpty ? nil : "Plays \(patterns) (\(calls.count) call\(calls.count == 1 ? "" : "s"))",
                 summary.otherEventsText.isEmpty ? nil : summary.otherEventsText].compactMap { $0 }
        return TrackRowData(id: "track\(track)", content: .track(track), icon: muted ? "speaker.slash" : "music.note.list",
                            name: "Track \(track + 1)", column2: output.displayName,
                            channels: channelsText(summary.channels), sound: sound,
                            notes: summary.notes == 0 ? "" : summary.notes.formatted(), keys: summary.keyRangeText ?? "",
                            column7: bars(summary), contents: contents, help: help.joined(separator: "\n"),
                            isDimmed: !output.playsInternally || excluded || muted, isDraggable: !summary.isEmpty)
    }
}

// MARK: - Pattern tracks

struct PatternTracksView: View {
    let item: SVQItem
    let svq: SVQFile

    var body: some View {
        if svq.patterns.isEmpty {
            Text("This song has no patterns.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TrackList(item: item, titles: TrackColumnTitles(name: "Pattern", column2: "Length", column7: "Played by", column7Width: 150),
                      rows: svq.patterns.map(row), note: note)
        }
    }

    private var note: String {
        var text = "Drag a pattern to the Finder or a DAW to save it as a MIDI file."
        if svq.variant == .xp {
            text += " On the XP, patterns play through RPS or from a phrase track that calls them."
        }
        return text
    }

    private func row(_ pattern: SVQPattern) -> TrackRowData {
        let summary = SVQEventSummary(events: pattern.events)
        let meter = pattern.events.lazy.compactMap { e -> SVQTimeSignature? in
            if case .timeSignature(let ts) = e.kind, e.tick == 0 { return ts } else { return nil }
        }.first ?? svq.initialTimeSignature
        let measure = meter.ticksPerMeasure(resolution: svq.resolution)
        let bars = (pattern.length + measure - 1) / measure
        let calls = svq.patternCalls.filter { $0.patternNumber == pattern.number }
        let byTrack = Dictionary(grouping: calls, by: \.track)
        let rpsKeys = svq.rpsAssignments.filter { $0.patternNumber == pattern.number }
        let playedBy = (byTrack.keys.sorted().map { track in
            let n = byTrack[track]?.count ?? 0
            return n == 1 ? "Track \(track + 1)" : "Track \(track + 1) ×\(n)"
        } + rpsKeys.map { "RPS \($0.summary)" }).joined(separator: ", ")
        return TrackRowData(id: "pattern\(pattern.number)", content: .pattern(pattern), icon: "square.grid.3x3",
                            name: pattern.name.isEmpty ? "\(pattern.number)" : "\(pattern.number)  \(pattern.name)",
                            column2: "\(bars) bar\(bars == 1 ? "" : "s")",
                            channels: channelsText(summary.channels),
                            sound: soundText(svq, summary.channels, .both),
                            notes: summary.notes == 0 ? "" : summary.notes.formatted(), keys: summary.keyRangeText ?? "",
                            column7: playedBy.isEmpty ? "–" : playedBy, contents: summary.compactOtherEventsText,
                            help: ([playedBy.isEmpty ? "Not played by the song" : "Played by \(playedBy)"]
                                   + [summary.otherEventsText].filter { !$0.isEmpty }).joined(separator: "\n"),
                            isDraggable: !summary.isEmpty)
    }
}

// MARK: - Helpers

private func channelsText(_ channels: Set<UInt8>) -> String {
    channels.sorted().map { "\($0 + 1)" }.joined(separator: ", ")
}

/// The sound each channel plays, from the song's saved Performance.
private func soundText(_ svq: SVQFile, _ channels: Set<UInt8>, _ output: SVQTrackOutput) -> String {
    if output == .midi { return "External (MIDI Out)" }
    let names = channels.sorted().compactMap { channel in
        svq.setup?.parts.first { $0.receiveSwitch && $0.midiChannel == Int(channel) }?.displayName
    }
    return names.joined(separator: ", ")
}
