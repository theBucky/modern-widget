extension UInt64 {
    func saturatingSubtract(_ other: UInt64) -> UInt64 {
        self >= other ? self - other : 0
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
