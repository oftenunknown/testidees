import Foundation
import Testing
@testable import SnagKit

@Suite("Interests")
struct InterestTests {
    @Test func mapsPhotoLabels() {
        let result = InterestMatcher.interests(from: [("dog", 0.9), ("mountain", 0.8), ("coffee", 0.4), ("card", 0.9)], source: .photos)
        let found = Set(result.map(\.interest))
        #expect(found.contains(.dogs))
        #expect(found.contains(.hiking))
        #expect(found.contains(.coffee))
        #expect(!found.contains(.cars)) // "card" must not match "car"
    }

    @Test func splitsHandles() {
        let result = InterestMatcher.interests(fromTexts: ["natgeoTravel", "the_sourdough_school"], source: .instagramExport)
        let found = Set(result.map(\.interest))
        #expect(found.contains(.travel))
        #expect(found.contains(.baking))
    }

    @Test func mergeBoostsCorroboratedInterests() {
        let a = [WeightedInterest(.coffee, weight: 0.5, sources: [.quiz])]
        let b = [WeightedInterest(.coffee, weight: 0.5, sources: [.photos]), WeightedInterest(.tea, weight: 0.6, sources: [.photos])]
        let merged = InterestMatcher.merge(a, b)
        #expect(merged.first { $0.interest == .coffee }?.weight == 0.65)
        #expect(merged.first { $0.interest == .coffee }?.sources == [.quiz, .photos])
    }
}

@Suite("Persona")
struct PersonaTests {
    @Test func quizShapesArchetype() {
        let quiz = PersonaQuiz.standard
        let adventurous = quiz.evaluate([
            "saturday": ["outside"], "surprise": ["surprise"], "souvenir": ["memory"],
            "splurge": ["experience"], "love": ["time"], "passions": ["p-outdoors", "p-travel"],
        ])
        #expect(adventurous.traits.experiential > 0.9)
        #expect(Archetype.best(for: adventurous.traits).id == "adventurer")
        #expect(adventurous.interests.contains { $0.interest == .hiking })

        let sentimental = quiz.evaluate(["surprise": ["tears"], "love": ["words"], "souvenir": ["craft"]])
        #expect(Archetype.best(for: sentimental.traits).id == "sentimentalist")
    }

    @Test func multiSelectIsDamped() {
        let quiz = PersonaQuiz.standard
        let all = quiz.questions.first { $0.id == "aesthetic" }!.choices.map(\.id)
        let result = quiz.evaluate(["aesthetic": all])
        #expect(result.traits.openness < 0.52)
        #expect(result.aesthetics.count == 3)
    }

    @Test func completeness() {
        var p = PersonaProfile()
        #expect(p.completeness == 0)
        p.sources = [.quiz, .photos]
        p.interests = [.init(.coffee, weight: 1), .init(.tea, weight: 1), .init(.art, weight: 1)]
        #expect(p.completeness > 0.8)
    }
}

@Suite("Gift recommender")
struct GiftRecommenderTests {
    var giver: PersonaProfile {
        var g = PersonaProfile(displayName: "Me")
        g.traits = PersonaTraits(openness: 0.8, extraversion: 0.7, experiential: 0.95)
        g.interests = [WeightedInterest(.hiking, weight: 0.9)]
        return g
    }

    @Test func matchesInterestsAndBudget() {
        let recipient = RecipientProfile(name: "Sam", relationship: .bestFriend, ageBand: .thirties,
                                         interests: [WeightedInterest(.coffee, weight: 1), WeightedInterest(.hiking, weight: 0.8)],
                                         budgetMin: 30, budgetMax: 90)
        let ideas = GiftRecommender.recommend(for: recipient, from: giver, count: 6)
        #expect(ideas.count == 6)
        #expect(ideas.prefix(3).contains { !Set($0.interests).isDisjoint(with: [.coffee, .hiking]) })
        #expect(ideas.allSatisfy { !$0.whyThem.isEmpty && !$0.whyYou.isEmpty })
        #expect(ideas.first?.whyThem.contains("Sam") == true)
    }

