import FluentSQL

struct MySQLConverterDelegate: SQLConverterDelegate {
    func nestedFieldExpression(_ column: String, _ path: [String]) -> SQLExpression {
        let path = path.joined(separator: ".")
        return SQLRaw("JSON_EXTRACT(\(column), '$.\(path)')")
    }

    func customDataType(_ dataType: DatabaseSchema.DataType) -> SQLExpression? {
        switch dataType {
        case .string: return SQLRaw("VARCHAR(255)")
        case .datetime: return SQLRaw("DATETIME(6)")
        case .uuid: return SQLRaw("VARBINARY(16)")
        case .bool: return SQLRaw("BOOL")
        case .array: return SQLRaw("JSON")
        default: return nil
        }
    }
}
