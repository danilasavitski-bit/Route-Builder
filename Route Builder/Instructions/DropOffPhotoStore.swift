import UIKit

enum DropOffPhotoStore {
    static func save(_ image: UIImage, stopID: String) throws -> String {
        let folder = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("DropOffs", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safe = stopID.replacingOccurrences(of: "/", with: "_")
        let url = folder.appendingPathComponent(safe).appendingPathExtension("jpg")
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
        return url.path
    }
}