    @Test func sharedInterestCreatesTogetherIdea() {
        let recipient = RecipientProfile(name: "Alex", relationship: .partner, interests: [WeightedInterest(.hiking, weight: 1)], budgetMin: 40, budgetMax: 120, occasion: .anniversary)
        let ideas = GiftRecommender.recommend(for: recipient, from: giver, count: 8)
        #expect(ideas.contains { $0.whyYou.contains("together") })
    }

    @Test func respectsDislikesAndAge() {
        let recipient = RecipientProfile(name: "Kid", relationship: .child, ageBand: .kid, interests: [WeightedInterest(.cocktails, weight: 1), WeightedInterest(.boardGames, weight: 0.6)], dislikes: ["puzzle"])
        let ideas = GiftRecommender.recommend(for: recipient, from: giver, count: 10)
        #expect(!ideas.contains { $0.title.lowercased().contains("cocktail") })
        #expect(!ideas.contains { $0.title.lowercased().contains("puzzle") })
    }

    @Test func avoidsRepeatingPastGifts() {
        let recipient = RecipientProfile(name: "Jo", interests: [WeightedInterest(.coffee, weight: 1)], pastGifts: ["specialty coffee subscription"])
        let ideas = GiftRecommender.recommend(for: recipient, from: giver, count: 3)
        #expect(!ideas.contains { $0.title == "Specialty coffee subscription" })
    }

    @Test func diverseKinds() {
        let recipient = RecipientProfile(name: "Pat", interests: [WeightedInterest(.music, weight: 1), WeightedInterest(.vinyl, weight: 1), WeightedInterest(.concerts, weight: 1)], budgetMin: 20, budgetMax: 300)
        let ideas = GiftRecommender.recommend(for: recipient, from: giver, count: 6)
        #expect(Set(ideas.map(\.kind)).count >= 3)
    }

    @Test func promptMentionsBothPeople() {
        let recipient = RecipientProfile(name: "Sam", relationship: .friend, interests: [WeightedInterest(.coffee, weight: 1)], dislikes: ["mugs"], currency: "GBP")
        let prompt = GiftPromptBuilder.prompt(recipient: recipient, giver: giver, count: 5)
        #expect(prompt.contains("Sam"))
        #expect(prompt.contains("The Adventurer"))
        #expect(prompt.contains("GBP"))
        #expect(prompt.contains("mugs"))
    }
}

@Suite("Importers")
struct ImporterTests {
    @Test func instagramTopics() throws {
        let topics = #"{"topics_your_topics":[{"string_map_data":{"Name":{"value":"Hiking"}}},{"string_map_data":{"Name":{"value":"Coffee"}}}]}"#
        let following = #"{"relationships_following":[{"string_list_data":[{"href":"https://instagram.com/natgeotravel","value":"natgeotravel","timestamp":1}]}]}"#
        let result = InstagramExportParser.parse(files: [("your_topics.json", Data(topics.utf8)), ("following.json", Data(following.utf8))])
        #expect(result.topics == ["Hiking", "Coffee"])
        #expect(result.accounts == ["natgeotravel"])
        let interests = Set(InstagramExportParser.interests(from: result).map(\.interest))
        #expect(interests.isSuperset(of: [.hiking, .coffee, .travel]))
    }

    @Test func orderHistoryCSV() {
        let csv = #"""
        Order Date,Order ID,Product Name,Item Total
        2026-01-02,1,"Hario V60 Coffee Dripper, Size 02",$24.99
        2026-02-10,2,"Yoga Mat 6mm",$35.00
        2026-03-01,3,"Book: ""The Hobbit""",$12.00
        """#
        let result = OrderHistoryParser.parse(csv: csv)
        #expect(result.productNames.count == 3)
        #expect(result.productNames[0] == "Hario V60 Coffee Dripper, Size 02")
        #expect(result.productNames[2] == "Book: \"The Hobbit\"")
        #expect(abs((result.averageOrderValue ?? 0) - 23.997) < 0.01)
        let interests = Set(OrderHistoryParser.interests(from: result).map(\.interest))
        #expect(interests.isSuperset(of: [.coffee, .yoga, .reading]))
    }
}
