import XCTest
@testable import CursorCat

final class CSVParserTests: XCTestCase {
    func testStreamingRecordsHandleQuotedCommasNewlinesAndEscapedQuotes() {
        let csv = [
            #"Date,Model,Cost,Note"#,
            #"2026-04-19T09:00:00Z,"composer,2","$1.25","line one"#,
            #"line two""#,
            #"2026-04-19T10:00:00Z,gpt-5.5,"Included","said ""hi""""#
        ].joined(separator: "\n")

        var records: [[String: String]] = []
        CSVParser.forEachRecord(in: csv) { records.append($0) }

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0]["Model"], "composer,2")
        XCTAssertEqual(records[0]["Note"], "line one\nline two")
        XCTAssertEqual(records[1]["Cost"], "Included")
        XCTAssertEqual(records[1]["Note"], "said \"hi\"")
    }
}
