import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PiecePost

struct PhotoProcessorTests {
    // MARK: 크기·형식

    @Test func landscapeBecomesCenterCropped1200HEIC() async throws {
        // 가로를 3등분해 빨강·초록·파랑. 가운데를 자르면 가운데가 초록이어야 한다.
        let original = try TestImage.jpeg(width: 4000, height: 3000) { x, _ in
            x < 4000 / 3 ? .red : (x < 4000 * 2 / 3 ? .green : .blue)
        }

        let result = try await PhotoProcessor.process(original)

        let photo = try DecodedImage(result.photo)
        #expect(photo.type == UTType.heic.identifier)
        #expect(photo.width == 1200 && photo.height == 1200)
        #expect(photo.color(x: 600, y: 600) == .green)
        // 크롭 영역 x=500…3500 → 빨강은 왼쪽 약 333px, 파랑은 오른쪽 약 333px
        #expect(photo.color(x: 100, y: 600) == .red)
        #expect(photo.color(x: 1100, y: 600) == .blue)
    }

    @Test func thumbnailIs300HEICFromSameCrop() async throws {
        let original = try TestImage.jpeg(width: 4000, height: 3000) { x, _ in
            x < 4000 / 3 ? .red : (x < 4000 * 2 / 3 ? .green : .blue)
        }

        let result = try await PhotoProcessor.process(original)

        let thumbnail = try DecodedImage(result.thumbnail)
        #expect(thumbnail.type == UTType.heic.identifier)
        #expect(thumbnail.width == 300 && thumbnail.height == 300)
        #expect(thumbnail.color(x: 150, y: 150) == .green)
        #expect(thumbnail.color(x: 25, y: 150) == .red)
    }

    @Test func portraitIsCroppedToSquare() async throws {
        let original = try TestImage.jpeg(width: 3000, height: 4000) { _, _ in .green }
        let photo = try DecodedImage(try await PhotoProcessor.process(original).photo)
        #expect(photo.width == 1200 && photo.height == 1200)
    }

    @Test func smallPhotoIsNotUpscaled() async throws {
        let original = try TestImage.jpeg(width: 800, height: 600) { _, _ in .green }

        let result = try await PhotoProcessor.process(original)

        let photo = try DecodedImage(result.photo)
        let thumbnail = try DecodedImage(result.thumbnail)
        #expect(photo.width == 600 && photo.height == 600)
        #expect(thumbnail.width == 300 && thumbnail.height == 300)
    }

    @Test func tinyPhotoKeepsItsSizeForThumbnailToo() async throws {
        let original = try TestImage.jpeg(width: 200, height: 250) { _, _ in .green }
        let result = try await PhotoProcessor.process(original)
        #expect(try DecodedImage(result.photo).width == 200)
        #expect(try DecodedImage(result.thumbnail).width == 200)
    }

    // MARK: 회전

    @Test func appliesExifOrientationBeforeCropping() async throws {
        // 저장된 픽셀은 가로 400×300, 왼쪽 1/4만 빨강. EXIF 6(시계 방향 90° 회전)이면
        // 화면에서는 세로 300×400이고 위쪽 1/4이 빨강이다.
        // 가운데를 자르면(y=50…350) 맨 위 50px만 빨강이고 나머지는 파랑.
        let original = try TestImage.jpeg(width: 400, height: 300, orientation: 6) { x, _ in
            x < 100 ? .red : .blue
        }

        let photo = try DecodedImage(try await PhotoProcessor.process(original).photo)

        #expect(photo.width == 300 && photo.height == 300)
        #expect(photo.color(x: 150, y: 20) == .red)
        #expect(photo.color(x: 150, y: 200) == .blue)
        // 회전을 무시했다면 왼쪽 세로 띠가 빨강이 된다.
        #expect(photo.color(x: 20, y: 200) == .blue)
    }

    // MARK: 메타데이터

