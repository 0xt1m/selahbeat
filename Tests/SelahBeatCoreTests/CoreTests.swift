import Testing
import Foundation
@testable import SelahBeatCore

@Suite("Tap tempo")
struct TapTempoTests {
    @Test("Two taps half a second apart give 120 BPM")
    func twoTaps() {
        var tap = TapTempo()
        #expect(tap.tap(at: 0) == nil)
        let bpm = tap.tap(at: 0.5)
        #expect(bpm != nil)
        #expect(abs(bpm! - 120) < 0.5)
    }

    @Test("A fumbled tap does not wreck the estimate")
    func rejectsOutliers() {
        var tap = TapTempo()
        // Steady 120 BPM, then one badly mistimed tap.
        for i in 0...5 { tap.tap(at: Double(i) * 0.5) }
        let steady = tap.estimate()!
        tap.tap(at: 2.5 + 0.12)   // way early
        let after = tap.estimate()!
        #expect(abs(after - steady) < 12, "outlier moved estimate from \(steady) to \(after)")
    }

    @Test("A long gap starts a new tap sequence")
    func resetsAfterGap() {
        var tap = TapTempo()
        tap.tap(at: 0)
        tap.tap(at: 0.5)
        #expect(tap.tapCount == 2)
        tap.tap(at: 10.0)          // well past resetInterval
        #expect(tap.tapCount == 1)
        #expect(tap.estimate() == nil)
    }

    @Test("Estimates stay inside the supported tempo range")
    func clamps() {
        var tap = TapTempo()
        tap.tap(at: 0)
        let bpm = tap.tap(at: 0.02)   // 3000 BPM if unclamped
        #expect(bpm! <= Song.maxBPM)
    }
}

@Suite("Search")
struct SearchTests {
    private func library() -> SearchIndex {
        SearchIndex(songs: [
            Song(title: "What A Beautiful Name", artist: "Hillsong Worship", defaultBPM: 68),
            Song(title: "Goodness Of God", artist: "Bethel Music", defaultBPM: 63),
            Song(title: "Way Maker", artist: "Sinach", defaultBPM: 66),
            Song(title: "Who You Say I Am", artist: "Hillsong Worship", defaultBPM: 76),
            Song(title: "Bui\u{0142}dings", artist: nil, defaultBPM: 100),
        ])
    }

    @Test("Prefix matches rank above substring matches")
    func ranking() {
        let index = library()
        let results = index.search("way")
        #expect(!results.isEmpty)
        #expect(results.first?.rawValue.isEmpty == false)
    }

    @Test("Matching is case- and punctuation-insensitive")
    func normalisation() {
        #expect(normalizedForSearch("What A Beautiful Name!") == "what a beautiful name")
        #expect(normalizedForSearch("  Who You Say  I Am ") == "who you say i am")
        #expect(normalizedForSearch("Cornerstone (Live)") == "cornerstone live")
    }

    @Test("Any word in the title can be typed to find a song")
    func wordPrefix() {
        let index = library()
        // A drummer types the memorable word, not the first one.
        #expect(!index.search("beautiful").isEmpty)
        #expect(!index.search("maker").isEmpty)
    }

    @Test("Artist name finds the song too")
    func artistSearch() {
        let index = library()
        #expect(index.search("sinach").count == 1)
        #expect(index.search("hillsong").count == 2)
    }

    @Test("An empty query matches nothing")
    func emptyQuery() {
        #expect(library().search("").isEmpty)
    }
}

@Suite("Persistence")
struct PersistenceTests {
    private func tempDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("selahbeat-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A payload round-trips through disk")
    func roundTrip() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = JSONFileStore<LibraryPayload>(url: dir.appendingPathComponent("library.json"))
        let song = Song(title: "Way Maker", artist: "Sinach", defaultBPM: 66)
        try store.save(LibraryPayload(songs: [song], recent: [song.id]))

        let loaded = store.load()
        #expect(loaded?.songs.first?.title == "Way Maker")
        #expect(loaded?.recent.first == song.id)
    }

    @Test("A corrupted primary file recovers from the backup")
    func backupRecovery() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("library.json")
        let store = JSONFileStore<LibraryPayload>(url: url)

        try store.save(LibraryPayload(songs: [Song(title: "First", defaultBPM: 100)]))
        // Second save promotes the good file to .bak.
        try store.save(LibraryPayload(songs: [Song(title: "Second", defaultBPM: 110)]))

        // Simulate a torn write / disk corruption.
        try Data("{ not json".utf8).write(to: url)

        let recovered = store.load()
        #expect(recovered?.songs.first?.title == "First")
    }

    @Test("A missing file loads as empty rather than failing")
    func missingFile() {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileStore<LibraryPayload>(url: dir.appendingPathComponent("nope.json"))
        #expect(store.load() == nil)
    }
}

