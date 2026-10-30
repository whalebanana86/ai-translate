import CoreGraphics
import CoreText
import Foundation

/// 테스트용 텍스트 이미지. 기본은 흰 배경에 검은 글자를 그린다. 위치는 왼쪽 위 원점 픽셀 좌표(글자 윗부분 기준)로 받는다.
enum TextImage {
    struct Line {
        var text: String
        var x: CGFloat
        var top: CGFloat
        var size: CGFloat = 28
    }

    static func render(
        _ lines: [Line], width: Int = 900, height: Int = 400,
        background: CGColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        foreground: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    ) -> CGImage? {
        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for line in lines {
            let font = CTFontCreateWithName("Helvetica" as CFString, line.size, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): foreground,
            ]
            let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: line.text, attributes: attributes))
            // CGContext는 왼쪽 아래 원점이고 기준선 위치에 그리므로 변환한다
            context.textPosition = CGPoint(x: line.x, y: CGFloat(height) - line.top - CTFontGetAscent(font))
            CTLineDraw(ctLine, context)
        }
        return context.makeImage()
    }
}
