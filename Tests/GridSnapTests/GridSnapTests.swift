import Testing
@testable import GridSnap

@Test func gridConfigurationDefaults() {
    let config = GridConfiguration.default
    #expect(config.rows == 3)
    #expect(config.cols == 3)
    #expect(config.gap == 0)
    #expect(config.padding == 0)
}

@Test func gridConfigurationPresets() {
    let presets = GridConfiguration.presets
    #expect(presets.count == 3)
    #expect(presets[0].name == "2x2")
    #expect(presets[1].name == "2x3")
    #expect(presets[2].name == "2x4")
    #expect(presets[2].config.cols == 4)
    #expect(presets[2].config.rows == 2)
}

@Test func gridCellEquality() {
    let a = GridCell(row: 1, col: 2)
    let b = GridCell(row: 1, col: 2)
    let c = GridCell(row: 0, col: 2)
    #expect(a == b)
    #expect(a != c)
}