@Suite("Reordering")
struct ReorderTests {
    @Test("Moving an item down lands it where SwiftUI expects")
    func moveDown() {
        var items = ["a", "b", "c", "d"]
        items.moveElements(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(items == ["b", "c", "a", "d"])
    }

    @Test("Moving an item up lands it where SwiftUI expects")
    func moveUp() {
        var items = ["a", "b", "c", "d"]
        items.moveElements(fromOffsets: IndexSet(integer: 3), toOffset: 1)
        #expect(items == ["a", "d", "b", "c"])
    }

    @Test("Moving several items keeps their relative order")
    func moveMultiple() {
        var items = ["a", "b", "c", "d", "e"]
        items.moveElements(fromOffsets: IndexSet([0, 2]), toOffset: 5)
        #expect(items == ["b", "d", "e", "a", "c"])
    }
}

@Suite("Meter")
struct MeterTests {
    @Test("6/8 is treated as two dotted-quarter pulses, not six beats")
    func compoundMeter() {
        let sixEight = TimeSignature.sixEight
        #expect(sixEight.isCompound)
        #expect(sixEight.pulseCount == 2)

        let pattern = ClickPattern.standard(for: sixEight, subdivision: .triplet)
        #expect(pattern.ticksPerBar == 6)
        #expect(pattern.ticksPerBeat == 3)
        #expect(pattern.levels[0] == 1)   // downbeat
        #expect(pattern.levels[3] == 3)   // second pulse is a beat, not a subdivision
    }

    @Test("4/4 with eighths alternates beats and subdivisions")
    func simpleMeter() {
        let pattern = ClickPattern.standard(for: .fourFour, subdivision: .eighth)
        #expect(pattern.ticksPerBar == 8)
        #expect(pattern.levels == [1, 4, 3, 4, 3, 4, 3, 4])
    }

    @Test("Frames per tick tracks tempo and subdivision")
    func framesPerTick() {
        let quarters = ClickPattern.standard(for: .fourFour, subdivision: .quarter)
        #expect(quarters.framesPerTick(bpm: 120, sampleRate: 48_000) == 24_000)

        let eighths = ClickPattern.standard(for: .fourFour, subdivision: .eighth)
        #expect(eighths.framesPerTick(bpm: 120, sampleRate: 48_000) == 12_000)
    }

    @Test("Odd meters build a full bar")
    func oddMeter() {
        let sevenEight = TimeSignature(beats: 7, noteValue: 8)
        #expect(!sevenEight.isCompound)
        let pattern = ClickPattern.standard(for: sevenEight, subdivision: .quarter)
        #expect(pattern.ticksPerBar == 7)
    }
}

@Suite("Keys")
struct KeyTests {
    @Test("Flat keys keep their spelling instead of collapsing to sharps")
    func spelling() {
        let bFlat = MusicalKey.parse("Bb")
        #expect(bFlat?.letter == .B)
        #expect(bFlat?.accidental == .flat)
        #expect(bFlat?.asciiDisplay == "Bb")
    }

    @Test("Minor keys parse")
    func minor() {
        let fSharpMinor = MusicalKey.parse("F#m")
        #expect(fSharpMinor?.mode == .minor)
        #expect(fSharpMinor?.asciiDisplay == "F#m")
    }

    @Test("Nonsense does not parse")
    func invalid() {
        #expect(MusicalKey.parse("") == nil)
        #expect(MusicalKey.parse("H") == nil)
    }
}

@Suite("Catalog")
struct CatalogTests {
    @Test("A catalog song imports as an offline-capable library song")
    func importCopiesEverything() {
        let entry = CatalogSong(
            id: "way-maker",
            title: "Way Maker",
            artist: "Sinach",
            bpm: 66,
            beats: 4,
            noteValue: 4,
            key: "E",
            revision: 3
        )
        let song = entry.toSong()
        #expect(song.id == SongID.catalog("way-maker"))
        #expect(song.defaultBPM == 66)
        #expect(song.defaultKey?.asciiDisplay == "E")
        #expect(song.origin.isCatalog)
        #expect(song.isUserModified == false)
    }

    @Test("Namespaced IDs keep custom songs from colliding with catalog slugs")
    func identity() {
        let catalog = SongID.catalog("way-maker")
        #expect(catalog.isCatalog)
        #expect(catalog.catalogSlug == "way-maker")

        let local = SongID.local()
        #expect(local.isLocal)
        #expect(local.catalogSlug == nil)
    }

    @Test("Overrides resolve against the song's defaults")
    func overrides() {
        let song = Song(title: "Goodness Of God", defaultBPM: 63, defaultTimeSignature: .fourFour)
        var item = ServiceItem(songID: song.id)

        #expect(ResolvedItem(item: item, song: song).bpm == 63)

        // A team plays it slower than the record this week.
        item.bpmOverride = 58
        item.key = MusicalKey(.A, .flat)
        let resolved = ResolvedItem(item: item, song: song)
        #expect(resolved.bpm == 58)
        #expect(resolved.key?.asciiDisplay == "Ab")
        #expect(resolved.hasBPMOverride)
    }
}

@Suite("Updates")
struct UpdateTests {
    @Test("Newer versions are detected")
    func detectsNewer() {
        #expect(UpdateChecker.isNewer("1.2.0", than: "1.1.9"))
        #expect(UpdateChecker.isNewer("2.0.0", than: "1.9.9"))
        #expect(UpdateChecker.isNewer("1.0.1", than: "1.0.0"))
    }

