import Foundation

/// Curated interest taxonomy shared by personas, recipients and gift ideas.
/// Free-text signals (photo labels, Instagram topics, product titles) are
/// mapped onto these so very different sources can be compared.
public enum Interest: String, Codable, CaseIterable, Sendable, Identifiable {
    case hiking, camping, travel, beach, cycling, running, fitness, yoga, football, basketball, golf, tennis, skiing, surfing
    case cooking, baking, coffee, tea, wine, cocktails, foodie
    case music, vinyl, concerts, playingMusic
    case reading, writing, art, photography, design, crafts
    case gaming, tech, film, anime, boardGames
    case fashion, sneakers, beauty, jewellery
    case home, plants, gardening
    case dogs, cats
    case wellness, sustainability, cars, diy, science, space, history, parenting, partying

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .hiking: "Hiking"
        case .camping: "Camping"
        case .travel: "Travel"
        case .beach: "Beach life"
        case .cycling: "Cycling"
        case .running: "Running"
        case .fitness: "Fitness"
        case .yoga: "Yoga"
        case .football: "Football"
        case .basketball: "Basketball"
        case .golf: "Golf"
        case .tennis: "Tennis"
        case .skiing: "Skiing"
        case .surfing: "Surfing"
        case .cooking: "Cooking"
        case .baking: "Baking"
        case .coffee: "Coffee"
        case .tea: "Tea"
        case .wine: "Wine"
        case .cocktails: "Cocktails"
        case .foodie: "Eating out"
        case .music: "Music"
        case .vinyl: "Vinyl"
        case .concerts: "Live music"
        case .playingMusic: "Playing music"
        case .reading: "Reading"
        case .writing: "Writing"
        case .art: "Art"
        case .photography: "Photography"
        case .design: "Design"
        case .crafts: "Crafts"
        case .gaming: "Gaming"
        case .tech: "Tech"
        case .film: "Film & TV"
        case .anime: "Anime"
        case .boardGames: "Board games"
        case .fashion: "Fashion"
        case .sneakers: "Sneakers"
        case .beauty: "Beauty"
        case .jewellery: "Jewellery"
        case .home: "Home & interiors"
        case .plants: "Plants"
        case .gardening: "Gardening"
        case .dogs: "Dogs"
        case .cats: "Cats"
        case .wellness: "Wellness"
        case .sustainability: "Sustainability"
        case .cars: "Cars"
        case .diy: "DIY"
        case .science: "Science"
        case .space: "Space"
        case .history: "History"
        case .parenting: "Family"
        case .partying: "Going out"
        }
    }

    public var symbol: String {
        switch self {
        case .hiking: "figure.hiking"
        case .camping: "tent.fill"
        case .travel: "airplane"
        case .beach: "beach.umbrella.fill"
        case .cycling: "bicycle"
        case .running: "figure.run"
        case .fitness: "dumbbell.fill"
        case .yoga: "figure.yoga"
        case .football: "soccerball"
        case .basketball: "basketball.fill"
        case .golf: "figure.golf"
        case .tennis: "tennis.racket"
        case .skiing: "figure.skiing.downhill"
        case .surfing: "figure.surfing"
        case .cooking: "frying.pan.fill"
        case .baking: "birthday.cake.fill"
        case .coffee: "cup.and.saucer.fill"
        case .tea: "mug.fill"
        case .wine: "wineglass.fill"
        case .cocktails: "wineglass"
        case .foodie: "fork.knife"
        case .music: "music.note"
        case .vinyl: "record.circle"
        case .concerts: "music.mic"
        case .playingMusic: "guitars.fill"
        case .reading: "book.fill"
        case .writing: "pencil.and.scribble"
        case .art: "paintpalette.fill"
        case .photography: "camera.fill"
        case .design: "ruler.fill"
        case .crafts: "scissors"
        case .gaming: "gamecontroller.fill"
        case .tech: "desktopcomputer"
        case .film: "film.fill"
        case .anime: "sparkles.tv.fill"
        case .boardGames: "dice.fill"
        case .fashion: "tshirt.fill"
        case .sneakers: "shoe.fill"
        case .beauty: "comb.fill"
        case .jewellery: "sparkle"
        case .home: "sofa.fill"
        case .plants: "leaf.fill"
        case .gardening: "camera.macro"
        case .dogs: "dog.fill"
        case .cats: "cat.fill"
        case .wellness: "heart.circle.fill"
        case .sustainability: "arrow.3.trianglepath"
        case .cars: "car.fill"
        case .diy: "hammer.fill"
        case .science: "flask.fill"
        case .space: "moon.stars.fill"
        case .history: "building.columns.fill"
        case .parenting: "figure.2.and.child.holdinghands"
        case .partying: "party.popper.fill"
        }
    }

    /// Lower-case tokens that indicate this interest in labels, titles or handles.
    public var keywords: [String] {
        switch self {
        case .hiking: ["hiking", "hike", "trail", "mountain", "summit", "trekking", "backpacking", "alpine", "hillwalking"]
        case .camping: ["camping", "tent", "campfire", "campsite", "sleeping bag", "bushcraft", "overlanding"]
        case .travel: ["travel", "airport", "airplane", "passport", "suitcase", "luggage", "wanderlust", "tourism", "landmark", "vacation", "holiday", "destination"]
        case .beach: ["beach", "seashore", "ocean", "sand", "coast", "tropical", "palm tree"]
        case .cycling: ["bicycle", "cycling", "bike", "cyclist", "peloton", "strava", "mtb", "road bike"]
        case .running: ["running", "runner", "marathon", "jogging", "parkrun", "trainers"]
        case .fitness: ["gym", "fitness", "workout", "weightlifting", "dumbbell", "crossfit", "bodybuilding", "exercise", "protein"]
        case .yoga: ["yoga", "pilates", "meditation", "mindfulness", "mat"]
        case .football: ["soccer", "football", "premier league", "fifa", "stadium"]
        case .basketball: ["basketball", "nba", "hoops"]
        case .golf: ["golf", "golfer", "putter", "fairway"]
        case .tennis: ["tennis", "racket", "padel", "wimbledon", "pickleball"]
        case .skiing: ["ski", "skiing", "snowboard", "snowboarding", "slopes", "apres"]
        case .surfing: ["surf", "surfing", "surfboard", "wave", "paddleboard", "kayak"]
        case .cooking: ["cooking", "chef", "kitchen", "recipe", "cookware", "frying pan", "knife", "cast iron", "dutch oven", "spice"]
        case .baking: ["baking", "bread", "cake", "pastry", "sourdough", "cupcake", "cookie", "dessert"]
        case .coffee: ["coffee", "espresso", "latte", "cappuccino", "barista", "cafe", "pour over", "aeropress", "beans"]
        case .tea: ["tea", "matcha", "teapot", "chai"]
        case .wine: ["wine", "vineyard", "winery", "sommelier", "champagne", "prosecco"]
        case .cocktails: ["cocktail", "gin", "whisky", "whiskey", "bourbon", "mixology", "bar", "rum", "tequila", "mezcal"]
        case .foodie: ["restaurant", "food", "foodie", "dining", "brunch", "sushi", "pizza", "ramen", "tasting", "michelin"]
        case .music: ["music", "spotify", "playlist", "headphones", "earbuds", "speaker", "album"]
        case .vinyl: ["vinyl", "record player", "turntable", "lp"]
        case .concerts: ["concert", "festival", "gig", "live music", "stage", "tour"]
        case .playingMusic: ["guitar", "piano", "drum", "ukulele", "violin", "synth", "musician", "keyboard instrument", "bass guitar"]
        case .reading: ["book", "books", "reading", "novel", "library", "kindle", "bookstagram", "booktok", "literature", "bookshop"]
        case .writing: ["journal", "notebook", "writing", "poetry", "fountain pen", "stationery", "calligraphy"]
        case .art: ["art", "painting", "museum", "gallery", "artist", "sketch", "illustration", "drawing", "canvas", "watercolor", "watercolour"]
        case .photography: ["camera", "photography", "photographer", "lens", "film camera", "polaroid", "35mm", "tripod"]
        case .design: ["design", "architecture", "typography", "interior design", "graphic", "minimalist"]
        case .crafts: ["craft", "knitting", "crochet", "sewing", "pottery", "ceramics", "embroidery", "diy craft", "yarn", "lego"]
        case .gaming: ["gaming", "video game", "playstation", "xbox", "nintendo", "switch", "steam", "esports", "controller", "twitch"]
        case .tech: ["tech", "gadget", "computer", "laptop", "smartphone", "iphone", "smart home", "keyboard", "electronics", "coding", "apple"]
        case .film: ["movie", "film", "cinema", "netflix", "series", "television", "tv show", "marvel", "star wars"]
        case .anime: ["anime", "manga", "studio ghibli", "cosplay", "japan"]
        case .boardGames: ["board game", "boardgame", "chess", "puzzle", "jigsaw", "card game", "dungeons", "tabletop"]
        case .fashion: ["fashion", "outfit", "style", "streetwear", "vintage clothing", "dress", "jacket", "ootd", "clothing", "apparel"]
        case .sneakers: ["sneaker", "sneakers", "trainers", "jordan", "nike", "adidas", "new balance", "shoe"]
        case .beauty: ["makeup", "beauty", "skincare", "cosmetics", "lipstick", "fragrance", "perfume", "nail", "hair care", "serum"]
        case .jewellery: ["jewelry", "jewellery", "necklace", "ring", "earrings", "bracelet", "watch"]
        case .home: ["home", "interior", "candle", "decor", "cozy", "cosy", "furniture", "living room", "throw", "hygge"]
        case .plants: ["plant", "houseplant", "succulent", "monstera", "cactus", "flower", "botanical", "terrarium"]
        case .gardening: ["garden", "gardening", "allotment", "seeds", "vegetable patch", "greenhouse", "lawn"]
        case .dogs: ["dog", "puppy", "canine", "doggo", "labrador", "retriever", "terrier", "spaniel", "poodle", "frenchie", "dachshund"]
        case .cats: ["cat", "kitten", "feline", "kitty"]
        case .wellness: ["wellness", "self care", "self-care", "spa", "bath", "massage", "sleep", "skincare routine", "journaling"]
        case .sustainability: ["sustainable", "eco", "zero waste", "vegan", "recycled", "thrift", "secondhand", "climate", "organic"]
        case .cars: ["car", "cars", "automotive", "motorsport", "formula 1", "f1", "porsche", "racing", "motorcycle", "motorbike"]
        case .diy: ["diy", "woodworking", "tools", "workshop", "home improvement", "drill", "carpentry"]
        case .science: ["science", "chemistry", "physics", "biology", "lab", "microscope", "nerd"]
        case .space: ["space", "nasa", "astronomy", "telescope", "galaxy", "planet", "rocket", "stars", "astrophotography"]
        case .history: ["history", "castle", "ancient", "historic", "heritage", "museum", "archaeology"]
        case .parenting: ["baby", "toddler", "kids", "family", "parenting", "mom", "mum", "dad", "child"]
        case .partying: ["party", "nightlife", "club", "dance", "drinks", "celebration", "karaoke"]
        }
    }
}

