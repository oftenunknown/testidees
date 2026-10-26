import Foundation

/// Seed ideas used when no language model is available, and as inspiration
/// in prompts when one is. Prices are rough USD anchors for budget matching.
public struct GiftTemplate: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var pitch: String
    public var kind: GiftIdea.Kind
    public var interests: [Interest]
    public var typicalPrice: Double
    /// Which giver/recipient traits make this a better fit.
    public var affinity: [PersonaTraits.Key: Double]
    public var aesthetics: [Aesthetic]
    public var query: String
    public var personalTouch: String?
    public var adultsOnly: Bool
    /// Works as a shared activity — giver and recipient do it together.
    public var shared: Bool

    init(
        _ id: String, _ title: String, _ pitch: String, kind: GiftIdea.Kind, interests: [Interest], price: Double,
        affinity: [PersonaTraits.Key: Double] = [:], aesthetics: [Aesthetic] = [], query: String,
        touch: String? = nil, adultsOnly: Bool = false, shared: Bool = false
    ) {
        self.id = id
        self.title = title
        self.pitch = pitch
        self.kind = kind
        self.interests = interests
        self.typicalPrice = price
        self.affinity = affinity
        self.aesthetics = aesthetics
        self.query = query
        self.personalTouch = touch
        self.adultsOnly = adultsOnly
        self.shared = shared
    }
}

