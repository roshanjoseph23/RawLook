import UniformTypeIdentifiers
import XCTest

@testable import RawLook

/// Apple-only checks for the UTType rules behind drag and drop and Dock opens.
final class PhotoDropTests: XCTestCase {
  func testOpenableContentTypes() {
    for type in [UTType.fujifilmRAW, .rawImage, .jpeg, .heic, .heif, .png, .tiff] {
      XCTAssertTrue(type.isOpenablePhoto, type.identifier)
    }
    XCTAssertTrue(UTType.fujifilmRAW.isRAWPhoto)
    XCTAssertFalse(UTType.jpeg.isRAWPhoto)
    for type in [UTType.gif, .bmp, .pdf, .image, .movie, .plainText, .fileURL] {
      XCTAssertFalse(type.isOpenablePhoto, type.identifier)
    }
  }

  func testPreferredPhotoTypeKeepsRAW() {
    XCTAssertEqual(UTType.preferredPhotoType(in: [.jpeg, .fujifilmRAW]), .fujifilmRAW)
    XCTAssertEqual(UTType.preferredPhotoType(in: [.png, .jpeg]), .jpeg)
    XCTAssertEqual(UTType.preferredPhotoType(in: [.gif, .heic]), .heic)
    XCTAssertNil(UTType.preferredPhotoType(in: [.gif, .fileURL, .plainText]))
    XCTAssertNil(UTType.preferredPhotoType(in: []))
  }

  func testOpenablePhotoFileURLs() {
    XCTAssertTrue(UTType.isOpenablePhotoFile(URL(fileURLWithPath: "/tmp/DSCF1234.RAF")))
    XCTAssertTrue(UTType.isOpenablePhotoFile(URL(fileURLWithPath: "/tmp/IMG_0001.HEIC")))
    XCTAssertFalse(UTType.isOpenablePhotoFile(URL(fileURLWithPath: "/tmp/clip.gif")))
    XCTAssertFalse(UTType.isOpenablePhotoFile(URL(fileURLWithPath: "/tmp/notes.txt")))
  }

  func testDroppedFileNameMatchesContentType() {
    let temp = URL(fileURLWithPath: "/tmp/AB12CD.tmp")
    XCTAssertEqual(
      PhotoDrop.fileName(source: temp, type: .fujifilmRAW, suggestedName: "DSCF1234"),
      "DSCF1234.raf")
    XCTAssertEqual(
      PhotoDrop.fileName(
        source: URL(fileURLWithPath: "/tmp/DSCF1234.RAF"), type: .fujifilmRAW, suggestedName: nil),
      "DSCF1234.RAF")
    XCTAssertEqual(
      PhotoDrop.fileName(source: temp, type: .jpeg, suggestedName: "Beach.jpeg"), "Beach.jpeg")
    XCTAssertEqual(
      PhotoDrop.fileName(source: temp, type: .jpeg, suggestedName: nil), "AB12CD.jpeg")
  }

  func testAppDelegatePicksFirstSupportedFile() {
    let urls = ["notes.txt", "DSCF1.RAF", "DSCF2.RAF"].map { URL(fileURLWithPath: "/tmp/" + $0) }
    let pick = OpenablePhotoFile.pick(urls, where: UTType.isOpenablePhotoFile)
    XCTAssertEqual(pick?.item.lastPathComponent, "DSCF1.RAF")
    XCTAssertEqual(pick?.ignoredCount, 2)
  }

  @MainActor
  func testDropCopiesRAWBytesInsteadOfJPEGFileURL() async throws {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: directory) }
    let rawURL = directory.appendingPathComponent("Original.raf")
    let jpegURL = directory.appendingPathComponent("Preview.jpg")
    // Distinct fixture bytes test transfer fidelity without requiring a supported camera.
    let rawBytes = Data([0x52, 0x41, 0x57, 0x00, 0xff])
    try rawBytes.write(to: rawURL)
    try Data([0xff, 0xd8, 0xff]).write(to: jpegURL)
    let provider = NSItemProvider(object: jpegURL as NSURL)
    provider.registerFileRepresentation(
      forTypeIdentifier: UTType.fujifilmRAW.identifier, fileOptions: [], visibility: .all
    ) { completion in
      completion(rawURL, false, nil)
      return nil
    }

    let dropped = try await PhotoDrop.receive([provider])
    defer { dropped.photo.removeTemporaryCopy() }
    XCTAssertNotNil(dropped.photo.temporaryDirectory)
    XCTAssertEqual(dropped.photo.url.pathExtension.lowercased(), "raf")
    XCTAssertEqual(try Data(contentsOf: dropped.photo.url), rawBytes)
    XCTAssertEqual(dropped.ignoredCount, 0)
  }
}
