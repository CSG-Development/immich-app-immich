import Foundation
import UIKit
import MobileCoreServices

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
        var fileURLs: [URL] = []
        
        for filePath in filePaths {
            if let image = UIImage(contentsOfFile: filePath) {
                imageItems.append(image)
            }
            
            let fileURL = URL(fileURLWithPath: filePath)
            if FileManager.default.fileExists(atPath: filePath) {
                fileURLs.append(fileURL)
            }
        }
        
        if !imageItems.isEmpty {
            pasteboard.images = imageItems
        }
        
        if !fileURLs.isEmpty {
            pasteboard.urls = fileURLs
        }
        
        return ClipboardResult(success: true, error: nil, photoCount: Int64(imageItems.count))
    }
    
    func getPhotosFromClipboard() throws -> [String] {
        let pasteboard = UIPasteboard.general
        var filePaths: [String] = []
        
        if let images = pasteboard.images, !images.isEmpty {
            for (index, image) in images.enumerated() {
                if let data = image.jpegData(compressionQuality: 0.8) {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard_image_\(index).jpg")
                    try? data.write(to: tempURL)
                    filePaths.append(tempURL.path)
                }
            }
        }
        
        if let urls = pasteboard.urls, !urls.isEmpty {
            for url in urls {
                if url.pathExtension.lowercased().contains("jpg") || 
                   url.pathExtension.lowercased().contains("jpeg") ||
                   url.pathExtension.lowercased().contains("png") ||
                   url.pathExtension.lowercased().contains("gif") ||
                   url.pathExtension.lowercased().contains("heic") {
                    filePaths.append(url.path)
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
        
        if let images = pasteboard.images, !images.isEmpty {
            for (index, image) in images.enumerated() {
                if let data = image.jpegData(compressionQuality: 0.8) {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard_image_\(index).jpg")
                    try? data.write(to: tempURL)
                    
                    let photo = ClipboardPhoto(
                        filePath: tempURL.path,
                        fileName: "clipboard_image_\(index).jpg",
                        fileSize: Int64(data.count),
                        mimeType: "image/jpeg"
                    )
                    photos.append(photo)
                }
            }
        }
        
        if let urls = pasteboard.urls, !urls.isEmpty {
            for url in urls {
                if url.pathExtension.lowercased().contains("jpg") || 
                   url.pathExtension.lowercased().contains("jpeg") ||
                   url.pathExtension.lowercased().contains("png") ||
                   url.pathExtension.lowercased().contains("gif") ||
                   url.pathExtension.lowercased().contains("heic") {
                    
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