public enum GiftCatalog {
    public static let templates: [GiftTemplate] = [
        // Outdoors
        GiftTemplate("trail-map-print", "Custom trail map print", "A framed topographic map of a route they love.", kind: .personalised, interests: [.hiking, .travel], price: 60,
                     affinity: [.sentimentality: 0.6, .experiential: 0.3], aesthetics: [.minimal, .natural], query: "custom topographic trail map print", touch: "Mark the spot you first hiked together."),
        GiftTemplate("packable-stove", "Ultralight camp stove kit", "Boils water in three minutes on a summit.", kind: .object, interests: [.camping, .hiking], price: 55,
                     affinity: [.practicality: 0.6, .experiential: 0.4], aesthetics: [.techy, .natural], query: "ultralight backpacking stove kit"),
        GiftTemplate("national-park-pass", "Annual parks pass + first trip", "A year of entry and a date for the first one.", kind: .experience, interests: [.hiking, .camping, .travel], price: 80,
                     affinity: [.experiential: 0.8, .sustainability: 0.3], query: "national parks annual pass", touch: "Tuck in a handwritten itinerary for your first day out.", shared: true),
        GiftTemplate("merino-layer", "Merino base layer", "The upgrade every outdoorsy person loves but never buys.", kind: .object, interests: [.hiking, .skiing, .running], price: 90,
                     affinity: [.practicality: 0.6, .luxury: 0.3, .sustainability: 0.3], aesthetics: [.natural, .minimal], query: "merino wool base layer"),
        GiftTemplate("stargazing-night", "Dark-sky stargazing night", "A guided night under properly dark skies.", kind: .experience, interests: [.space, .camping, .science], price: 70,
                     affinity: [.experiential: 0.7, .openness: 0.5, .sentimentality: 0.3], query: "guided stargazing experience", shared: true),
        GiftTemplate("bike-tune", "Pro bike service + gadget", "A full service and a clever multitool for the saddle bag.", kind: .experience, interests: [.cycling], price: 85,
                     affinity: [.practicality: 0.7], query: "bike multitool saddle bag"),
        GiftTemplate("race-entry", "Race entry they've been eyeing", "Sign them up — and promise to be at the finish line.", kind: .experience, interests: [.running, .cycling, .fitness], price: 60,
                     affinity: [.experiential: 0.6, .playfulness: 0.2], query: "half marathon race entry", touch: "Make a finish-line sign together."),
        GiftTemplate("surf-lesson", "Surf or paddleboard lesson for two", "Falling in is half the fun.", kind: .experience, interests: [.surfing, .beach], price: 120,
                     affinity: [.experiential: 0.8, .playfulness: 0.5, .extraversion: 0.3], query: "surf lesson for two", shared: true),
        // Food & drink
        GiftTemplate("knife", "A properly good chef's knife", "One knife they'll use every single day.", kind: .object, interests: [.cooking], price: 110,
                     affinity: [.practicality: 0.7, .luxury: 0.5], aesthetics: [.minimal], query: "japanese chef knife gyuto", touch: "Get it engraved with their initials.", adultsOnly: true),
        GiftTemplate("cooking-class", "Cooking class for two", "Learn a cuisine together, eat it afterwards.", kind: .experience, interests: [.cooking, .foodie], price: 140,
                     affinity: [.experiential: 0.8, .extraversion: 0.3], query: "cooking class for two", shared: true),
        GiftTemplate("spice-set", "Global spice collection", "A passport's worth of flavour in tiny tins.", kind: .consumable, interests: [.cooking, .foodie, .travel], price: 40,
                     affinity: [.openness: 0.5, .playfulness: 0.2], aesthetics: [.minimal], query: "spice gift set world"),
        GiftTemplate("sourdough-kit", "Sourdough starter kit", "Banneton, lame, and a starter with a name.", kind: .object, interests: [.baking, .cooking], price: 45,
                     affinity: [.practicality: 0.3, .openness: 0.3], aesthetics: [.cozy, .natural], query: "sourdough bread starter kit banneton"),
        GiftTemplate("coffee-subscription", "Specialty coffee subscription", "A new roaster at their door every month.", kind: .subscription, interests: [.coffee], price: 60,
                     affinity: [.openness: 0.5, .luxury: 0.3], query: "specialty coffee subscription"),
        GiftTemplate("pour-over", "Pour-over coffee setup", "Kettle, dripper, grinder — the slow-morning ritual.", kind: .object, interests: [.coffee], price: 95,
                     affinity: [.conscientiousness: 0.4, .luxury: 0.3], aesthetics: [.minimal, .techy], query: "pour over coffee set gooseneck kettle"),
        GiftTemplate("tea-flight", "Rare tea tasting flight", "Single-estate teas with tasting notes.", kind: .consumable, interests: [.tea, .wellness], price: 45,
                     affinity: [.openness: 0.4, .stability: 0.3], aesthetics: [.cozy, .minimal], query: "loose leaf tea tasting set"),
        GiftTemplate("wine-tasting", "Vineyard tour and tasting", "A day out that ends with a bottle to take home.", kind: .experience, interests: [.wine, .travel], price: 120,
                     affinity: [.experiential: 0.7, .luxury: 0.4], query: "vineyard tour wine tasting experience", adultsOnly: true, shared: true),
        GiftTemplate("cocktail-kit", "Cocktail smoker kit", "Turns an old fashioned into a party trick.", kind: .object, interests: [.cocktails, .partying], price: 50,
                     affinity: [.playfulness: 0.6, .extraversion: 0.4], aesthetics: [.vintage, .bold], query: "cocktail smoker kit", adultsOnly: true),
        GiftTemplate("tasting-menu", "Dinner at the place they keep mentioning", "Book the table, handle the babysitter.", kind: .experience, interests: [.foodie], price: 180,
                     affinity: [.experiential: 0.7, .luxury: 0.6], query: "restaurant gift card", shared: true),
        // Music
        GiftTemplate("turntable", "Entry-level turntable", "Start (or restart) a record collection.", kind: .object, interests: [.vinyl, .music], price: 180,
                     affinity: [.sentimentality: 0.3, .openness: 0.3], aesthetics: [.vintage], query: "bluetooth turntable record player"),
        GiftTemplate("first-record", "A record from the year you met", "Vinyl that means something.", kind: .personalised, interests: [.vinyl, .music], price: 35,
                     affinity: [.sentimentality: 0.9], aesthetics: [.vintage], query: "vinyl record", touch: "Pick an album from a year that matters to you both."),
        GiftTemplate("gig-tickets", "Tickets to see their favourite act", "The gift they'll talk about for years.", kind: .experience, interests: [.concerts, .music], price: 120,
                     affinity: [.experiential: 0.9, .extraversion: 0.4], query: "concert tickets", shared: true),
        GiftTemplate("lessons", "A block of music lessons", "For the guitar in the corner.", kind: .experience, interests: [.playingMusic], price: 150,
                     affinity: [.openness: 0.5, .conscientiousness: 0.3], query: "guitar lessons gift"),
        GiftTemplate("headphones", "Noise-cancelling headphones", "Instant quiet on every commute.", kind: .object, interests: [.music, .tech, .travel], price: 250,
                     affinity: [.practicality: 0.6, .luxury: 0.4], aesthetics: [.techy, .minimal], query: "noise cancelling headphones"),
        // Books & creative
        GiftTemplate("book-subscription", "Hand-picked book subscription", "A surprise novel every month, chosen for them.", kind: .subscription, interests: [.reading], price: 45,
                     affinity: [.openness: 0.6], aesthetics: [.cozy], query: "book subscription box"),
        GiftTemplate("first-edition", "A special edition of their favourite book", "The one they reread every year.", kind: .object, interests: [.reading, .history], price: 70,
                     affinity: [.sentimentality: 0.6, .luxury: 0.4], aesthetics: [.vintage], query: "illustrated special edition book", touch: "Write an inscription inside the cover."),
        GiftTemplate("reading-light", "Reading nook upgrade", "A warm clip light and a weighted throw.", kind: .object, interests: [.reading, .home], price: 60,
                     affinity: [.stability: 0.4, .agreeableness: 0.3], aesthetics: [.cozy], query: "book reading light warm"),
        GiftTemplate("fountain-pen", "A first fountain pen + journal", "Makes writing feel like an occasion.", kind: .object, interests: [.writing], price: 55,
                     affinity: [.conscientiousness: 0.4, .sentimentality: 0.4], aesthetics: [.vintage, .minimal], query: "fountain pen gift set journal"),
        GiftTemplate("pottery-class", "Pottery wheel class", "Get muddy, make a mug, keep it forever.", kind: .experience, interests: [.crafts, .art, .design], price: 90,
                     affinity: [.openness: 0.6, .experiential: 0.6, .playfulness: 0.3], query: "pottery wheel class", shared: true),
        GiftTemplate("art-supplies", "Artist-grade paint set", "The good stuff they wouldn't buy for themselves.", kind: .object, interests: [.art], price: 70,
                     affinity: [.openness: 0.6, .luxury: 0.3], aesthetics: [.bold], query: "artist watercolor paint set professional"),
        GiftTemplate("instant-camera", "Instant camera + film", "Photos you can hold, made at the party.", kind: .object, interests: [.photography, .partying], price: 90,
                     affinity: [.playfulness: 0.6, .sentimentality: 0.4], aesthetics: [.vintage, .playful], query: "instant camera film bundle"),
        GiftTemplate("photo-book", "A photo book of your year", "Every good moment, printed.", kind: .personalised, interests: [.photography, .travel], price: 45,
                     affinity: [.sentimentality: 1.0], query: "custom photo book", touch: "Add captions only the two of you will get."),
        GiftTemplate("film-camera", "Refurbished 35mm film camera", "For the friend with an eye for it.", kind: .object, interests: [.photography], price: 150,
                     affinity: [.openness: 0.5, .sustainability: 0.3], aesthetics: [.vintage], query: "refurbished 35mm film camera"),
        // Games & tech
        GiftTemplate("board-game", "A modern board game night", "A strategy game plus snacks for the first game night.", kind: .object, interests: [.boardGames, .partying], price: 50,
                     affinity: [.playfulness: 0.6, .extraversion: 0.4], aesthetics: [.playful], query: "best strategy board game", shared: true),
        GiftTemplate("puzzle", "1000-piece art puzzle", "A slow, satisfying weekend project.", kind: .object, interests: [.boardGames, .art], price: 30,
                     affinity: [.stability: 0.5, .conscientiousness: 0.3], aesthetics: [.cozy, .bold], query: "1000 piece art jigsaw puzzle"),
        GiftTemplate("controller", "Pro controller", "For the person who's 'just one more game'.", kind: .object, interests: [.gaming], price: 70,
                     affinity: [.playfulness: 0.4], aesthetics: [.techy], query: "pro wireless game controller"),
        GiftTemplate("retro-console", "Retro mini console", "Childhood games, plugged into the TV.", kind: .object, interests: [.gaming], price: 80,
                     affinity: [.sentimentality: 0.6, .playfulness: 0.6], aesthetics: [.vintage, .playful], query: "retro mini console"),
        GiftTemplate("smart-tracker", "Item trackers for keys and bags", "Never lose the keys again.", kind: .object, interests: [.tech, .travel], price: 35,
                     affinity: [.practicality: 0.8], aesthetics: [.techy, .minimal], query: "bluetooth item tracker 4 pack"),
        GiftTemplate("mech-keyboard", "Mechanical keyboard", "Clicky, customisable, and genuinely nicer to type on.", kind: .object, interests: [.tech, .gaming, .writing], price: 110,
                     affinity: [.openness: 0.3, .luxury: 0.3], aesthetics: [.techy], query: "mechanical keyboard hot swappable"),
        GiftTemplate("cinema-membership", "Independent cinema membership", "A year of films with someone to see them with.", kind: .subscription, interests: [.film], price: 90,
                     affinity: [.experiential: 0.5, .openness: 0.4], query: "cinema membership gift", shared: true),
        GiftTemplate("projector", "Mini projector movie night", "Turn any wall into an open-air cinema.", kind: .object, interests: [.film, .gaming], price: 160,
                     affinity: [.playfulness: 0.5, .experiential: 0.3], aesthetics: [.techy], query: "portable mini projector", shared: true),
        GiftTemplate("telescope", "Beginner telescope", "Saturn's rings from the back garden.", kind: .object, interests: [.space, .science], price: 170,
                     affinity: [.openness: 0.7], aesthetics: [.techy], query: "beginner telescope"),
        GiftTemplate("lego-set", "A display-worthy LEGO set", "Two evenings of building, then a shelf piece.", kind: .object, interests: [.crafts, .design, .film], price: 90,
                     affinity: [.playfulness: 0.5, .conscientiousness: 0.3], aesthetics: [.playful, .bold], query: "lego set for adults"),
        GiftTemplate("anime-art", "Studio art book", "Concept art from the films they love.", kind: .object, interests: [.anime, .art], price: 40,
                     affinity: [.openness: 0.4, .sentimentality: 0.3], query: "anime art book"),
        // Style & beauty
        GiftTemplate("sneaker-care", "Sneaker cleaning and display kit", "Keeps the grails box-fresh.", kind: .object, interests: [.sneakers, .fashion], price: 35,
                     affinity: [.conscientiousness: 0.5, .practicality: 0.4], query: "sneaker cleaning kit"),
        GiftTemplate("limited-sneakers", "That pair they keep sending you", "Check the wishlist hints — they've been obvious.", kind: .object, interests: [.sneakers], price: 160,
                     affinity: [.luxury: 0.5, .playfulness: 0.3], aesthetics: [.bold], query: "limited sneakers"),
        GiftTemplate("silk-pillowcase", "Silk pillowcase + eye mask", "Better hair, better sleep, feels like a hotel.", kind: .object, interests: [.beauty, .wellness], price: 55,
                     affinity: [.luxury: 0.6, .agreeableness: 0.2], aesthetics: [.luxe, .minimal], query: "mulberry silk pillowcase eye mask set"),
        GiftTemplate("fragrance-discovery", "Niche fragrance discovery set", "Ten scents to find their signature.", kind: .object, interests: [.beauty, .fashion], price: 70,
                     affinity: [.openness: 0.6, .luxury: 0.5], aesthetics: [.luxe], query: "niche perfume discovery set", adultsOnly: true),
        GiftTemplate("skincare-ritual", "Skincare ritual set", "A tidy routine in good-looking bottles.", kind: .consumable, interests: [.beauty, .wellness], price: 60,
                     affinity: [.luxury: 0.4, .conscientiousness: 0.3], aesthetics: [.minimal, .luxe], query: "skincare gift set"),
        GiftTemplate("initial-necklace", "Fine initial necklace", "Small, personal, worn every day.", kind: .personalised, interests: [.jewellery, .fashion], price: 90,
                     affinity: [.sentimentality: 0.7, .luxury: 0.4], aesthetics: [.minimal, .luxe], query: "gold initial necklace", touch: "Use the initial of someone they love."),
        GiftTemplate("vintage-jacket", "A great vintage jacket", "One-of-one, which is the point.", kind: .object, interests: [.fashion, .sustainability], price: 85,
                     affinity: [.sustainability: 0.6, .openness: 0.4], aesthetics: [.vintage], query: "vintage denim jacket"),
        GiftTemplate("watch-strap", "Leather watch strap, monogrammed", "Makes the watch they already love feel new.", kind: .personalised, interests: [.jewellery, .fashion], price: 50,
                     affinity: [.sentimentality: 0.4, .practicality: 0.4], aesthetics: [.vintage, .luxe], query: "leather watch strap monogram"),
        // Home & plants
        GiftTemplate("rare-plant", "A rare houseplant + self-watering pot", "Low effort, high drama.", kind: .object, interests: [.plants, .home], price: 55,
                     affinity: [.stability: 0.3, .sustainability: 0.3], aesthetics: [.natural, .minimal], query: "rare houseplant self watering pot"),
        GiftTemplate("herb-garden", "Indoor smart herb garden", "Fresh basil in January.", kind: .object, interests: [.gardening, .cooking, .plants], price: 90,
                     affinity: [.practicality: 0.5, .sustainability: 0.4], aesthetics: [.techy, .natural], query: "indoor smart herb garden"),
        GiftTemplate("candle-making", "Candle-making kit", "Make your own scent for the flat.", kind: .object, interests: [.home, .crafts], price: 40,
                     affinity: [.playfulness: 0.3, .openness: 0.3], aesthetics: [.cozy], query: "candle making kit"),
        GiftTemplate("weighted-blanket", "Chunky knit throw", "The cosiest thing in the room.", kind: .object, interests: [.home, .wellness], price: 80,
                     affinity: [.agreeableness: 0.3, .stability: 0.3, .luxury: 0.3], aesthetics: [.cozy], query: "chunky knit throw blanket"),
        GiftTemplate("art-print", "Limited art print from an independent artist", "Something nobody else on the street has.", kind: .object, interests: [.art, .home, .design], price: 75,
                     affinity: [.openness: 0.6, .sustainability: 0.2], aesthetics: [.bold, .minimal], query: "limited edition art print independent artist"),
        GiftTemplate("custom-portrait", "Illustrated portrait of their home or pet", "Commissioned from a real illustrator.", kind: .personalised, interests: [.dogs, .cats, .home, .art], price: 70,
                     affinity: [.sentimentality: 0.9], aesthetics: [.playful, .cozy], query: "custom pet portrait illustration", touch: "Send the illustrator a photo only you have."),
        GiftTemplate("toolkit", "Good-quality cordless drill kit", "The toolkit that makes every job easier.", kind: .object, interests: [.diy, .home], price: 120,
                     affinity: [.practicality: 0.9], query: "cordless drill kit", adultsOnly: true),
        // Pets
        GiftTemplate("dog-adventure", "Dog adventure kit", "Hands-free lead, collapsible bowl, treat pouch.", kind: .object, interests: [.dogs, .hiking], price: 45,
                     affinity: [.practicality: 0.5, .experiential: 0.4], query: "hands free dog leash hiking kit"),
        GiftTemplate("cat-tree", "Design-y cat tree", "Furniture the cat and the human both like.", kind: .object, interests: [.cats, .home, .design], price: 120,
                     affinity: [.luxury: 0.3], aesthetics: [.minimal, .natural], query: "modern cat tree furniture"),
        // Wellness
        GiftTemplate("spa-day", "Spa day", "A whole day where nobody needs them.", kind: .experience, interests: [.wellness, .beauty], price: 150,
                     affinity: [.luxury: 0.6, .agreeableness: 0.3, .stability: 0.3], aesthetics: [.luxe], query: "spa day gift voucher", adultsOnly: true),
        GiftTemplate("massage-gun", "Compact massage gun", "For sore legs after every session.", kind: .object, interests: [.fitness, .running, .wellness], price: 80,
                     affinity: [.practicality: 0.7], aesthetics: [.techy], query: "mini massage gun"),
        GiftTemplate("yoga-retreat", "Weekend yoga retreat", "Two days offline.", kind: .experience, interests: [.yoga, .wellness, .travel], price: 300,
                     affinity: [.experiential: 0.7, .stability: 0.5, .luxury: 0.4], aesthetics: [.natural], query: "weekend yoga retreat"),
        GiftTemplate("smart-bottle", "Insulated bottle, engraved", "Goes everywhere, says something.", kind: .personalised, interests: [.fitness, .hiking, .sustainability], price: 40,
                     affinity: [.practicality: 0.6, .sustainability: 0.5], aesthetics: [.minimal], query: "insulated water bottle engraved", touch: "Engrave an inside joke."),
        // Sports & cars
        GiftTemplate("match-tickets", "Tickets to a live match", "Better seats than they'd ever book themselves.", kind: .experience, interests: [.football, .basketball, .tennis, .golf], price: 140,
                     affinity: [.experiential: 0.8, .extraversion: 0.5], query: "match tickets", shared: true),
        GiftTemplate("retro-shirt", "Retro shirt from their team's best season", "Nostalgia they can wear.", kind: .object, interests: [.football, .basketball], price: 70,
                     affinity: [.sentimentality: 0.6, .playfulness: 0.3], aesthetics: [.vintage], query: "retro football shirt"),
        GiftTemplate("golf-lesson", "Golf lesson with a pro", "Fix the slice once and for all.", kind: .experience, interests: [.golf], price: 90,
                     affinity: [.practicality: 0.4, .conscientiousness: 0.4], query: "golf lesson gift voucher"),
        GiftTemplate("track-day", "Driving experience day", "The car they've always wanted to drive, for a day.", kind: .experience, interests: [.cars], price: 200,
                     affinity: [.experiential: 0.9, .playfulness: 0.5, .luxury: 0.4], query: "supercar driving experience", adultsOnly: true),
        GiftTemplate("car-care", "Detailing kit", "Showroom shine in an afternoon.", kind: .object, interests: [.cars, .diy], price: 60,
                     affinity: [.practicality: 0.6, .conscientiousness: 0.5], query: "car detailing kit", adultsOnly: true),
        // History, science, travel
        GiftTemplate("museum-membership", "Museum membership", "Skip-the-queue visits all year.", kind: .subscription, interests: [.history, .art, .science], price: 80,
                     affinity: [.openness: 0.6, .experiential: 0.5], query: "museum membership gift", shared: true),
        GiftTemplate("scratch-map", "Scratch-off world map", "Every trip, revealed.", kind: .object, interests: [.travel], price: 30,
                     affinity: [.playfulness: 0.5, .sentimentality: 0.3], aesthetics: [.playful], query: "scratch off world map poster"),
        GiftTemplate("packing-cubes", "Premium packing cubes", "Carry-on only, forever.", kind: .object, interests: [.travel], price: 40,
                     affinity: [.practicality: 0.8, .conscientiousness: 0.5], aesthetics: [.minimal], query: "compression packing cubes"),
        GiftTemplate("weekend-away", "A surprise weekend away", "You plan it, they just pack.", kind: .experience, interests: [.travel, .foodie], price: 350,
                     affinity: [.experiential: 1.0, .openness: 0.5, .sentimentality: 0.3], query: "weekend getaway", shared: true),
        GiftTemplate("science-kit", "Grown-up chemistry kit", "Make things fizz, legitimately.", kind: .object, interests: [.science], price: 50,
                     affinity: [.openness: 0.6, .playfulness: 0.5], aesthetics: [.playful], query: "science experiment kit adults"),
        // Family & parties
        GiftTemplate("family-portrait", "Family photo session", "Everyone in one photo, finally.", kind: .experience, interests: [.parenting, .photography], price: 150,
                     affinity: [.sentimentality: 0.9], query: "family photoshoot gift voucher"),
        GiftTemplate("night-off", "A night off, fully arranged", "Babysitting, dinner booking, done.", kind: .experience, interests: [.parenting, .foodie], price: 100,
                     affinity: [.practicality: 0.5, .agreeableness: 0.6, .experiential: 0.4], query: "restaurant gift card"),
        GiftTemplate("karaoke", "Private karaoke room", "Friends, a mic and zero shame.", kind: .experience, interests: [.partying, .music], price: 90,
                     affinity: [.extraversion: 0.8, .playfulness: 0.8], query: "private karaoke room booking", adultsOnly: true, shared: true),
        // Sustainability
        GiftTemplate("refill-kit", "Zero-waste bathroom refill kit", "Pretty glass bottles, no more plastic.", kind: .object, interests: [.sustainability, .beauty], price: 45,
                     affinity: [.sustainability: 0.9], aesthetics: [.minimal, .natural], query: "zero waste refillable bathroom set"),
        GiftTemplate("tree-planting", "Trees planted in their name", "A gift that keeps growing.", kind: .experience, interests: [.sustainability, .gardening], price: 25,
                     affinity: [.sustainability: 1.0, .sentimentality: 0.3], query: "plant trees gift certificate"),
    ]
}
