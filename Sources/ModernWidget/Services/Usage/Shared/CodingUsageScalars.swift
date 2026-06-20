extension UInt64 {
    func saturatingSubtract(_ other: UInt64) -> UInt64 {
        self >= other ? self - other : 0
    }
}

extension String {
    /// The string unless it is empty, mirroring the loaders' "treat blank as absent".
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