/// An interest with how strongly we believe in it and where it came from.
public struct WeightedInterest: Codable, Hashable, Sendable, Identifiable {
    public var interest: Interest
    /// 0–1.
    public var weight: Double
    public var sources: Set<SignalSource>

    public var id: Interest { interest }

    public init(_ interest: Interest, weight: Double, sources: Set<SignalSource> = [.manual]) {
        self.interest = interest
        self.weight = min(1, max(0, weight))
        self.sources = sources
    }
}

public enum SignalSource: String, Codable, Sendable, CaseIterable {
    case manual, quiz, photos, instagramExport, orderHistory, wishlist, ai
}

public enum InterestMatcher {
    /// Maps free-text signals to interests. Each signal can carry a confidence
    /// (e.g. a photo classifier's score). Multi-word keywords match as phrases;
    /// short single words must match a whole token so "car" doesn't hit "card".
    public static func interests(
        from signals: [(text: String, confidence: Double)],
        source: SignalSource
    ) -> [WeightedInterest] {
        var scores: [Interest: Double] = [:]
        for signal in signals {
            let text = normalize(signal.text)
            guard !text.isEmpty else { continue }
            let tokens = Set(text.split(separator: " ").map(String.init))
            for interest in Interest.allCases {
                let hit = interest.keywords.contains { keyword in
                    keyword.contains(" ") ? text.contains(keyword) : (tokens.contains(keyword) || (keyword.count >= 5 && text.contains(keyword)))
                }
                if hit { scores[interest, default: 0] += max(0.05, signal.confidence) }
            }
        }
        guard let top = scores.values.max(), top > 0 else { return [] }
        return scores
            .map { WeightedInterest($0.key, weight: 0.25 + 0.75 * ($0.value / top), sources: [source]) }
            .sorted { $0.weight > $1.weight }
    }

