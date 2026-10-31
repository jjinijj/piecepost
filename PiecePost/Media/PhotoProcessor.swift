import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 저장·업로드할 사진 한 쌍. 둘 다 HEIC.
nonisolated struct ProcessedPhoto: Sendable, Equatable {
    /// 1:1, 한 변 최대 1200px
    let photo: Data
    /// 1:1, 한 변 최대 300px
    let thumbnail: Data
}

nonisolated enum PhotoProcessorError: Error, Equatable {
    case unreadableImage
    case encodingFailed
}

/// docs/system-design.md 4장 순서대로 사진을 만든다.
/// 원본 해상도에서 1:1로 한 번 자르고, 1200px로 한 번 줄이고, HEIC 0.8로 한 번 인코딩한다.
/// 썸네일은 인코딩 전 1200px 이미지에서 만든다.
///
/// - 1200px보다 작은 사진은 키우지 않는다.
/// - 새로 인코딩하므로 위치·촬영 정보 같은 메타데이터와 HDR 정보는 남지 않는다.
nonisolated enum PhotoProcessor {
    static let photoMaxPixel = 1200
    static let thumbnailMaxPixel = 300
    static let compressionQuality = 0.8

    /// 큰 사진은 메모리·시간이 많이 들어 메인 스레드 밖에서 처리한다.
    @concurrent
    static func process(_ original: Data) async throws -> ProcessedPhoto {
        try processSynchronously(original)
    }

    static func processSynchronously(_ original: Data) throws -> ProcessedPhoto {
        let oriented = try decodeOriented(original)
        let square = try cropCenterSquare(oriented)
        let photoImage = try resize(square, to: min(square.width, photoMaxPixel))
        let thumbnailImage = try resize(photoImage, to: min(photoImage.width, thumbnailMaxPixel))
        return ProcessedPhoto(
            photo: try encodeHEIC(photoImage),
            thumbnail: try encodeHEIC(thumbnailImage)
        )
    }

    /// 원본 해상도로 읽되 EXIF 회전값을 반영한다.
    private static func decodeOriented(_ data: Data) throws -> CGImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard
            let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else {
            throw PhotoProcessorError.unreadableImage
        }

        // 최대 크기를 원본 긴 변으로 주면 축소 없이 회전만 적용된 원본 해상도 이미지가 나온다.
        let decodeOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, decodeOptions) else {
            throw PhotoProcessorError.unreadableImage
        }
        return image
    }

    private static func cropCenterSquare(_ image: CGImage) throws -> CGImage {
        let side = min(image.width, image.height)
        let rect = CGRect(
            x: (image.width - side) / 2,
            y: (image.height - side) / 2,
            width: side,
            height: side
        )
        guard let cropped = image.cropping(to: rect) else {
            throw PhotoProcessorError.unreadableImage
        }
        return cropped
    }

    private static func resize(_ image: CGImage, to side: Int) throws -> CGImage {
        if image.width == side && image.height == side { return image }

        guard let context = makeContext(side: side, preferredColorSpace: image.colorSpace) else {
            throw PhotoProcessorError.encodingFailed
        }
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        // 투명 영역이 있는 이미지는 검게 나오지 않도록 흰 바탕을 깐다.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.interpolationQuality = .high
        context.draw(image, in: rect)

        guard let resized = context.makeImage() else {
            throw PhotoProcessorError.encodingFailed
        }
        return resized
    }

    /// 원본 색 공간(예: Display P3)을 유지한다. 그 색 공간으로 그릴 수 없으면 sRGB로 그린다.
    private static func makeContext(side: Int, preferredColorSpace: CGColorSpace?) -> CGContext? {
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
        if let preferredColorSpace, preferredColorSpace.model == .rgb,
           let context = CGContext(
               data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
               space: preferredColorSpace, bitmapInfo: bitmapInfo
           ) {
            return context
        }
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: sRGB, bitmapInfo: bitmapInfo
        )
    }

    private static func encodeHEIC(_ image: CGImage) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.heic.identifier as CFString, 1, nil
        ) else {
            throw PhotoProcessorError.encodingFailed
        }
        let options = [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoProcessorError.encodingFailed
        }
        return output as Data
    }
}
