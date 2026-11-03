import Testing

@testable import TranslateCore

struct AIMisreadingTests {
    // SF·Helvetica·Arial 화면에서 Vision이 "AI"를 읽은 그대로 (스크래치 측정, TASK-066)
    @Test(arguments: [
        ("Al", "AI"), ("Al tools", "AI tools"), ("New Al tools are here", "New AI tools are here"),
        ("Generative Al for everyone", "Generative AI for everyone"),
        ("OpenAl and Google Al", "OpenAI and Google AI"), ("xAl and GenAl", "xAI and GenAI"),
        ("OpenAl's new model", "OpenAI's new model"),
        ("Al 모델이 새로 나왔어요", "AI 모델이 새로 나왔어요"), ("Al가 바꾼 것들", "AI가 바꾼 것들"), ("Alの進化が速い", "AIの進化が速い"),
        ("Al-powered search", "AI-powered search"), ("Follow #Al now", "Follow #AI now"),
        ("Al this week:\nMonday: GPT-6.1 Terra", "AI this week:\nMonday: GPT-6.1 Terra"),
        // 단어마다 대문자로 쓰는 제목: 대문자 다음 단어가 이름 표시가 아니다
        ("Google Launches New Al Model", "Google Launches New AI Model"),
        ("Al Agents Are Coming", "AI Agents Are Coming"),
    ])
    func correctsMisreadAI(text: String, expected: String) {
        #expect(AIMisreading.corrected(text) == expected)
    }

    @Test(arguments: [
        // 사람·단체 이름
        "Al Gore gave a talk on climate", "I love Al Pacino movies", "Vice President Al Gore spoke",
        "Weird Al Yankovic released a song", "Al Jazeera reported the news", "Al-Nassr won the match",
        // "Al"이 보통 낱말인 언어
        "Al final del día, todos se fueron", "Al principio no lo entendí", "Al mattino andiamo al mare", "Al final",
        "Al menos",
        // 알루미늄, 아이디, "Al"로 시작하는 단어, 이미 맞게 읽은 글
        "Aluminium (Al) is light", "Al2O3 coating", "follow @Al for updates", "Also, Albert said alright",
        "AI is everywhere", "ai and Ai",
    ])
    func keepsRealAl(text: String) {
        #expect(AIMisreading.corrected(text) == text)
    }
}
