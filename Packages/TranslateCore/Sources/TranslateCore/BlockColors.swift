import CoreGraphics
import Foundation

/// sRGB 색. 성분은 0...1
public struct SRGBColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let black = SRGBColor(red: 0, green: 0, blue: 0)
    public static let white = SRGBColor(red: 1, green: 1, blue: 1)

    /// 상대 휘도 (WCAG)
    var luminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// 대비 비율 (1...21, WCAG)
    func contrast(with other: SRGBColor) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }
}

/// 원문 문단의 바탕색과 글자색. 번역을 이 색으로 그려 페이지에 섞여 보이게 한다.
public struct BlockColors: Equatable, Sendable {
    public var background: SRGBColor
    public var text: SRGBColor

    public init(background: SRGBColor, text: SRGBColor) {
        self.background = background
        self.text = text
    }

    /// 색을 뽑지 못했을 때
    public static let plain = BlockColors(background: .white, text: .black)

    /// 문단이 커도 이만큼만 본다
    static let maxSamples = 20_000
    /// 바탕과 이보다 가까운 색만 있으면(0~255 RGB 거리) 글자가 없는 것으로 본다
    static let minimumTextDistance = 40.0
    /// 글자색 후보: 바탕에서 가장 먼 색과의 거리의 이 비율 이상 떨어진 색. 글자 가장자리의 섞인 색을 뺀다
    static let textDistanceRatio = 0.5
    /// 글자색과 바탕의 대비가 이보다 낮으면 잘못 뽑은 것으로 보고 검정·흰색 중 대비가 큰 쪽을 쓴다
    static let minimumContrast = 3.0

    /// `box`(이미지 픽셀 좌표, 왼쪽 위 원점) 안의 색을 본다. 가장 많은 색이 바탕이고, 바탕과 충분히 다른 색 중
    /// 가장 많은 색이 글자다. 이미지는 sRGB로 바꿔 읽는다.
    public static func sample(_ image: CGImage, in box: CGRect) -> BlockColors? {
        let area = box.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !area.isEmpty, let pixels = pixels(of: image, in: area) else { return nil }
        let background = dominant(pixels)
        let distances = pixels.map { $0.distance(to: background) }
        let farthest = distances.max() ?? 0
        var text: SRGBColor?
        if farthest >= minimumTextDistance {
            text = dominant(zip(pixels, distances).filter { $0.1 >= farthest * textDistanceRatio }.map(\.0)).color
        }
        let backgroundColor = background.color
        if let candidate = text, candidate.contrast(with: backgroundColor) >= minimumContrast {
            return BlockColors(background: backgroundColor, text: candidate)
        }
        let readable =
            SRGBColor.black.contrast(with: backgroundColor) >= SRGBColor.white.contrast(with: backgroundColor)
        return BlockColors(background: backgroundColor, text: readable ? .black : .white)
    }

    private struct Pixel {
        var red: Double
        var green: Double
        var blue: Double

        var color: SRGBColor { SRGBColor(red: red / 255, green: green / 255, blue: blue / 255) }

        /// 성분마다 16단계로 묶은 칸
        var bucket: Int { (Int(red) >> 4) << 8 | (Int(green) >> 4) << 4 | Int(blue) >> 4 }

        func distance(to other: Pixel) -> Double {
            ((red - other.red) * (red - other.red) + (green - other.green) * (green - other.green)
                + (blue - other.blue) * (blue - other.blue)).squareRoot()
        }
    }

    /// 가장 많은 칸에 든 색들의 평균
    private static func dominant(_ pixels: [Pixel]) -> Pixel {
        var counts: [Int: Int] = [:]
        for pixel in pixels {
            counts[pixel.bucket, default: 0] += 1
        }
        let bucket = counts.max { $0.value < $1.value }?.key
        let members = pixels.filter { $0.bucket == bucket }
        let count = Double(max(members.count, 1))
        return Pixel(
            red: members.reduce(0) { $0 + $1.red } / count, green: members.reduce(0) { $0 + $1.green } / count,
            blue: members.reduce(0) { $0 + $1.blue } / count)
    }

    private static func pixels(of image: CGImage, in area: CGRect) -> [Pixel]? {
        guard
            let cropped = image.cropping(to: area),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: cropped.width, height: cropped.height, bitsPerComponent: 8,
                bytesPerRow: cropped.width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let (width, height) = (cropped.width, cropped.height)
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let step = max(1, Int((Double(width * height) / Double(maxSamples)).squareRoot().rounded(.up)))
        var pixels: [Pixel] = []
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let offset = (y * width + x) * 4
                pixels.append(
                    Pixel(red: Double(bytes[offset]), green: Double(bytes[offset + 1]), blue: Double(bytes[offset + 2]))
                )
            }
        }
        return pixels
    }
}
