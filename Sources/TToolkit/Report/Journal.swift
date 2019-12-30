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
    
    init(_ input:TimePath, distill:TimePrecision? = nil) {
		preciseGMTISO = input.preciseGMTISO
		
    	switch distill {
		case .daily:
			yearElement = input.yearElement
			monthElement = input.monthElement
			dayElement = input.dayElement
			
			hourElement = 0
			
		case .monthly:
			yearElement = input.yearElement
			monthElement = input.monthElement
			
			dayElement = 0
			hourElement = 0
			
		case .annual:
			yearElement = input.yearElement
			
			monthElement = 0
			dayElement = 0
			hourElement = 0
			
		default:
			yearElement = input.yearElement
			monthElement = input.monthElement
			dayElement = input.dayElement
			hourElement = input.hourElement

    	}
    }
	    
    init(yearElement:Int, monthElement:Int, dayElement:Int, hourElement:Int, preciseGMTISO:String) {
        self.yearElement = yearElement
        self.monthElement = monthElement
        self.dayElement = dayElement
        self.hourElement = hourElement
        self.preciseGMTISO = preciseGMTISO
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

private func write(date:TimePath, to thisURL:URL) throws {
	let isoData = try date.preciseGMTISO.safeData(using:.utf8)
	try isoData.write(to:thisURL)
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

public struct JournalFrame: Comparable, Hashable {
	private let _time:TimeStruct	
	public var time:TimePath {
		get {
			return _time
		}
	}
	
	public let directory:URL
	public let precision:TimePrecision
	
	fileprivate init(time:TimePath, journal:Journal) {
		self._time = TimeStruct(time, distill:journal.precision)
		self.directory = self._time.theoreticalTimePath(precision:journal.precision, for:journal.directory)
		self.precision = journal.precision
	}
	
	//MARK: Hashable Protocol
	public func hash(into hasher:inout Hasher) {
		switch precision {
			case .hourly:
			hasher.combine(time.yearElement)
			hasher.combine(time.monthElement)
			hasher.combine(time.dayElement)
			hasher.combine(time.hourElement)
			
			case .daily:
			hasher.combine(time.yearElement)
			hasher.combine(time.monthElement)
			hasher.combine(time.dayElement)
			
			case .monthly:
			hasher.combine(time.yearElement)
			hasher.combine(time.monthElement)
			
			case .annual:
			hasher.combine(time.yearElement)
		}
		
		hasher.combine(directory.path)
		hasher.combine(precision)
	}
	
	//MARK: Comparable Protocol
	public static func < (lhs:JournalFrame, rhs:JournalFrame) -> Bool {
		return lhs._time < rhs._time
	}
	public static func > (lhs:JournalFrame, rhs:JournalFrame) -> Bool {
		return lhs._time > rhs._time
	}
	public static func == (lhs:JournalFrame, rhs:JournalFrame) -> Bool {
		return lhs._time == rhs._time
	}
	public static func >= (lhs:JournalFrame, rhs:JournalFrame) -> Bool {
		return lhs._time >= rhs._time
	}
	public static func <= (lhs:JournalFrame, rhs:JournalFrame) -> Bool {
		return lhs._time <= rhs._time
	}
}

public enum FrameTarget { 
	case itterateBackwards(UInt)
	case dateOnOrBefore(TimePath)
}

//the journal object allows for data to be recorded in a linear fashion through time
public class Journal {
    public enum JournalerError: Error {
        case unableToFindLastAvailable
        case journalTailReached(URL)
        case headAlreadyExists
        case missingHead
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
	
	private var currentHead:TimeStruct?
	public var currentHeadURL:URL?
	
	//URL Related Variables
    private static let latestTimeRepName:String = ".latest.timerep.json"
    private static let previousTimeRepName:String = ".previous.timerep.json"
    private static let creationTimestamp:String = ".creation-timestamp.iso"
    private var latestDirectoryPath:URL		//this represents the path where the "latest" timepath is stored on disk
        
    //MARK: Private Functions
    //This function assumes the input TimeStruct has a theoretical timepath that exists given the journalers directory and precision
    fileprivate func enumerateBackwards(from thisTime:TimeStruct, using enumeratorFunction:InternalJournalEnumerator) throws -> TimeStruct {
    	var dateToTarget:TimeStruct = thisTime
    	var fileToCheck:URL? = nil
    	var i:UInt = 0
    	var response:JournalEnumerationResponse
    	repeat {
    		if (i > 0) {
    			dateToTarget = try JSONDecoder.decodeBinaryJSON(file:fileToCheck!, type:TimeStruct.self)
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
        
    //Progresses the journal with a new directory representing current time
    fileprivate func writeNewHead(with nowDate:TimePath = Date()) throws -> TimeStruct {
		let pathAsStructure = TimeStruct(nowDate)
		let newDirectory = pathAsStructure.theoreticalTimePath(precision:precision, for:directory)
		if (FileManager.default.fileExists(atPath: newDirectory.path) == false) {
			try FileManager.default.createDirectory(at:newDirectory, withIntermediateDirectories:true, attributes:nil)
			if (FileManager.default.fileExists(atPath: latestDirectoryPath.path) == true) {
				let previousTimeRep = try JSONDecoder.decodeBinaryJSON(file:latestDirectoryPath, type:TimeStruct.self)
				try previousTimeRep.encodeBinaryJSON(file:newDirectory.appendingPathComponent(Journal.previousTimeRepName))
			}
			try pathAsStructure.encodeBinaryJSON(file:latestDirectoryPath)
			try write(date:nowDate, to:newDirectory.appendingPathComponent(Journal.creationTimestamp))
			try pathAsStructure.updateIndicies(precision:precision, for:directory)
			currentHead = pathAsStructure
			currentHeadURL = pathAsStructure.theoreticalTimePath(precision:precision, for:directory)
			return pathAsStructure
		} else {
			throw JournalerError.headAlreadyExists
		}
    }
    
	//For searching x number of directory iterations before the present head
    fileprivate func loadFrame(backFromHead foldersBack:UInt = 0) throws -> JournalFrame {
    	guard let headStruct = currentHead else {
    		throw JournalerError.missingHead
    	}
    	
    	var i = 0
    	let terminatedStruct = try enumerateBackwards(from:headStruct, using: { path, time -> JournalEnumerationResponse in
    		if (foldersBack <= i) {
    			return .terminate
    		} else {
    			i += 1
    			return .proceed
    		}
    	})
    	return try JournalFrame(time:terminatedStruct, journal:self)
    }
    
	//For searching for a particular timepath closest to a particular head
    fileprivate func loadFrame(onOrBefore date:TimePath) throws -> JournalFrame {
    	guard let headStruct = currentHead else {
    		throw JournalerError.missingHead
    	}
    	
    	let inputAsTimeStruct = TimeStruct(date)
    	let terminatedStruct = try enumerateBackwards(from: headStruct, using: { path, thisTime -> JournalEnumerationResponse in
    		if (thisTime <= inputAsTimeStruct) {
    			return .terminate
    		} else {
    			return .proceed
    		}
    	})
    	return try JournalFrame(time:terminatedStruct, journal:self)
    }
    
    //MARK: Public Functions
	public init(directory:URL, precision requestedPrecision:TimePrecision) {
        self.directory = directory
        precision = requestedPrecision
        
		latestDirectoryPath = directory.appendingPathComponent(Journal.latestTimeRepName, isDirectory:false)
        currentHead = try? JSONDecoder.decodeBinaryJSON(file: latestDirectoryPath, type:TimeStruct.self)
        currentHeadURL = currentHead?.theoreticalTimePath(precision:precision, for:directory)
    }
    
    public func loadFrame(_ target:FrameTarget) throws -> JournalFrame {
    	switch target {
		case let .itterateBackwards(steps):
    		return try loadFrame(backFromHead:steps)
    	case let .dateOnOrBefore(thisDate):
    		return try loadFrame(onOrBefore:thisDate)
    	}
    }
        
    public func advanceHead(using inputDate:TimePath = Date()) throws -> JournalFrame {
    	do {
    		let newTime = try writeNewHead(with: inputDate)
    		return try JournalFrame(time:newTime, journal:self)
    	} catch let error {
    		switch error {
			case JournalerError.headAlreadyExists:
    			guard let hasHead = currentHead else {
    				throw error
    			}
    			return JournalFrame(time:hasHead, journal:self)
    		default:
    			throw error
    		}
    	}
    }
    
    public func enumerateBackwards(using enumFunction:JournalEnumerator) throws -> URL {
    	guard let headStruct = currentHead else {
    		throw JournalerError.missingHead
    	}
    	return try enumerateBackwards(from:headStruct, using:enumFunction).theoreticalTimePath(precision:precision, for:directory)
    }
}
