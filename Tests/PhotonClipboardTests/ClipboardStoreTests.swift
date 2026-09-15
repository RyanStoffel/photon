import Foundation
import PhotonClipboard
import XCTest

final class ClipboardStoreTests: XCTestCase {
  private let settings = ClipboardSettings(retention: .forever, maxItems: 100)
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func makeDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("photon-clipboard-tests-\(UUID().uuidString)", isDirectory: true)
  }

  private func png(_ seed: UInt8) -> Data {
    Data([0x89, 0x50, 0x4e, 0x47, seed, seed, seed])
  }

  private func blobCount(in directory: URL) -> Int {
    let blobs = try? FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("blobs").path)
    return blobs?.count ?? 0
  }

  func testInsertAndReloadRoundTrip() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ClipboardStore(directory: directory)

    let text = await store.insert(
      ClipboardCapture(text: "hello", richText: Data("{\\rtf1}".utf8), sourceBundleID: "com.apple.Notes", date: now),
      settings: settings
    )
    XCTAssertEqual(text?.outcome, .inserted)

    let image = await store.insert(
      ClipboardCapture(imagePNG: png(1), imageWidth: 4, imageHeight: 2, date: now.addingTimeInterval(1)),
      settings: settings
    )
    XCTAssertEqual(image?.snapshot.items.count, 2)

    let files = await store.insert(
      ClipboardCapture(filePaths: ["/tmp/a.txt", "/tmp/b.txt"], date: now.addingTimeInterval(2)),
      settings: settings
    )
    let finalSnapshot = try XCTUnwrap(files?.snapshot)
    XCTAssertEqual(finalSnapshot.items.map(\.kind), [.file, .image, .text])
    XCTAssertGreaterThan(finalSnapshot.storageBytes, 0)
    XCTAssertEqual(blobCount(in: directory), 2, "one rtf blob and one png blob")

    let reloaded = ClipboardStore(directory: directory)
    let snapshot = await reloaded.load()
    XCTAssertEqual(snapshot.items, finalSnapshot.items)

    let textItem = try XCTUnwrap(snapshot.items.first { $0.kind == .text })
    let payload = await reloaded.payload(for: textItem)
    XCTAssertEqual(payload.text, "hello")
    XCTAssertEqual(payload.richText, Data("{\\rtf1}".utf8))
    XCTAssertTrue(textItem.hasRichText)
    XCTAssertEqual(textItem.sourceBundleID, "com.apple.Notes")

    let imageItem = try XCTUnwrap(snapshot.items.first { $0.kind == .image })
    let imageData = await reloaded.imageData(for: imageItem)
    XCTAssertEqual(imageData, png(1))
    XCTAssertEqual(imageItem.imageWidth, 4)
    XCTAssertEqual(imageItem.subtitle, "4 × 2 px")

    let fileItem = try XCTUnwrap(snapshot.items.first { $0.kind == .file })
    XCTAssertEqual(fileItem.title, "2 files")
    XCTAssertEqual(fileItem.filePaths, ["/tmp/a.txt", "/tmp/b.txt"])
  }

  func testLargeTextGoesToBlobAndComesBackWhole() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ClipboardStore(directory: directory)
    let large = String(repeating: "line of text\n", count: 3000)
    XCTAssertGreaterThan(large.count, ClipboardItem.inlineTextLimit)

    let result = await store.insert(ClipboardCapture(text: large), settings: settings)
    let item = try XCTUnwrap(result?.snapshot.items.first)
    XCTAssertTrue(item.isTextTruncated)
    XCTAssertEqual(item.text?.count, ClipboardItem.inlineTextLimit)

    let blob = await store.blobURL(id: item.id, extension: "txt")
    XCTAssertTrue(FileManager.default.fileExists(atPath: blob.path))
    let full = await store.fullText(for: item)
    XCTAssertEqual(full, large)
  }

  func testDuplicateCaptureDoesNotWriteASecondBlob() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ClipboardStore(directory: directory)

    let first = await store.insert(ClipboardCapture(imagePNG: png(7)), settings: settings)
    let firstID = try XCTUnwrap(first?.snapshot.items.first?.id)
    let second = await store.insert(ClipboardCapture(imagePNG: png(7)), settings: settings)
    XCTAssertEqual(second?.outcome, .movedToTop(firstID))
    XCTAssertEqual(second?.snapshot.items.count, 1)
    XCTAssertEqual(blobCount(in: directory), 1)
  }

  func testRemoveDeletesBlobsAndClearAllEmptiesTheStore() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ClipboardStore(directory: directory)

    let inserted = await store.insert(ClipboardCapture(imagePNG: png(3)), settings: settings)
    let item = try XCTUnwrap(inserted?.snapshot.items.first)
    let blob = await store.blobURL(id: item.id, extension: "png")
    XCTAssertTrue(FileManager.default.fileExists(atPath: blob.path))

    let afterRemove = await store.remove(id: item.id)
    XCTAssertTrue(afterRemove.items.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: blob.path))

    _ = await store.insert(ClipboardCapture(text: "one"), settings: settings)
    _ = await store.insert(ClipboardCapture(text: "two"), settings: settings)
    let cleared = await store.removeAll()
    XCTAssertTrue(cleared.items.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("blobs").path))

    let reloaded = await ClipboardStore(directory: directory).load()
    XCTAssertTrue(reloaded.items.isEmpty)
  }

  func testInsertAppliesRetentionAndLimit() async {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ClipboardStore(directory: directory)
    let tight = ClipboardSettings(retention: .oneDay, maxItems: 2)

    _ = await store.insert(ClipboardCapture(text: "expired", date: now.addingTimeInterval(-2 * 86400)), settings: tight)
    _ = await store.insert(ClipboardCapture(text: "a", date: now.addingTimeInterval(-30)), settings: tight)
    _ = await store.insert(ClipboardCapture(text: "b", date: now.addingTimeInterval(-20)), settings: tight)
    let result = await store.insert(ClipboardCapture(text: "c", date: now), settings: tight)
    XCTAssertEqual(result?.snapshot.items.map(\.text), ["c", "b"])
  }

  func testPinnedItemsSurviveRetentionPrune() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ClipboardStore(directory: directory)

    let old = await store.insert(
      ClipboardCapture(text: "keep", date: now.addingTimeInterval(-40 * 86400)),
      settings: settings
    )
    let oldID = try XCTUnwrap(old?.snapshot.items.first?.id)
    _ = await store.setPinned(true, id: oldID)
    let pruned = await store.prune(settings: ClipboardSettings(retention: .sevenDays, maxItems: 10), now: now)
    XCTAssertEqual(pruned.items.map(\.text), ["keep"])
    XCTAssertEqual(pruned.items.first?.isPinned, true)
  }

  func testTouchMovesItemToTopAndPersists() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ClipboardStore(directory: directory)

    let first = await store.insert(
      ClipboardCapture(text: "first", date: now.addingTimeInterval(-60)),
      settings: settings
    )
    let firstID = try XCTUnwrap(first?.snapshot.items.first?.id)
    _ = await store.insert(ClipboardCapture(text: "second", date: now.addingTimeInterval(-30)), settings: settings)
    let touched = await store.touch(id: firstID, at: now)
    XCTAssertEqual(touched.items.map(\.text), ["first", "second"])

    let reloaded = await ClipboardStore(directory: directory).load()
    XCTAssertEqual(reloaded.items.map(\.text), ["first", "second"])
  }

  func testEmptyCaptureIsIgnored() async {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ClipboardStore(directory: directory)
    let result = await store.insert(ClipboardCapture(), settings: settings)
    XCTAssertNil(result)
    XCTAssertNil(ClipboardCapture(text: "").primaryKind)
  }

  func testCapturePrioritisesFilesThenTextThenImage() {
    XCTAssertEqual(ClipboardCapture(text: "x", imagePNG: png(1), filePaths: ["/a"]).primaryKind, .file)
    XCTAssertEqual(ClipboardCapture(text: "x", imagePNG: png(1)).primaryKind, .text)
    XCTAssertEqual(ClipboardCapture(text: "https://a.io", imagePNG: png(1)).primaryKind, .link)
    XCTAssertEqual(ClipboardCapture(imagePNG: png(1)).primaryKind, .image)
    let item = ClipboardCapture(text: "x", imagePNG: png(1)).makeItem()
    XCTAssertEqual(item?.hasImage, true, "secondary image rides along with text")
    XCTAssertEqual(item?.byteCount, 1 + png(1).count)
  }
}
