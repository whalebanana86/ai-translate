import Testing

@testable import TranslateCore

struct LanguageDetectionTests {
    // 한국어 유튜브 화면의 댓글 머리줄·버튼 (실제 화면 OCR 결과)
    @Test(arguments: [
        "1년 전", "@AbdulHafeez-my3pd 1년 전", "@ JetpackGamer456 6년 전(수정됨)", "답글 457개 V", "자세히 알아보기",
        "AI 기능이 추가되었습니다", "정말 좋은 노래네요",
    ])
    func takesKoreanTextAsKorean(text: String) {
        #expect(LanguageDetection.isWritten(text, in: .korean))
    }

    @Test(arguments: [
        "This song never gets old.", "Very nice person.", "gREAT",
        // 판별기는 한국어로 보지만 영어가 절반이라 번역한다
        "정말 좋은 노래네요 I love it", "좋아요 Love this song so much", "Great song! 노래 좋네요",
        "料金プランを選択してください", "我们今天去公园",
        // 아이디만 있으면 판단할 글이 없다
        "@MusicLover88",
    ])
    func translatesTextNotWrittenInKorean(text: String) {
        #expect(!LanguageDetection.isWritten(text, in: .korean))
    }

    @Test(arguments: [
        ("料金プランを選択してください", TargetLanguage.japanese), ("ログイン", .japanese), ("设置已保存", .simplifiedChinese),
        ("設定已儲存", .traditionalChinese), ("This song never gets old.", .english),
        ("Me gusta mucho esta canción", .spanish), ("C'est vraiment une belle chanson", .french),
        ("Das ist ein wirklich schönes Lied", .german),
    ])
    func takesTextInTargetLanguage(text: String, language: TargetLanguage) {
        #expect(LanguageDetection.isWritten(text, in: language))
    }

    @Test(arguments: [
        ("我们今天去公园", TargetLanguage.japanese), ("답글 4개", .japanese), ("設定已儲存", .simplifiedChinese),
        ("设置已保存", .traditionalChinese), ("料金プランを選択してください", .simplifiedChinese),
        ("Me gusta mucho esta canción", .english), ("Das ist ein wirklich schönes Lied", .french),
        ("This song never gets old.", .german), ("자세히 알아보기", .english),
    ])
    func translatesTextInOtherLanguages(text: String, language: TargetLanguage) {
        #expect(!LanguageDetection.isWritten(text, in: language))
    }
}
