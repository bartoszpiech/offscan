import Testing
import CoreGraphics
@testable import FlatlyCore

struct PageRendererTests {
    @Test func cropFilterRotateRecipe() throws {
        // 1000×800, red square in the top-left 200×200, dark grey elsewhere at the bottom.
        let original = Synthetic.image(width: 1000, height: 800, background: Synthetic.gray(1)) { ctx in
            ctx.setFillColor(Synthetic.red)
            ctx.fill(Synthetic.flip(CGRect(x: 0, y: 0, width: 200, height: 200), height: 800))
            ctx.setFillColor(Synthetic.gray(0.2))
            ctx.fill(Synthetic.flip(CGRect(x: 0, y: 700, width: 1000, height: 100), height: 800))
        }
        // Crop the top half (500×400 px from the top-left), grayscale, quarter turn clockwise.
        let recipe = PageRenderRecipe(cropRect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5), filter: .grayscale, rotation: .quarter)
        let out = try PageRenderer().render(original, recipe: recipe)
        #expect(out.width == 400 && out.height == 500)
        let bmp = Bitmap(out)
        // The (former red, now grey) square is in the top-right after the clockwise turn.
        let corner = bmp[out.width - 30, 30]
        #expect(corner.luminance < 200)
        #expect(abs(Int(corner.r) - Int(corner.g)) <= 2)
        // The dark bottom strip was cropped away, so the rest is white.
        #expect(bmp[30, out.height - 30].luminance > 240)
    }

    @Test func fullCropRectIsIgnored() throws {
        let original = Synthetic.redCornerImage(width: 300, height: 200)
        let recipe = PageRenderRecipe(cropRect: CGRect(x: 0, y: 0, width: 1, height: 1), filter: .original, rotation: .none)
        let out = try PageRenderer().render(original, recipe: recipe)
        #expect(out === original)
    }

    @Test func defaultRecipeKeepsSize() throws {
        let original = Synthetic.redCornerImage(width: 300, height: 200)
        let out = try PageRenderer().render(original, recipe: .default)
        #expect(out.width == 300 && out.height == 200)
        #expect(Bitmap(out)[10, 10].isRed)
    }
}
