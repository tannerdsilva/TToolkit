import Foundation

public enum TimePrecision {
    case hourly
    case daily
    case monthly
    case annual
    
    var stack:[TimePrecision] {
    	get {
    		switch self {
    			case .hourly:
    				return [.annual, .monthly, .daily, .hourly]
    			case .daily:
    				return [.annual, .monthly, .daily]
    			case .monthly:
    				return [.annual, .monthly]
    			case .annual:
    				return [.annual]
    		}
    	}
    }
}

internal struct TimeStruct: TimePath, Codable, Hashable, Comparable {
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
    public func hash(into hasher:inout Hasher) {
        hasher.combine(yearElement)
        hasher.combine(monthElement)
        hasher.combine(dayElement)
        hasher.combine(hourElement)
    }
    
	static public func < (lhs:TimeStruct, rhs:TimeStruct) -> Bool {
        if (lhs.yearElement < rhs.yearElement) {
            return true
        } else if (lhs.yearElement > rhs.yearElement) {
            return false
        }
        
        if (lhs.monthElement < rhs.monthElement) {
            return true
        } else if (lhs.monthElement > rhs.monthElement) {
            return false
        }
        
        if (lhs.dayElement < rhs.dayElement) {
        	return true
        } else if (lhs.dayElement > rhs.dayElement) {
        	return false
        }
        
        if (lhs.hourElement < rhs.hourElement) {
            return true
        } else if (lhs.hourElement > rhs.hourElement) {
            return false
        } else {
            return false
        }
    }

    static public func <= (lhs:TimeStruct, rhs:TimeStruct) -> Bool {
        return (lhs < rhs) || (lhs == rhs)
    }
    
    static public func >= (lhs:TimeStruct, rhs:TimeStruct) -> Bool {
        return (lhs > rhs) || (lhs == rhs)
    }
    
    static public func > (lhs:TimeStruct, rhs:TimeStruct) -> Bool {
        if (lhs.yearElement > rhs.yearElement) {
            return true
        } else if (lhs.yearElement < rhs.monthElement) {
            return false
        }
        
        if (lhs.monthElement > rhs.monthElement) {
            return true
        } else if (lhs.monthElement < rhs.monthElement) {
            return false
        }
        
        if (lhs.dayElement > rhs.dayElement) {
        	return true
        } else if (lhs.dayElement < rhs.dayElement) {
        	return false
        }
        
        if (lhs.hourElement > rhs.hourElement) {
            return true
        } else if (lhs.hourElement < rhs.hourElement) {
            return false
        } else {
            return false
        }
    }
    
