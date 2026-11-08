import Foundation

/// A famous trip to measure your distance against.
///
/// City pairs use great-circle distances computed from their coordinates.
/// Routes, trails and voyages use their commonly cited lengths; their
/// waypoints are only for drawing, so every number shown is marked "≈".
public struct Journey: Hashable, Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case city, crossing, flight, voyage, trail, road, rail, planet, space
    }

    public var id: String
    public var title: String
    public var subtitle: String
    public var kind: Kind
    public var lengthKm: Double
    public var waypoints: [Coordinate]
    public var from: String?
    public var to: String?
    public var fact: String?

    /// Big enough to draw on the dot-matrix world map.
    public var isMappable: Bool { waypoints.count >= 2 && lengthKm >= 250 && kind != .space }

    public var symbol: String {
        switch kind {
        case .city: "mappin.and.ellipse"
        case .crossing: "water.waves"
        case .flight: "airplane"
        case .voyage: "sailboat.fill"
        case .trail: "figure.hiking"
        case .road: "road.lanes"
        case .rail: "tram.fill"
        case .planet: "globe.europe.africa.fill"
        case .space: "moon.stars.fill"
        }
    }
}

public enum JourneyCatalog {
    static func c(_ lat: Double, _ lon: Double) -> Coordinate { Coordinate(lat, lon) }

    /// Great-circle length of a city pair, rounded to the kilometre.
    static func flight(_ id: String, _ from: String, _ to: String, _ a: Coordinate, _ b: Coordinate, subtitle: String = "as the crow flies", kind: Journey.Kind = .city, fact: String? = nil) -> Journey {
        Journey(id: id, title: "\(from) → \(to)", subtitle: subtitle, kind: kind,
                lengthKm: Geo.distanceKm(a, b).rounded(), waypoints: [a, b], from: from, to: to, fact: fact)
    }

    public static let all: [Journey] = [
        Journey(id: "manhattan", title: "Manhattan, end to end", subtitle: "Battery Park → Inwood", kind: .city, lengthKm: 21.6,
                waypoints: [c(40.7033, -74.0170), c(40.7580, -73.9855), c(40.8732, -73.9105)], from: "Battery Park", to: "Inwood"),
        flight("channel", "Dover", "Cap Gris-Nez", c(51.1279, 1.3134), c(50.8693, 1.5841), subtitle: "the English Channel swim", kind: .crossing,
               fact: "Channel swimmers usually cover far more than this, pushed around by the tides."),
        flight("london-paris", "London", "Paris", c(51.5072, -0.1276), c(48.8566, 2.3522)),
        flight("nyc-boston", "New York", "Boston", c(40.7128, -74.0060), c(42.3601, -71.0589)),
        flight("tokyo-osaka", "Tokyo", "Osaka", c(35.6762, 139.6503), c(34.6937, 135.5023)),
        flight("sf-la", "San Francisco", "Los Angeles", c(37.7749, -122.4194), c(34.0522, -118.2437)),
        flight("amsterdam-berlin", "Amsterdam", "Berlin", c(52.3676, 4.9041), c(52.5200, 13.4050)),
        Journey(id: "camino", title: "The Camino de Santiago", subtitle: "Camino Francés, St-Jean → Santiago", kind: .trail, lengthKm: 780,
                waypoints: [c(43.1631, -1.2378), c(42.8125, -1.6458), c(42.4627, -2.4450), c(42.3439, -3.6969), c(42.5987, -5.5671), c(42.8782, -8.5448)],
                from: "St-Jean-Pied-de-Port", to: "Santiago", fact: "Pilgrims have walked it for more than a thousand years."),
        Journey(id: "lejog", title: "Land's End → John o' Groats", subtitle: "the length of Britain by road", kind: .road, lengthKm: 1407,
                waypoints: [c(50.0657, -5.7132), c(51.4545, -2.5879), c(53.4808, -2.2426), c(54.8925, -2.9329), c(55.9533, -3.1883), c(57.4778, -4.2247), c(58.6373, -3.0689)],
                from: "Land's End", to: "John o' Groats"),
        flight("london-rome", "London", "Rome", c(51.5072, -0.1276), c(41.9028, 12.4964), kind: .flight),
        Journey(id: "route66", title: "Route 66", subtitle: "Chicago → Santa Monica", kind: .road, lengthKm: 3940,
                waypoints: [c(41.8781, -87.6298), c(38.6270, -90.1994), c(37.2090, -93.2923), c(36.1540, -95.9928), c(35.4676, -97.5164), c(35.2220, -101.8313), c(35.0844, -106.6504), c(35.1983, -111.6513), c(34.8958, -117.0173), c(34.0195, -118.4912)],
                from: "Chicago", to: "Santa Monica", fact: "The Mother Road opened in 1926."),
        Journey(id: "appalachian", title: "The Appalachian Trail", subtitle: "Georgia → Maine", kind: .trail, lengthKm: 3530,
                waypoints: [c(34.6266, -84.1938), c(35.5628, -83.4985), c(36.6337, -81.7837), c(39.3254, -77.7389), c(40.9687, -75.1418), c(42.6370, -73.1662), c(44.2706, -71.3033), c(45.9044, -68.9213)],
                from: "Springer Mountain", to: "Mount Katahdin", fact: "Thru-hikers take five to seven months."),
        Journey(id: "pct", title: "The Pacific Crest Trail", subtitle: "Mexico → Canada", kind: .trail, lengthKm: 4265,
                waypoints: [c(32.5899, -116.4669), c(35.9800, -118.1200), c(37.8700, -119.3500), c(40.4900, -121.4200), c(42.9400, -122.1000), c(45.6700, -121.8900), c(47.4200, -121.4100), c(49.0640, -120.7920)],
                from: "Campo", to: "Manning Park"),
        flight("la-honolulu", "Los Angeles", "Honolulu", c(34.0522, -118.2437), c(21.3069, -157.8583), kind: .flight),
        flight("paris-nyc", "Paris", "New York", c(48.8566, 2.3522), c(40.7128, -74.0060), subtitle: "the transatlantic flight", kind: .flight,
               fact: "About eight hours by plane."),
        Journey(id: "silk-road", title: "The Silk Road", subtitle: "Xi'an → Constantinople", kind: .road, lengthKm: 6400,
                waypoints: [c(34.3416, 108.9398), c(36.0611, 103.8343), c(40.1421, 94.6620), c(42.9513, 89.1895), c(39.4704, 75.9898), c(39.6270, 66.9750), c(37.6620, 62.1920), c(35.6892, 51.3890), c(33.3152, 44.3661), c(36.2021, 36.1606), c(41.0082, 28.9784)],
                from: "Xi'an", to: "Constantinople", fact: "Silk, spices and ideas moved along it for 1,500 years."),
        Journey(id: "columbus", title: "Columbus's 1492 voyage", subtitle: "Palos → the Canaries → San Salvador", kind: .voyage,
                lengthKm: (Geo.pathLengthKm([c(37.2283, -6.8936), c(28.0916, -17.1133), c(24.0500, -74.5300)]) / 10).rounded() * 10,
                waypoints: [c(37.2283, -6.8936), c(28.0916, -17.1133), c(24.0500, -74.5300)],
                from: "Palos", to: "San Salvador", fact: "The Niña, Pinta and Santa María took 70 days."),
        Journey(id: "great-wall", title: "The Great Wall of China", subtitle: "the Ming-era wall", kind: .road, lengthKm: 8850,
                waypoints: [c(39.8000, 98.2100), c(38.2900, 109.7300), c(39.4500, 111.5000), c(40.0800, 113.3000), c(40.3600, 116.0100), c(40.0100, 119.7500)],
                from: "Jiayuguan", to: "Shanhaiguan", fact: "Built and rebuilt over two thousand years."),
        Journey(id: "trans-siberian", title: "The Trans-Siberian Railway", subtitle: "Moscow → Vladivostok", kind: .rail, lengthKm: 9289,
                waypoints: [c(55.7558, 37.6173), c(56.3269, 44.0059), c(56.8389, 60.6057), c(55.0084, 82.9357), c(56.0153, 92.8932), c(52.2870, 104.3050), c(52.0340, 113.4994), c(48.4827, 135.0838), c(43.1155, 131.8855)],
                from: "Moscow", to: "Vladivostok", fact: "Seven nights on the train, across eight time zones."),
        flight("nyc-tokyo", "New York", "Tokyo", c(40.7128, -74.0060), c(35.6762, 139.6503), kind: .flight),
        flight("london-sydney", "London", "Sydney", c(51.5072, -0.1276), c(-33.8688, 151.2093), subtitle: "halfway round the world", kind: .flight),
        Journey(id: "equator", title: "Around the Equator", subtitle: "all the way round the Earth", kind: .planet, lengthKm: 40_075,
                waypoints: stride(from: -180.0, through: 180.0, by: 30).map { c(0, $0) }),
        Journey(id: "moon", title: "To the Moon", subtitle: "average distance from Earth", kind: .space, lengthKm: 384_400, waypoints: []),
    ]

