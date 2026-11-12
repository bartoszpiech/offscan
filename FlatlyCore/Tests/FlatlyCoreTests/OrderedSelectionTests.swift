import Testing
@testable import FlatlyCore

struct OrderedSelectionTests {
    @Test func toggleKeepsSelectionOrder() {
        var selection = OrderedSelection<Int>()
        selection.toggle(3)
        selection.toggle(1)
        selection.toggle(2)
        #expect(selection.ids == [3, 1, 2])
        #expect(selection.count == 3 && !selection.isEmpty)
        #expect(selection.contains(1) && !selection.contains(4))
    }

    @Test func toggleOffAndOnAgainMovesToTheEnd() {
        var selection = OrderedSelection([1, 2, 3])
        selection.toggle(1)
        #expect(selection.ids == [2, 3])
        selection.toggle(1)
        #expect(selection.ids == [2, 3, 1])
    }

    @Test func selectAppendsOnlyMissingIDs() {
        var selection = OrderedSelection([2, 5])
        selection.select([1, 2, 3, 5, 3])
        #expect(selection.ids == [2, 5, 1, 3])
    }

    @Test func retainPrunesAndKeepsOrder() {
        var selection = OrderedSelection([4, 1, 3, 2])
        selection.retain(only: [2, 3, 4])
        #expect(selection.ids == [4, 3, 2])
        selection.removeAll()
        #expect(selection.isEmpty)
    }

    @Test func initRemovesDuplicates() {
        #expect(OrderedSelection([1, 2, 1, 3, 2]).ids == [1, 2, 3])
    }

    @Test func positionFollowsSelectionOrder() {
        var selection = OrderedSelection<String>()
        selection.toggle("a")
        selection.toggle("b")
        selection.toggle("c")
        #expect(selection.position(of: "a") == 1)
        #expect(selection.position(of: "b") == 2)
        #expect(selection.position(of: "c") == 3)
        #expect(selection.position(of: "z") == nil)
    }

    @Test func deselectingRenumbersTheRest() {
        var selection = OrderedSelection(["a", "b", "c"])
        selection.toggle("b")
        #expect(selection.position(of: "a") == 1)
        #expect(selection.position(of: "b") == nil)
        #expect(selection.position(of: "c") == 2)
    }

    @Test func selectAllNumbersNewIDsAfterExistingOnes() {
        var selection = OrderedSelection(["c"])
        selection.select(["a", "b", "c"])
        #expect(selection.position(of: "c") == 1)
        #expect(selection.position(of: "a") == 2)
        #expect(selection.position(of: "b") == 3)
        selection.retain(only: ["b", "c"])
        #expect(selection.position(of: "c") == 1)
        #expect(selection.position(of: "a") == nil)
        #expect(selection.position(of: "b") == 2)
    }

    @Test func firstIsTheFirstSelected() {
        var selection = OrderedSelection<String>()
        #expect(selection.first == nil)
        selection.toggle("b")
        selection.toggle("a")
        #expect(selection.first == "b")
    }
}