    static public func == (lhs:TimeStruct, rhs:TimeStruct) -> Bool {
        return (lhs.yearElement == rhs.yearElement) && (lhs.monthElement == rhs.monthElement) && (lhs.hourElement == rhs.hourElement) && (lhs.dayElement == rhs.dayElement)
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
    public enum JournalEnumerationResponse:UInt8 {
    	case proceed
    	case terminate
    }
    
    //Enumeration types for the journal
    fileprivate typealias InternalJournalEnumerator = (URL, TimeStruct) throws -> JournalEnumerationResponse
    public typealias JournalEnumerator = (URL, TimePath) throws -> JournalEnumerationResponse
    
    //two primary variables for this structure
    public let directory:URL
	public let precision:TimePrecision
	
	//URL Related Variables
    private static let latestTimeRepName:String = ".latest.timerep.json"
    private static let previousTimeRepName:String = ".previous.timerep.json"
    private static let creationTimestamp:String = ".creation-timestamp.iso"
    private var latestDirectoryPath:URL {
        get {
            return directory.appendingPathComponent(Journal.latestTimeRepName, isDirectory:false)
        }
    }
    
    public init(directory:URL, precision requestedPrecision:TimePrecision) {
        self.directory = directory
        precision = requestedPrecision
    }
    
    //MARK: Private Functions
    //this function assumes the input TimeStruct has a theoretical timepath that exists given the journalers directory and precision
    fileprivate func enumerateBackwards(from thisTime:TimeStruct, using enumeratorFunction:InternalJournalEnumerator) throws -> TimeStruct {
    	var dateToTarget:TimeStruct = thisTime
    	var fileToCheck:URL? = nil
    	var i:UInt = 0
    	var response:JournalEnumerationResponse
    	repeat {
    		if (i > 0) {
    			dateToTarget = try TimeStruct.fromWrittenState(url: fileToCheck!)
    		}
    		fileToCheck = try dateToTarget.theoreticalTimePath(precision:precision, for:directory).appendingPathComponent(Journal.previousTimeRepName)			
    		response = try enumeratorFunction(fileToCheck!.deletingLastPathComponent(), dateToTarget)
    		if (response == .terminate) { 
    			return dateToTarget
    		}
    		i += 1
    	} while (FileManager.default.fileExists(atPath:fileToCheck!.path) == true)
    	throw JournalerError.journalTailReached(dateToTarget.theoreticalTimePath(precision:precision, for:directory))
    }
    
    //loads the journal head from disk
    private func readLatest() throws -> TimeStruct {
        return try TimeStruct.fromWrittenState(url: directory.appendingPathComponent(Journal.latestTimeRepName))
    }
    
    //progresses the journal with a new directory representing current time
    private func writeNewHead() throws -> TimeStruct {
    	let nowDate = Date()
		let pathAsStructure = TimeStruct(Date())
		let newDirectory = pathAsStructure.theoreticalTimePath(precision:precision, for:directory)
		if (FileManager.default.fileExists(atPath: newDirectory.path) == false) {
			try FileManager.default.createDirectory(at:newDirectory, withIntermediateDirectories:true, attributes:nil)
			if (FileManager.default.fileExists(atPath: latestDirectoryPath.path) == true) {
				let previousTimeRep = try TimeStruct.fromWrittenState(url: latestDirectoryPath)
				try previousTimeRep.encodeBinaryJSON(file:newDirectory.appendingPathComponent(Journal.previousTimeRepName))
			}
			try pathAsStructure.encodeBinaryJSON(file:latestDirectoryPath)
			try write(date:nowDate, to:newDirectory.appendingPathComponent(Journal.creationTimestamp))
			try pathAsStructure.updateIndicies(precision:precision, for:directory)
		}
		return pathAsStructure
    }
    
    //MARK: Public Functions
    //Searching for x amount of directories before the present head
    public func timePath(backFromHead foldersBack:UInt = 0) throws -> (time:TimePath, directory:URL) {
        var i = 0
        let terminatedStruct = try enumerateBackwards(from:try readLatest(), using: { path, time -> JournalEnumerationResponse in
        	if foldersBack <= i {
        		i += 1
        		return .terminate
        	} else {
        		i += 1
        		return .proceed
        	}
        })
        return (time:terminatedStruct, directory:terminatedStruct.theoreticalTimePath(precision:precision, for:directory))
    }
    
	public func directoryOnOrBefore(date inputDate:TimePath) throws -> (time:TimePath, directory:URL) {
    	let inputAsTimeStruct = TimeStruct(inputDate)
    	let terminatedTimeStruct = try enumerateBackwards(from:try readLatest(), using: { path, thisTime -> JournalEnumerationResponse in
    		if (thisTime <= inputAsTimeStruct) {
    			return .terminate
    		} else {
    			return .proceed
    		}
    	})
    	return (time:terminatedTimeStruct, directory:terminatedTimeStruct.theoreticalTimePath(precision:precision, for:directory))
    }
    
    public func advanceHead() throws -> URL {
    	let nowTimeStruct = try writeNewHead()
    	return nowTimeStruct.theoreticalTimePath(precision:precision, for:directory)
    }
    
    public func enumerateBackwards(using enumFunction:JournalEnumerator) throws -> URL {
    	let latest = try readLatest()
    	let terminatedTimeStruct = try enumerateBackwards(from:latest, using:enumFunction)
    	return terminatedTimeStruct.theoreticalTimePath(precision:precision, for:directory)
    }
}
