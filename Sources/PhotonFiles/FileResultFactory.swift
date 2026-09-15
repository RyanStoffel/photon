import Foundation
import UniformTypeIdentifiers

/// Builds a `FileResult` from a path Spotlight/`mdfind` returned.
enum FileResultFactory: Sendable {
  static func file(at path: String) -> FileResult? {
    let resolved = PathFormatter.resolvingFirmlink(path)
    guard !resolved.isEmpty else {
      return nil
    }
    let url = URL(fileURLWithPath: resolved)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDirectory) else {
      return nil
    }
    let values = try? url.resourceValues(forKeys: [
      .localizedNameKey,
      .nameKey,
      .fileSizeKey,
      .creationDateKey,
      .contentModificationDateKey,
      .contentAccessDateKey,
      .contentTypeKey,
      .localizedTypeDescriptionKey,
      .isApplicationKey,
      .isDirectoryKey
    ])
    let fileName = values?.name ?? url.lastPathComponent
    let displayName = values?.localizedName ?? fileName
    let isApplication = values?.isApplication == true
    let isFolder = !isApplication && (values?.isDirectory == true || isDirectory.boolValue)
    let contentType = values?.contentType?.identifier
    let kind = values?.localizedTypeDescription
      ?? fallbackKind(contentType: contentType, isFolder: isFolder, fileName: fileName)
    return FileResult(
      path: resolved,
      displayName: displayName.isEmpty ? fileName : displayName,
      fileName: fileName,
      kind: kind,
      contentType: contentType,
      isFolder: isFolder,
      isApplication: isApplication,
      size: fileSize(values, isFolder: isFolder),
      created: values?.creationDate,
      modified: values?.contentModificationDate,
      lastUsed: values?.contentAccessDate
    )
  }

  static func fallbackKind(contentType: String?, isFolder: Bool, fileName: String) -> String {
    if isFolder {
      return "Folder"
    }
    if let contentType, let type = UTType(contentType), let description = type.localizedDescription {
      return description
    }
    let ext = (fileName as NSString).pathExtension
    return ext.isEmpty ? "Document" : ext.uppercased() + " file"
  }

  private static func fileSize(_ values: URLResourceValues?, isFolder: Bool) -> Int64? {
    guard !isFolder, let size = values?.fileSize else {
      return nil
    }
    return Int64(size)
  }
}
