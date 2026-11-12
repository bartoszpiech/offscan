import Testing
@testable import FlatlyCore

struct PageSizeOptionTests {
    @Test(arguments: ["US", "CA", "MX", "PH", "us"])
    func letterRegionsDefaultToLetter(region: String) {
        #expect(PageSizeOption.defaultSize(forRegion: region) == .letter)
    }

    @Test(arguments: ["PL", "GB", "DE", "FR", "JP", "AU"])
    func otherRegionsDefaultToA4(region: String) {
        #expect(PageSizeOption.defaultSize(forRegion: region) == .a4)
    }

    @Test func unknownOrMissingRegionDefaultsToA4() {
        #expect(PageSizeOption.defaultSize(forRegion: nil) == .a4)
        #expect(PageSizeOption.defaultSize(forRegion: "") == .a4)
        #expect(PageSizeOption.defaultSize(forRegion: "ZZ") == .a4)
    }
}
