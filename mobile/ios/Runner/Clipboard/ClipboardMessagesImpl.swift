import Foundation
import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

class ClipboardMessagesImpl: NSObject, NativeClipboardApi {
    
    override init() {
        super.init()
    }
    
    func copyPhotosToClipboard(filePaths: [String]) throws -> ClipboardResult {
        if filePaths.isEmpty {
            return ClipboardResult(success: false, error: "No file paths provided", photoCount: 0)
        }
        
        let pasteboard = UIPasteboard.general
        pasteboard.string = ""
        pasteboard.images = nil
        pasteboard.urls = nil
        
        var imageItems: [UIImage] = []
        var dataItems: [[String: Any]] = []
        
        for filePath in filePaths {
            // Try to load as UIImage for third-party paste targets (e.g., Telegram)
            if let image = UIImage(contentsOfFile: filePath) {
                imageItems.append(image)
                // Prefer JPEG representation for broader compatibility
                if let jpegData = image.jpegData(compressionQuality: 0.95) {
                    if #available(iOS 14.0, *) {
                        dataItems.append([UTType.jpeg.identifier: jpegData])
                    } else {
                        dataItems.append([(kUTTypeJPEG as String): jpegData])
                    }
                } else if let pngData = image.pngData() {
                    if #available(iOS 14.0, *) {
                        dataItems.append([UTType.png.identifier: pngData])
                    } else {
                        dataItems.append([(kUTTypePNG as String): pngData])
                    }
                }
            }
        }
        
        // Provide actual images for apps that expect images on the pasteboard
        if !imageItems.isEmpty {
            pasteboard.images = imageItems
        }
        // Also provide typed data items for apps that read raw data representations
        if !dataItems.isEmpty {
            pasteboard.setItems(dataItems, options: [.localOnly: true])
        }
        
        return ClipboardResult(success: true, error: nil, photoCount: Int64(imageItems.count))
    }
    
    func getPhotosFromClipboard() throws -> [String] {
        let pasteboard = UIPasteboard.general
        var filePaths: [String] = []
        
        if let urls = pasteboard.urls, !urls.isEmpty {
            for url in urls {
                let ext = url.pathExtension.lowercased()
                if ["jpg","jpeg","png","gif","heic","heif","webp","bmp","dng"].contains(ext) {
                    filePaths.append(url.path)
                }
            }
        }
        // If there are no accessible URLs but images exist, export images to temp files
        if filePaths.isEmpty, let images = pasteboard.images, !images.isEmpty {
            let tmpDir = NSTemporaryDirectory()
            for (idx, image) in images.enumerated() {
                // Save as JPEG for compatibility
                if let data = image.jpegData(compressionQuality: 0.95) {
                    let filename = "clipboard_\(Int(Date().timeIntervalSince1970))_\(idx).jpg"
                    let fullPath = (tmpDir as NSString).appendingPathComponent(filename)
                    do {
                        try data.write(to: URL(fileURLWithPath: fullPath), options: .atomic)
                        filePaths.append(fullPath)
                    } catch {
                        // skip on error
                    }
                }
            }
        }
        
        return filePaths
    }
    
    func hasPhotosInClipboard() throws -> Bool {
        let pasteboard = UIPasteboard.general
        let hasImages = pasteboard.images?.isEmpty == false
        let hasFileURLs = pasteboard.urls?.isEmpty == false
        
        return hasImages || hasFileURLs
    }
    
    func getClipboardPhotoMetadata() throws -> [ClipboardPhoto] {
        let pasteboard = UIPasteboard.general
        var photos: [ClipboardPhoto] = []
        
        if let urls = pasteboard.urls, !urls.isEmpty {
            for url in urls {
                let ext = url.pathExtension.lowercased()
                if ["jpg","jpeg","png","gif","heic","heif","webp","bmp","dng"].contains(ext) {
                    
                    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                    let fileSize = attributes?[.size] as? Int64 ?? 0
                    let mimeType = getMimeType(for: url.pathExtension)
                    
                    let photo = ClipboardPhoto(
                        filePath: url.path,
                        fileName: url.lastPathComponent,
                        fileSize: fileSize,
                        mimeType: mimeType
                    )
                    photos.append(photo)
                }
            }
        }
        
        return photos
    }
    
    private func getMimeType(for fileExtension: String) -> String {
        let ext = fileExtension.lowercased()
        switch ext {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "heic", "heif":
            return "image/heif"
        case "webp":
            return "image/webp"
        case "bmp":
            return "image/bmp"
        case "dng":
            return "image/x-adobe-dng"
        default:
            return "image/*"
        }
    }
    
    func clearClipboard() throws -> Bool {
        let pasteboard = UIPasteboard.general
        
        pasteboard.string = ""
        pasteboard.images = nil
        pasteboard.urls = nil
        
        return true
    }
}
