import Accelerate
import Flutter
import MobileCoreServices
import Photos

final class RemoteImageRequest: ImageRequest {
  var task: URLSessionDataTask?
  let id: Int64

  init(id: Int64, completion: @escaping @Sendable (Result<[String: Int64]?, any Error>) -> Void) {
    self.id = id
    super.init(completion: completion)
  }

  override func cancel() {
    super.cancel()
    task?.cancel()
  }
}

class RemoteImageApiImpl: NSObject, RemoteImageApi {
  private static let registry = RequestRegistry<RemoteImageRequest>()
  private static let maxTlsRetries = 1
  private static let rgbaFormat = vImage_CGImageFormat(
    bitsPerComponent: 8,
    bitsPerPixel: 32,
    colorSpace: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
    renderingIntent: .perceptual
  )!
  private static let decodeOptions = [
    kCGImageSourceShouldCache: false,
    kCGImageSourceShouldCacheImmediately: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceCreateThumbnailFromImageAlways: true
  ] as CFDictionary

  func requestImage(url: String, headers: [String: String], requestId: Int64, preferEncoded: Bool, completion: @escaping (Result<[String : Int64]?, any Error>) -> Void) {
    let request = RemoteImageRequest(id: requestId, completion: completion)
    Self.registry.add(requestId: requestId, request: request)
    Self.startRequest(
      request: request,
      url: url,
      headers: headers,
      preferEncoded: preferEncoded,
      retryCount: 0
    )
  }

  private static func startRequest(
    request: RemoteImageRequest,
    url: String,
    headers: [String: String],
    preferEncoded: Bool,
    retryCount: Int
  ) {
    if request.isCancelled {
      return
    }

    var urlRequest = URLRequest(url: URL(string: url)!)
    urlRequest.cachePolicy = .returnCacheDataElseLoad
    for (key, value) in headers {
      urlRequest.setValue(value, forHTTPHeaderField: key)
    }

    let task = URLSessionManager.shared.session.dataTask(with: urlRequest) { data, response, error in
      if let error = error, retryCount < maxTlsRetries, isTlsError(error), !request.isCancelled {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) {
          startRequest(
            request: request,
            url: url,
            headers: headers,
            preferEncoded: preferEncoded,
            retryCount: retryCount + 1
          )
        }
        return
      }

      handleCompletion(request: request, encoded: preferEncoded, data: data, response: response, error: error)
    }

    request.task = task
    task.resume()
  }

  private static func isTlsError(_ error: Error) -> Bool {
    let nsError = error as NSError
    guard nsError.domain == NSURLErrorDomain else {
      return false
    }
    return nsError.code == NSURLErrorSecureConnectionFailed
      || nsError.code == NSURLErrorServerCertificateUntrusted
      || nsError.code == NSURLErrorClientCertificateRejected
  }

  private static func handleCompletion(request: RemoteImageRequest, encoded: Bool, data: Data?, response: URLResponse?, error: Error?) {
    if request.isCancelled {
      return request.completion(ImageProcessing.cancelledResult)
    }

    if let error = error {
      registry.remove(requestId: request.id)
      return request.completion(.failure(error))
    }

    guard let data = data else {
      registry.remove(requestId: request.id)
      return request.completion(.failure(PigeonError(code: "", message: "No data received", details: nil)))
    }

    if encoded {
      let length = data.count
      let pointer = malloc(length)!
      data.copyBytes(to: pointer.assumingMemoryBound(to: UInt8.self), count: length)

      if request.isCancelled {
        free(pointer)
        return request.completion(ImageProcessing.cancelledResult)
      }

      registry.remove(requestId: request.id)
      return request.completion(
        .success([
          "pointer": Int64(Int(bitPattern: pointer)),
          "length": Int64(length),
        ]))
    }

    ImageProcessing.queue.addOperation {
      if request.isCancelled {
        return request.completion(ImageProcessing.cancelledResult)
      }

      guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
            let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, decodeOptions) else {
        registry.remove(requestId: request.id)
        return request.completion(.failure(PigeonError(code: "", message: "Failed to decode image for request", details: nil)))
      }

      if request.isCancelled {
        return request.completion(ImageProcessing.cancelledResult)
      }

      do {
        let buffer = try vImage_Buffer(cgImage: cgImage, format: rgbaFormat)

        if request.isCancelled {
          buffer.free()
          return request.completion(ImageProcessing.cancelledResult)
        }

        registry.remove(requestId: request.id)
        return request.completion(
                 .success([
                   "pointer": Int64(Int(bitPattern: buffer.data)),
                   "width": Int64(buffer.width),
                   "height": Int64(buffer.height),
                   "rowBytes": Int64(buffer.rowBytes),
                 ]))
      } catch {
        registry.remove(requestId: request.id)
        return request.completion(.failure(PigeonError(code: "", message: "Failed to convert image for request: \(error)", details: nil)))
      }
    }
  }

  func cancelRequest(requestId: Int64) throws {
    Self.registry.remove(requestId: requestId)?.cancel()
  }

  func clearCache(completion: @escaping (Result<Int64, any Error>) -> Void) {
    Task {
      let cache = URLSessionManager.shared.session.configuration.urlCache!
      let cacheSize = Int64(cache.currentDiskUsage)
      cache.removeAllCachedResponses()
      completion(.success(cacheSize))
    }
  }
}