    public static func interests(fromTexts texts: [String], source: SignalSource) -> [WeightedInterest] {
        interests(from: texts.map { ($0, 1.0) }, source: source)
    }

    /// Combines interest lists from different sources, keeping the strongest
    /// signal per interest and boosting ones that several sources agree on.
    public static func merge(_ lists: [WeightedInterest]...) -> [WeightedInterest] {
        merge(lists.flatMap { $0 })
    }

    public static func merge(_ all: [WeightedInterest]) -> [WeightedInterest] {
        var merged: [Interest: WeightedInterest] = [:]
        for item in all {
            if var existing = merged[item.interest] {
                let corroborated = !item.sources.isSubset(of: existing.sources)
                existing.weight = min(1, max(existing.weight, item.weight) + (corroborated ? 0.15 : 0))
                existing.sources.formUnion(item.sources)
                merged[item.interest] = existing
            } else {
                merged[item.interest] = item
            }
        }
        return merged.values.sorted { $0.weight == $1.weight ? $0.interest.rawValue < $1.interest.rawValue : $0.weight > $1.weight }
    }

    static func normalize(_ s: String) -> String {
        // Split camel case and handles: "natgeoTravel_photos" -> "natgeo travel photos"
        var out = ""
        var previous: Character?
        for ch in s {
            if ch.isUppercase, let p = previous, p.isLowercase { out.append(" ") }
            out.append(ch)
            previous = ch
        }
        let lowered = out.lowercased()
        let cleaned = lowered.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }
}
