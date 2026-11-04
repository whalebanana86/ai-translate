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
        var font = "Helvetica"
        /// 링크처럼 글 아래 밑줄
        var underline = false
    }

    /// 페이지 위에 떠서 아래 글을 가리는 상자(드롭다운 메뉴 등)
    struct Popup {
        /// 왼쪽 위 원점 픽셀 좌표
        var rect: CGRect
        var lines: [Line]
        var fill = CGColor(gray: 0.93, alpha: 1)
    }

    static func render(
        _ lines: [Line], popups: [Popup] = [], width: Int = 900, height: Int = 400,
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
        draw(lines, in: context, height: height, foreground: foreground)
        for popup in popups {
            // CGContext는 왼쪽 아래 원점이다
            context.setFillColor(popup.fill)
            context.fill(
                CGRect(
                    x: popup.rect.minX, y: CGFloat(height) - popup.rect.maxY, width: popup.rect.width,
                    height: popup.rect.height))
            draw(popup.lines, in: context, height: height, foreground: foreground)
        }
        return context.makeImage()
    }

    private static func draw(_ lines: [Line], in context: CGContext, height: Int, foreground: CGColor) {
        for line in lines {
            let font = CTFontCreateWithName(line.font as CFString, line.size, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): foreground,
            ]
            let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: line.text, attributes: attributes))
            // CGContext는 왼쪽 아래 원점이고 기준선 위치에 그리므로 변환한다
            let baseline = CGFloat(height) - line.top - CTFontGetAscent(font)
            context.textPosition = CGPoint(x: line.x, y: baseline)
            CTLineDraw(ctLine, context)
            if line.underline {
                let width = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
                context.setFillColor(foreground)
                context.fill(
                    CGRect(x: line.x, y: baseline - CTFontGetDescent(font), width: width, height: line.size * 0.08))
            }
        }
    }
}
