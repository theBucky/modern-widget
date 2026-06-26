extension UInt64 {
    func saturatingAdd(_ other: UInt64) -> UInt64 {
        let (sum, overflow) = addingReportingOverflow(other)
        return overflow ? .max : sum
    }

    func saturatingSubtract(_ other: UInt64) -> UInt64 {
        self >= other ? self - other : 0
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
