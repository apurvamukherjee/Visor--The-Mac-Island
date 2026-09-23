/// Two features had independently grown a private `clamp` helper of their own
/// before this existed, which is the signal that the shape was wanted. The
/// win is uniformity rather than line count: twenty-odd sites that each said
/// `min(max(x, lo), hi)` now read the same way.
extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
