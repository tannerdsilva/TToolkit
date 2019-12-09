import Foundation

public enum TimePrecision {
    case hourly
    case daily
    case monthly
    case annual
}

private struct TimeStruct: TimePath, Codable, Hashable {
    enum CodingKeys: CodingKey {
        case yearElement
        case monthName
        case monthElement
        case dayElement
        case hourElement
        case preciseGMTISO
    }
    var yearElement:Int
    var monthElement: Int
    var dayElement: Int
    var hourElement: Int
    var preciseGMTISO: String
    init(from decoder:Decoder) throws {
        let values = try decoder.container(keyedBy:CodingKeys.self)
        yearElement = try values.decode(Int.self, forKey: .yearElement)
        monthElement = try values.decode(Int.self, forKey: .monthElement)
        dayElement = try values.decode(Int.self, forKey: .dayElement)
        hourElement = try values.decode(Int.self, forKey: .hourElement)
        preciseGMTISO = try values.decode(String.self, forKey: .preciseGMTISO)
    }
    func encode(to encoder:Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(yearElement, forKey: .yearElement)
        try container.encode(monthElement, forKey: .monthElement)
        try container.encode(dayElement, forKey: .dayElement)
        try container.encode(hourElement, forKey: .hourElement)
        try container.encode(preciseGMTISO, forKey: .preciseGMTISO)
    }
    init(_ input:TimePath) {
        yearElement = input.yearElement
        monthElement = input.monthElement
        dayElement = input.dayElement
        hourElement = input.hourElement
        preciseGMTISO = input.preciseGMTISO
    }
    init(yearElement:Int, monthElement:Int, dayElement:Int, hourElement:Int, preciseGMTISO:String) {
        self.yearElement = yearElement
        self.monthElement = monthElement
        self.dayElement = dayElement
        self.hourElement = hourElement
        self.preciseGMTISO = preciseGMTISO
    }
    public static func fromWrittenState(url:URL) throws -> TimeStruct {
         let decoder = JSONDecoder()
         let dataToDecode = try Data(contentsOf:url)
         return try decoder.decode(TimeStruct.self, from:dataToDecode)
    }
    public func writeTo(url:URL) throws {
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(self)
        try jsonData.write(to:url)
    }
    public func hash(into hasher:inout Hasher) {
        hasher.combine(yearElement)
        hasher.combine(monthElement)
        hasher.combine(dayElement)
        hasher.combine(hourElement)
    }
}

fileprivate let calendar = Calendar.current
extension Date: TimePath {
	public var yearElement:Int {
		return calendar.component(.year, from:self)
	}
	
	public var monthElement:Int {
		return calendar.component(.month, from:self)
	}
	
	public var dayElement:Int {
		return calendar.component(.day, from:self)
	}
	
	public var hourElement:Int {
		return calendar.component(.hour, from:self)
	}
    
    public var preciseGMTISO: String {
        return self.isoString
    }
}

private enum DateEncodingError:Error {
    case malformedData
    case noFileFound
}
private func write(date:Date, to thisURL:URL) throws {
    let isoString = date.isoString
    guard let isoData = isoString.data(using:.utf8) else {
        throw DateEncodingError.malformedData
    }
    try isoData.write(to: thisURL)
}
private func readDate(from thisURL:URL) throws -> Date {
    let urlData = try Data(contentsOf:thisURL)
    guard let dateString = String(data:urlData, encoding:.utf8) else {
        throw DateEncodingError.malformedData
    }
    guard let parsedDate = Date.fromISOString(dateString) else {
        throw DateEncodingError.malformedData
    }
    return parsedDate
}

public struct Journal {
    public enum JournalerError: Error {
        case unableToFindLastAvailable
        case journalTailReached(URL)
    }
    
    public let directory:URL
    private static let latestTimeRepName:String = ".latest.timerep.json"
    private static let previousTimeRepName:String = ".previous.timerep.json"
    private static let creationTimestamp:String = ".creation-timestamp.iso"
    private var latestDirectoryPath:URL {
        get {
            return directory.appendingPathComponent(Journal.latestTimeRepName, isDirectory:false)
        }
    }
    public let precision:TimePrecision
    
    public init(logDirectory:URL, precision requestedPrecision:TimePrecision) {
        directory = logDirectory
        precision = requestedPrecision
    }
    