    @Test func stripsLocationAndCameraMetadata() async throws {
        let original = try TestImage.jpeg(
            width: 1600, height: 1600,
            extraProperties: [
                kCGImagePropertyGPSDictionary: [
                    kCGImagePropertyGPSLatitude: 37.5665,
                    kCGImagePropertyGPSLatitudeRef: "N",
                    kCGImagePropertyGPSLongitude: 126.978,
                    kCGImagePropertyGPSLongitudeRef: "E",
                ],
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "TestCamera"],
            ]
        ) { _, _ in .green }
        // 입력에 실제로 들어갔는지 먼저 확인
        #expect(try DecodedImage(original).properties[kCGImagePropertyGPSDictionary] != nil)

        let result = try await PhotoProcessor.process(original)

        for data in [result.photo, result.thumbnail] {
            let properties = try DecodedImage(data).properties
            #expect(properties[kCGImagePropertyGPSDictionary] == nil)
            let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            #expect(tiff?[kCGImagePropertyTIFFMake] == nil)
        }
    }

    // MARK: 오류

    @Test func rejectsNonImageData() async {
        await #expect(throws: PhotoProcessorError.unreadableImage) {
            try await PhotoProcessor.process(Data("not an image".utf8))
        }
        await #expect(throws: PhotoProcessorError.unreadableImage) {
            try await PhotoProcessor.process(Data())
        }
    }
}

// MARK: - 테스트 도우미

private enum TestColor: Equatable {
    case red, green, blue, other

    var rgb: (UInt8, UInt8, UInt8) {
        switch self {
        case .red: (255, 0, 0)
        case .green: (0, 255, 0)
        case .blue: (0, 0, 255)
        case .other: (128, 128, 128)
        }
    }

    /// 손실 압축 오차를 감안해 가장 강한 채널로 판정한다.
    init(r: UInt8, g: UInt8, b: UInt8) {
        let high: UInt8 = 180, low: UInt8 = 90
        switch (r, g, b) {
        case let (r, g, b) where r > high && g < low && b < low: self = .red
        case let (r, g, b) where g > high && r < low && b < low: self = .green
        case let (r, g, b) where b > high && r < low && g < low: self = .blue
        default: self = .other
        }
    }
}

private enum TestImage {
    static func jpeg(
        width: Int,
        height: Int,
        orientation: Int = 1,
        extraProperties: [CFString: Any] = [:],
        color: (Int, Int) -> TestColor
    ) throws -> Data {
        let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        // 세로 줄 단위로 칠한다(테스트 이미지는 x로만 색이 바뀜). CGContext 원점은 왼쪽 아래.
        for x in 0..<width {
            let (r, g, b) = color(x, 0).rgb
            context.setFillColor(CGColor(
                red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1
            ))
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        let image = try #require(context.makeImage())

        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ))
        var properties = extraProperties
        properties[kCGImagePropertyOrientation] = orientation
        properties[kCGImageDestinationLossyCompressionQuality] = 1.0
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }
}

private struct DecodedImage {
    let type: String
    let width: Int
    let height: Int
    let properties: [CFString: Any]
    private let pixels: [UInt8]

    init(_ data: Data) throws {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        type = try #require(CGImageSourceGetType(source) as String?)
        properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let width = image.width
        let height = image.height
        self.width = width
        self.height = height

        // 위쪽이 y=0이 되도록 sRGB RGBA 버퍼에 그린다.
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try buffer.withUnsafeMutableBytes { raw in
            let context = try #require(CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        pixels = buffer
    }

    /// (x, y)는 이미지 왼쪽 위 기준.
    func color(x: Int, y: Int) -> TestColor {
        // CGContext 메모리 첫 줄이 이미지 맨 위 줄이다.
        let offset = (y * width + x) * 4
        return TestColor(r: pixels[offset], g: pixels[offset + 1], b: pixels[offset + 2])
    }
}