    public static func journey(_ id: String) -> Journey? { all.first { $0.id == id } }
}

/// Something tall to measure climbing against.
public struct Landmark: Hashable, Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case building, mountain, sky }

    public var id: String
    public var name: String
    public var plural: String
    public var heightMeters: Double
    public var kind: Kind

    public var symbol: String {
        switch kind {
        case .building: "building.2.fill"
        case .mountain: "mountain.2.fill"
        case .sky: "airplane.departure"
        }
    }

    public static let all: [Landmark] = [
        Landmark(id: "liberty", name: "the Statue of Liberty", plural: "Statues of Liberty", heightMeters: 93, kind: .building),
        Landmark(id: "eiffel", name: "the Eiffel Tower", plural: "Eiffel Towers", heightMeters: 330, kind: .building),
        Landmark(id: "empire", name: "the Empire State Building", plural: "Empire State Buildings", heightMeters: 443, kind: .building),
        Landmark(id: "burj", name: "the Burj Khalifa", plural: "Burj Khalifas", heightMeters: 828, kind: .building),
        Landmark(id: "fuji", name: "Mount Fuji", plural: "Mount Fujis", heightMeters: 3776, kind: .mountain),
        Landmark(id: "mont-blanc", name: "Mont Blanc", plural: "Mont Blancs", heightMeters: 4806, kind: .mountain),
        Landmark(id: "kilimanjaro", name: "Kilimanjaro", plural: "Kilimanjaros", heightMeters: 5895, kind: .mountain),
        Landmark(id: "everest", name: "Everest", plural: "Everests", heightMeters: 8849, kind: .mountain),
        Landmark(id: "cruising", name: "a jet's cruising altitude", plural: "cruising altitudes", heightMeters: 10_700, kind: .sky),
        Landmark(id: "space", name: "the edge of space", plural: "trips to the edge of space", heightMeters: 100_000, kind: .sky),
    ]

    public static func landmark(_ id: String) -> Landmark? { all.first { $0.id == id } }
}