    private func readLatest() throws -> TimeStruct {
        return try TimeStruct.fromWrittenState(url: directory.appendingPathComponent(Journal.latestTimeRepName))
    }
    
    public func directoryOnOrBefore(date:Date) throws -> URL {
        return try directoryOnOrBefore(date: TimeStruct(date))
    }
    
    private func directoryOnOrBefore(date:TimeStruct) throws -> URL {
        var dateToTarget:TimeStruct = try readLatest()
        var fileToCheck:URL?
        var i = 0
        repeat {
            if i > 0 {
                dateToTarget = try TimeStruct.fromWrittenState(url: fileToCheck!)
            }
            if (dateToTarget < date) {
                return dateToTarget.theoreticalTimePath(precision: precision, for:directory)
            }
            fileToCheck = dateToTarget.theoreticalTimePath(precision: precision, for:directory).appendingPathComponent(Journal.previousTimeRepName)
            i += 1
        } while (FileManager.default.fileExists(atPath: fileToCheck!.path) == true)
        throw JournalerError.journalTailReached(dateToTarget.theoreticalTimePath(precision: precision, for:directory))
    }
    
    public func enumerateFromPresentTo(date:Date, using thisFunction:(URL, Date) throws -> Void) throws {
        let timeRep = TimeStruct(date)
        var dateToTarget:TimeStruct = try readLatest()
        var fileToCheck:URL?
        var i = 0
        repeat {
            if i > 0 {
                dateToTarget = try TimeStruct.fromWrittenState(url: fileToCheck!)
            }
            if (dateToTarget < timeRep) {
                return
            }
            let targetedDirectory = dateToTarget.theoreticalTimePath(precision: precision, for: directory)
            let createDateURL = targetedDirectory.appendingPathComponent(Journal.creationTimestamp, isDirectory: false)
            let createDateData = try Data(contentsOf:createDateURL)
            if let createDateString = String(data:createDateData, encoding:.utf8), let parsedISODate = Date.fromISOString(createDateString) {
                try thisFunction(targetedDirectory, parsedISODate)
            }
            fileToCheck = targetedDirectory.appendingPathComponent(Journal.previousTimeRepName)
            i += 1
        } while (FileManager.default.fileExists(atPath: fileToCheck!.path) == true)
        throw JournalerError.journalTailReached(dateToTarget.theoreticalTimePath(precision: precision, for:directory))
    }
    
    public func advanceHead(withDate now:Date) throws -> URL {
        let timeRep = TimeStruct(now)
        let newDirectory = timeRep.theoreticalTimePath(precision:precision, for:directory)
        if (FileManager.default.fileExists(atPath: newDirectory.path) == false) {
            try FileManager.default.createDirectory(at: newDirectory, withIntermediateDirectories: true, attributes: nil)
            if (FileManager.default.fileExists(atPath: latestDirectoryPath.path) == true) {
                let previousTimeRep = try TimeStruct.fromWrittenState(url: latestDirectoryPath)
                try previousTimeRep.writeTo(url: newDirectory.appendingPathComponent(Journal.previousTimeRepName))
            }
            try timeRep.writeTo(url: latestDirectoryPath)
            try write(date:Date(), to:newDirectory.appendingPathComponent(Journal.creationTimestamp))
        }
        return newDirectory
    }
    
    public func findLatestDirectoryInPast() throws -> URL {
        return try directoryOnOrBefore(date: TimeStruct(Date()))
    }
    
    public func findHeadDirectory() throws -> URL {
    	return try readLatest().theoreticalTimePath(precision:precision, for:directory)
    }
    
    public func file(named fileName:String, onOrBefore thisDate:Date) throws -> Data {
        let timeRep = TimeStruct(thisDate)
        let immediateTheoretical = timeRep.theoreticalTimePath(precision: precision, for: directory).appendingPathComponent(fileName, isDirectory:false)
        if (FileManager.default.fileExists(atPath: immediateTheoretical.path) == true) {
            return try Data(contentsOf: immediateTheoretical)
        } else {
            let directoryForDate = try directoryOnOrBefore(date: timeRep)
            return try Data(contentsOf:directoryForDate.appendingPathComponent(fileName))
        }
    }
}
