//
//  ChatMemeInsightServiceTests.swift
//  SCleanTests
//
//  Tests the pure chat/meme text-signal scoring (no Vision/Photos needed).
//

import Testing
import Foundation
@testable import SClean

struct ChatMemeInsightServiceTests {

    @Test func textScore_emptyText_isZero() {
        #expect(ChatMemeInsightService.chatMemeTextScore(text: "", lineCount: 0) == 0)
    }

    @Test func textScore_englishChat_scoresStrongKeyword() {
        // "message" (2.0) + "delivered" (1.1) + lines>=4 (0.3) + length>=60 (0.3)
        let text = "new message from alex delivered yesterday how are you doing today friend"
        #expect(ChatMemeInsightService.chatMemeTextScore(text: text, lineCount: 4) >= 2.0)
    }

    @Test func textScore_russianChat_scoresViaRussianKeywords() {
        // Russian messenger surface text should now contribute (was English-only before).
        let text = "переслано из телеграм печатает был вчера в сети"
        #expect(ChatMemeInsightService.chatMemeTextScore(text: text, lineCount: 2) >= 2.0)
    }

    @Test func textScore_laughterAndLink_contribute() {
        let withLaughter = ChatMemeInsightService.chatMemeTextScore(text: "hahaha that is so funny", lineCount: 1)
        let plain = ChatMemeInsightService.chatMemeTextScore(text: "that is so funny", lineCount: 1)
        #expect(withLaughter > plain)
    }

    @Test func textScore_plainPhotoCaption_staysLow() {
        // No chat keywords, no links, no laughter — should not look like a chat screenshot.
        let text = "sunset over the mountains"
        #expect(ChatMemeInsightService.chatMemeTextScore(text: text, lineCount: 1) == 0)
    }
}
