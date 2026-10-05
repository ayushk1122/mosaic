import Testing
@testable import Mosaic

struct PursuitCatalogTests {
    @Test
    func iteration0AHasStablePursuitOrder() {
        let pursuits = MosaicHomeFixtures.iteration0A.pursuits

        #expect(pursuits.map(\.id.rawValue) == ["golf", "fitness", "modeling", "cooking"])
        #expect(pursuits.map(\.kind) == [.golf, .fitness, .modeling, .cooking])
        #expect(pursuits.map(\.title) == ["Golf", "Fitness", "Modeling", "Cooking"])
    }
}
