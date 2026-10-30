import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers
import TranslateCore

/// 받은 로컬 모델을 MLX로 불러와 글을 생성한다. 다운로더는 쓰지 않고 받은 폴더에서 바로 읽는다.
///
/// 빌드에는 Metal 툴체인이 필요하다 (Xcode 26: `xcodebuild -downloadComponent MetalToolchain`).
final class LocalTextGenerator: TextGenerating, Sendable {
    private let container: ModelContainer

    private init(container: ModelContainer) {
        self.container = container
    }

    static func load(directory: URL) async throws -> any TextGenerating {
        let generator = LocalTextGenerator(
            container: try await loadModelContainer(from: directory, using: TokenizerLoader()))
        // 첫 생성은 GPU 커널 준비로 4초 넘게 걸린다 (측정, TASK-019). 불러올 때 짧게 한 번 돌려 둔다
        _ = try await generator.generate(prompt: HyMTPrompt.prompt(for: "Hello", target: "Korean"), maxTokens: 4)
        return generator
    }

    func generate(prompt: String, maxTokens: Int) async throws -> String {
        // 프롬프트에 채팅 형식의 특수 토큰이 이미 들어 있으므로 토크나이저가 더 붙이지 않게 한다
        let tokens = await container.perform { context in
            context.tokenizer.encode(text: prompt, addSpecialTokens: false)
        }
        // Hy-MT2 모델 카드 권장 샘플링
        let parameters = GenerateParameters(
            maxTokens: maxTokens, temperature: 0.7, topP: 0.6, topK: 20, repetitionPenalty: 1.05)
        let stream = try await container.generate(input: LMInput(tokens: MLXArray(tokens)), parameters: parameters)
        var output = ""
        for await event in stream {
            try Task.checkCancellation()
            if let chunk = event.chunk {
                output += chunk
            }
        }
        return output
    }
}

/// swift-transformers 토크나이저를 mlx-swift-lm 프로토콜에 연결한다 (mlx-swift-lm의 `MLXHuggingFace` 매크로가 만드는 것과
/// 같은 매핑. 매크로·다운로더 패키지를 들이지 않으려고 직접 둔다)
private struct TokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(upstream: try await AutoTokenizer.from(modelFolder: directory))
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
    }
}
