import Foundation

private enum DateEncodingError:Error {
    case malformedData
    case noFileFound
}

fileprivate func write(date:TimePath, to thisURL:URL) throws {
	let isoData = try date.preciseGMTISO.safeData(using:.utf8)
	try isoData.write(to:thisURL)
}

fileprivate func readDate(from thisURL:URL) throws -> Date {
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
	public let time:TimeStruct	
	
	public let directory:URL
	public let precision:TimePrecision
	
	fileprivate init(time:TimeStruct, journal:Journal) {
		self.time = time
		self.directory = time.theoreticalTimePath(precision:journal.precision, for:journal.directory)
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
	}
	
	//MARK: Comparable Protocol
	public static func < (lhs:JournalFrame, rhs:JournalFrame) -> Bool {
		return lhs.time < rhs.time
	}
	public static func > (lhs:JournalFrame, rhs:JournalFrame) -> Bool {
		return lhs.time > rhs.time
	}
	public static func == (lhs:JournalFrame, rhs:JournalFrame) -> Bool {
		return lhs.time == rhs.time
	}
	public static func >= (lhs:JournalFrame, rhs:JournalFrame) -> Bool {
		return lhs.time >= rhs.time
	}
	public static func <= (lhs:JournalFrame, rhs:JournalFrame) -> Bool {
		return lhs.time <= rhs.time
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
        case unableToEnumerate
        case internalError
    }
    public enum JournalEnumerationResponse:UInt8 {
    	case proceed
    	case terminate
    }
    
    //Enumeration types for the journal
    public typealias JournalEnumerator = (URL, JournalFrame) throws -> JournalEnumerationResponse
    
    //two primary variables for this structure
    public let directory:URL
	public let precision:TimePrecision
	
	public var currentHead:TimeStruct?
	public var currentHeadURL:URL?
	
	//URL Related Variables
    private static let latestTimeRepName:String = ".latest.timerep.json"
    private static let previousTimeRepName:String = ".previous.timerep.json"
    private static let creationTimestamp:String = ".creation-timestamp.iso"
    private var latestDirectoryPath:URL		//this represents the path where the "latest" timepath is stored on disk
	
    //MARK: Private Functions
    //This function assumes the input TimeStruct has a theoretical timepath that exists given the journalers directory and precision
    public func enumerateBackwards(from thisTime:TimeStruct, using enumeratorFunction:JournalEnumerator) throws -> JournalFrame {
    	var dateToTarget:TimeStruct = thisTime
    	var fileToCheck:URL? = nil
    	var i:UInt = 0
    	var response:JournalEnumerationResponse
    	repeat {
    		if (i > 0) {
    			dateToTarget = try JSONDecoder.decodeBinaryJSON(file:fileToCheck!, type:TimeStruct.self)
    		}
    		fileToCheck = try dateToTarget.theoreticalTimePath(precision:precision, for:directory).appendingPathComponent(Journal.previousTimeRepName)			
    		response = try enumeratorFunction(fileToCheck!.deletingLastPathComponent(), JournalFrame(time:dateToTarget, journal:self))
    		if (response == .terminate) { 
    			return JournalFrame(time:dateToTarget, journal:self)
    		}
    		i += 1
    	} while (FileManager.default.fileExists(atPath:fileToCheck!.path) == true)
    	throw JournalerError.journalTailReached(dateToTarget.theoreticalTimePath(precision:precision, for:directory))
    }
    
    public func enumerateBackwards(using enumeratorFunction:JournalEnumerator) throws -> JournalFrame {
    	guard let ch = currentHead else {
    		throw JournalerError.missingHead
    	}
    	return try enumerateBackwards(from:ch, using:enumeratorFunction)
    }

    
    public func loadAllHeads() throws -> Set<JournalFrame> {
    	let suspectedDates = try findAllCreationDates()
    	
    	let journalFrameTransform = suspectedDates.explode(using: { (n, curItemURL) -> JournalFrame in
    		let timeData = try Data(contentsOf:curItemURL)
    		let dataToString = String(data:timeData, encoding:.utf8)
            if let hasString = dataToString, let dateObj = Date.fromISOString(hasString) {
                let timeStructFromDate = TimeStruct(dateObj)
                let jf = JournalFrame(time:timeStructFromDate, journal:self)
                return jf
            } else {
                throw JournalerError.internalError
            }
    	})
    	
    	return journalFrameTransform
    }
        
    internal func findAllCreationDates() throws -> [URL] {
    	let directoryPath = directory.path
    	guard let pathsToSearch = FileManager.default.enumerator(atPath:directoryPath) else {
    		throw JournalerError.unableToEnumerate
    	}
    	
    	var urlsToReturn = [URL]()
    	
    	for currentPath in pathsToSearch {
    		if let cpValidate = currentPath as? String {
				let elementURL = URL(fileURLWithPath:directoryPath + "/" + cpValidate).standardizedFileURL
                if elementURL.lastPathComponent == Self.creationTimestamp {
					urlsToReturn.append(elementURL)
				}
    		} else {
    			print(Colors.red("[DEBUG]\tJournal enumerated through a value that was considered to not be a string. This element was skipped."))
    		}
    	}
    	
    	return urlsToReturn
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
    	let terminatedFrame = try enumerateBackwards(from:headStruct, using: { path, time -> JournalEnumerationResponse in
    		if (foldersBack <= i) {
    			return .terminate
    		} else {
    			i += 1
    			return .proceed
    		}
    	})
    	return terminatedFrame
    }
    
	//For searching for a particular timepath closest to a particular head
    fileprivate func loadFrame(onOrBefore date:TimePath) throws -> JournalFrame {
    	guard let headStruct = currentHead else {
    		throw JournalerError.missingHead
    	}
    	
    	let inputAsTimeStruct = TimeStruct(date)
    	let terminatedFrame = try enumerateBackwards(from: headStruct, using: { path, thisTime -> JournalEnumerationResponse in
    		if (thisTime.time <= inputAsTimeStruct) {
    			return .terminate
    		} else {
    			return .proceed
    		}
    	})
    	return terminatedFrame
    }
    
    //MARK: Public Functions
	public init(directory:URL, precision requestedPrecision:TimePrecision) {
        self.directory = directory
        precision = requestedPrecision
        
		latestDirectoryPath = directory.appendingPathComponent(Journal.latestTimeRepName, isDirectory:false)
        currentHead = try? JSONDecoder.decodeBinaryJSON(file: latestDirectoryPath, type:TimeStruct.self)
        if (currentHead == nil) {
        	print(Colors.Red("[JOURNAL]\tJournal inialized with no head found."))
        }
        
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
}
