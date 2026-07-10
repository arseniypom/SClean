//
//  ReceiptInsightServiceTests.swift
//  SCleanTests
//
//  Tests the pure receipt scoring heuristic (no Vision/Photos needed).
//

import Testing
import Foundation
@testable import SClean

struct ReceiptInsightServiceTests {

    private var threshold: Double { ReceiptInsightService.receiptScoreThreshold }

    @Test func score_realReceiptWithKeywordAndAmount_isReceipt() {
        let text = "receipt subtotal 12.50 total 14.99 vat 2.49 thank you for shopping"
        #expect(ReceiptInsightService.receiptScore(for: text) >= threshold)
    }

    @Test func score_amountDateMediumKeyword_reachesThresholdWithoutStrongKeyword() {
        // total(0.8) + monetary(1.6) + date(0.7) + length>40(0.3) = 3.4
        let text = "total 1234.56 paid by card on 12/31/2024 thank you for visiting"
        #expect(ReceiptInsightService.receiptScore(for: text) >= threshold)
    }

    @Test func score_genericDatedScreenshotWithoutMoney_isGatedToZero() {
        // Has a date and bare numbers but no receipt keyword and no monetary amount.
        let text = "meeting notes for project 3 on 12/31 see page 5 for details"
        #expect(ReceiptInsightService.receiptScore(for: text) == 0)
    }

    @Test func score_emptyText_isZero() {
        #expect(ReceiptInsightService.receiptScore(for: "") == 0)
    }

    @Test func score_russianReceipt_isReceipt() {
        let text = "чек касса итог 1 000,00 руб оплата картой спасибо за покупку"
        #expect(ReceiptInsightService.receiptScore(for: text) >= threshold)
    }

    @Test func monetary_currencySymbolPasses_bareCountDoesNot() {
        // "$500" passes the monetary gate (score > 0); "page 3 of 5" does not (== 0).
        #expect(ReceiptInsightService.receiptScore(for: "$500 dinner") > 0)
        #expect(ReceiptInsightService.receiptScore(for: "page 3 of 5 items") == 0)
    }

    @Test func monetary_timeOfDayIsNotTreatedAsAmount() {
        // "12:45" must not satisfy the cents pattern (colon is not a decimal separator).
        #expect(ReceiptInsightService.receiptScore(for: "call me at 12:45 tomorrow please") == 0)
    }
}
