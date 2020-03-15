import Foundation


@available(macOS 10.12, *)
public extension Date {
    var isoString: String {
        return ISO8601DateFormatter().string(from:self)
    }
    
    static func fromISOString(_ isoString:String) -> Date? {
        return ISO8601DateFormatter().date(from: isoString)
    }
}

//shifting a date to a specified timezone
public extension Date {
    func convertTo(timezone:TimeZone, from firstTimezone:TimeZone) -> Date {
        let targetOffset = TimeInterval(timezone.secondsFromGMT(for: self))
        let localOffset = TimeInterval(TimeZone.autoupdatingCurrent.secondsFromGMT(for: self))
        return self.addingTimeInterval(targetOffset - localOffset)
    }
}