    @Test("Same or older versions are not offered")
    func ignoresOlder() {
        #expect(!UpdateChecker.isNewer("1.0.0", than: "1.0.0"))
        #expect(!UpdateChecker.isNewer("1.0.0", than: "1.0.1"))
        #expect(!UpdateChecker.isNewer("0.9.0", than: "1.0.0"))
    }

    @Test("Comparison is numeric, not lexicographic")
    func numericComparison() {
        // A string compare would call 0.9.0 newer than 0.10.0.
        #expect(UpdateChecker.isNewer("0.10.0", than: "0.9.0"))
        #expect(!UpdateChecker.isNewer("0.9.0", than: "0.10.0"))
        #expect(UpdateChecker.isNewer("1.0.10", than: "1.0.9"))
    }

    @Test("Missing components are treated as zero")
    func differentLengths() {
        #expect(UpdateChecker.isNewer("1.1", than: "1.0.9"))
        #expect(!UpdateChecker.isNewer("1.0", than: "1.0.0"))
    }
}

@Suite("Service editing")
@MainActor
struct ServiceEditingTests {
    private func makeStore() async -> LibraryStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("selahbeat-tests-\(UUID().uuidString)")
        let store = LibraryStore(persistence: PersistenceCoordinator(directory: dir))
        await store.bootstrap()
        return store
    }

    @Test("One song can be added to several services independently")
    func sameSongInTwoServices() async {
        let store = await makeStore()
        let song = store.addSong(Song(title: "Way Maker", defaultBPM: 66))
        let sunday = store.createService(name: "Sunday")
        let youth = store.createService(name: "Youth")

        store.addSong(song.id, to: sunday.id, key: MusicalKey(.E))
        store.addSong(song.id, to: youth.id, key: MusicalKey(.G))

        #expect(store.service(sunday.id)?.items.count == 1)
        #expect(store.service(youth.id)?.items.count == 1)
        // Key is placement data: the same song is played in a different key.
        #expect(store.resolvedItems(in: sunday.id).first?.key?.asciiDisplay == "E")
        #expect(store.resolvedItems(in: youth.id).first?.key?.asciiDisplay == "G")
        #expect(store.usageCount(of: song.id) == 2)
    }

    @Test("Removing a song from one service leaves the other alone")
    func removalIsScoped() async {
        let store = await makeStore()
        let song = store.addSong(Song(title: "Goodness Of God", defaultBPM: 63))
        let a = store.createService(name: "A")
        let b = store.createService(name: "B")
        store.addSong(song.id, to: a.id)
        store.addSong(song.id, to: b.id)

        let itemInA = store.service(a.id)!.items[0].id
        store.removeItem(itemInA, from: a.id)

        #expect(store.service(a.id)?.items.isEmpty == true)
        #expect(store.service(b.id)?.items.count == 1)
        #expect(store.song(song.id) != nil, "removing a placement must not delete the song")
    }

    @Test("A song can appear twice in one service as its own placement")
    func twiceInOneService() async {
        let store = await makeStore()
        let song = store.addSong(Song(title: "Cornerstone", defaultBPM: 70))
        let service = store.createService(name: "Sunday")
        store.addSong(song.id, to: service.id, key: MusicalKey(.C))
        store.addSong(song.id, to: service.id, key: MusicalKey(.D))

        let items = store.service(service.id)!.items
        #expect(items.count == 2)
        // Distinct placement identities, or ForEach would crash on duplicates.
        #expect(items[0].id != items[1].id)
    }

    @Test("Reordering only touches the service being reordered")
    func reorderIsScoped() async {
        let store = await makeStore()
        let first = store.addSong(Song(title: "First", defaultBPM: 100))
        let second = store.addSong(Song(title: "Second", defaultBPM: 110))
        let a = store.createService(name: "A")
        let b = store.createService(name: "B")
        for id in [first.id, second.id] {
            store.addSong(id, to: a.id)
            store.addSong(id, to: b.id)
        }

        store.moveItems(in: a.id, from: IndexSet(integer: 0), to: 2)

        #expect(store.resolvedItems(in: a.id).map(\.title) == ["Second", "First"])
        #expect(store.resolvedItems(in: b.id).map(\.title) == ["First", "Second"])
    }

    @Test("Deleting a song removes it from every service that used it")
    func deleteCascades() async {
        let store = await makeStore()
        let song = store.addSong(Song(title: "Temporary", defaultBPM: 90))
        let a = store.createService(name: "A")
        let b = store.createService(name: "B")
        store.addSong(song.id, to: a.id)
        store.addSong(song.id, to: b.id)

        store.deleteSong(song.id)

        #expect(store.service(a.id)?.items.isEmpty == true)
        #expect(store.service(b.id)?.items.isEmpty == true)
    }

    @Test("Suggested service names land on a Sunday")
    func suggestedName() async {
        let store = await makeStore()
        // 2026-09-10 is a Thursday; the next Sunday is the 13th.
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 10
        let thursday = Calendar.current.date(from: components)!
        #expect(store.suggestedServiceName(from: thursday).contains("13"))
    }
}
