import Foundation
import Observation
import SwiftData
import SnagKit
import UIKit

/// State for one scanning session: what the camera saw, what we looked up,
/// and the verdict. Designed so pointing the camera is the only required step.
@Observable
final class ScanSession {
    enum Phase: Equatable {
        case idle
        case looking(String)
        case found
        case choosing
        case failed(String)
    }

    var phase: Phase = .idle
    var result: PriceSearchService.Result?
    var candidates: [PriceSearchService.Result] = []
    var scannedCode: String?
    /// Price read off the shelf tag by the camera.
    var detectedPrice: PriceTagParser.Candidate?
    /// Price the user typed, which wins over the detected one.
    var manualPrice: Double?
    var history: [PricePoint] = []

    private var lookupTask: Task<Void, Never>?
    private var priceSightings: [Double: Int] = [:]

    var shelfPrice: Double? { manualPrice ?? detectedPrice?.amount }

    func verdict(currency: String, includeUsed: Bool) -> PriceVerdict? {
        guard let result, let price = shelfPrice else { return nil }
        return PriceAnalyzer.verdict(
            userPrice: price,
            currency: currency,
            offers: result.offers,
            history: history,
            recordedLow: result.product.recordedLow,
            includeUsed: includeUsed
        )
    }

    func reset() {
        lookupTask?.cancel()
        phase = .idle
        result = nil
        candidates = []
        scannedCode = nil
        detectedPrice = nil
        manualPrice = nil
        history = []
        priceSightings = [:]
    }

    /// Barcode from the camera or typed in.
    func lookup(code: String, isUPCE: Bool = false, model: AppModel, context: ModelContext) {
        guard let normalized = GTIN.normalize(code, isUPCE: isUPCE) else {
            phase = .failed("That barcode didn't read cleanly. Try again or type it in.")
            return
        }
        guard normalized != scannedCode || result == nil else { return }
        scannedCode = normalized
        lookupTask?.cancel()
        phase = .looking("Finding the best price…")
        let search = model.search
        let region = model.settings.region
        lookupTask = Task {
            do {
                let found = try await search.lookup(code: normalized, region: region)
                guard !Task.isCancelled else { return }
                self.result = found
                self.history = Self.knownHistory(for: found.product.id, context: context)
                self.phase = .found
                self.record(model: model, context: context)
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed((error as? LocalizedError)?.errorDescription ?? "Couldn't find that product.")
            }
        }
    }

    /// Product name typed in, or recognised from a photo.
    func search(query: String, model: AppModel) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if GTIN.normalize(trimmed) != nil, trimmed.allSatisfy({ $0.isNumber || $0 == " " }) {
            lookup(code: trimmed, model: model, context: model.container.mainContext)
            return
        }
        lookupTask?.cancel()
        phase = .looking("Searching shops for “\(trimmed)”…")
        let search = model.search
        let region = model.settings.region
        lookupTask = Task {
            do {
                let found = try await search.search(query: trimmed, region: region)
                guard !Task.isCancelled else { return }
                if found.count == 1 {
                    self.result = found[0]
                    self.phase = .found
                } else if found.isEmpty {
                    self.phase = .failed("No matches for “\(trimmed)”.")
                } else {
                    self.candidates = found
                    self.phase = .choosing
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed((error as? LocalizedError)?.errorDescription ?? "Search failed.")
            }
        }
    }

    func choose(_ candidate: PriceSearchService.Result, model: AppModel) {
        result = candidate
        candidates = []
        history = Self.knownHistory(for: candidate.product.id, context: model.container.mainContext)
        phase = .found
    }

    /// Identify a product from a photo when there's no barcode.
    func identify(image: UIImage, model: AppModel) {
        guard let cg = image.cgImage?.downscaled() else { return }
        lookupTask?.cancel()
        phase = .looking("Reading the packaging…")
        let ai = model.ai
        lookupTask = Task {
            async let textLines = VisionService.text(in: cg)
            async let labels = VisionService.labels(for: cg, limit: 5)
            let (lines, labelList) = await (textLines, labels)
            if let price = PriceTagParser.bestPrice(in: lines.joined(separator: "\n"), defaultCurrency: model.settings.currency), price.score >= 3 {
                self.detectedPrice = price
            }
            guard let query = await ai.productQuery(fromText: lines, labels: labelList.map(\.text)) else {
                self.phase = .failed("Couldn't tell what that is. Try the barcode instead.")
                return
            }
            self.search(query: query, model: model)
        }
    }

    /// Text seen by the live camera; keeps the price that shows up consistently.
    func observe(text: String, currency: String) {
        guard manualPrice == nil, let candidate = PriceTagParser.bestPrice(in: text, defaultCurrency: currency), candidate.score >= 2.5 else { return }
        let key = (candidate.amount * 100).rounded() / 100
        priceSightings[key, default: 0] += 1
        if priceSightings[key, default: 0] >= 2, detectedPrice?.amount != key {
            detectedPrice = candidate
        }
    }

    private func record(model: AppModel, context: ModelContext) {
        guard let result else { return }
        let verdict = verdict(currency: model.settings.currency, includeUsed: model.settings.includeUsed)
        let best = PriceAnalyzer.comparableOffers(result.offers, currency: model.settings.currency).map(\.totalPrice).min()
        context.insert(ScanRecord(product: result.product, code: scannedCode, userPrice: shelfPrice, bestPrice: best, currency: model.settings.currency, verdict: verdict?.level))
        try? context.save()
    }

    static func knownHistory(for productID: String, context: ModelContext) -> [PricePoint] {
        let id = productID
        return (try? context.fetch(FetchDescriptor<WishItem>(predicate: #Predicate { $0.productID == id })).first?.history) ?? []
    }
}
