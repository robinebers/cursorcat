import Foundation

/// Minimal CSV parser supporting quoted fields with embedded commas, newlines,
/// and escaped quotes (`""` → `"`). Returns rows as string arrays.
enum CSVParser {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var i = text.startIndex

        while i < text.endIndex {
            let c = text[i]

            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex && text[next] == "\"" {
                        field.append("\"")
                        i = text.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                        i = next
                        continue
                    }
                } else {
                    field.append(c)
                    i = text.index(after: i)
                    continue
                }
            }

            switch c {
            case "\"":
                inQuotes = true
            case ",":
                row.append(field)
                field = ""
            case "\r":
                break
            case "\n":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            default:
                field.append(c)
            }
            i = text.index(after: i)
        }

        // Trailing partial row.
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows.filter { !$0.allSatisfy { $0.isEmpty } }
    }

    /// Parse into `[rowDict]` keyed by header. Returns `[]` if no header row.
    static func parseRecords(_ text: String) -> [[String: String]] {
        let rows = parse(text)
        guard let header = rows.first else { return [] }
        return rows.dropFirst().map { row in
            var dict: [String: String] = [:]
            for (i, key) in header.enumerated() where i < row.count {
                dict[key] = row[i]
            }
            return dict
        }
    }
}
