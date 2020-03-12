import Foundation

//Base Protocol
public protocol TimePath {
    var yearElement:Int { get }
	var monthElement:Int { get }
	var dayElement:Int { get }
	var hourElement:Int { get }
    var preciseGMTISO:String { get }
}

fileprivate let indexFilename = ".index-file"

public enum TimePrecision:UInt8 {
	case annual = 1
	case monthly = 2
	case daily = 3
	case hourly = 4
    
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

public struct TimeStruct: TimePath, Codable, Hashable, Comparable {
    enum CodingKeys: CodingKey {
        case yearElement
        case monthName
        case monthElement
        case dayElement
		case hourElement
        case preciseGMTISO
    }
    
    enum TimeStructInitError:Error {
    	case invalidGMTISOString
    }
    
    public var yearElement:Int
    public var monthElement: Int
    public var dayElement: Int
    public var hourElement: Int
    
    public var preciseGMTISO: String
    
    //MARK: Codable functions
    public init(from decoder:Decoder) throws {
        let values = try decoder.container(keyedBy:CodingKeys.self)
        yearElement = try values.decode(Int.self, forKey: .yearElement)
        monthElement = try values.decode(Int.self, forKey: .monthElement)
        dayElement = try values.decode(Int.self, forKey: .dayElement)
        hourElement = try values.decode(Int.self, forKey: .hourElement)
        preciseGMTISO = try values.decode(String.self, forKey: .preciseGMTISO)
    }
    
    public func encode(to encoder:Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(yearElement, forKey: .yearElement)
        try container.encode(monthElement, forKey: .monthElement)
        try container.encode(dayElement, forKey: .dayElement)
        try container.encode(hourElement, forKey: .hourElement)
        try container.encode(preciseGMTISO, forKey: .preciseGMTISO)
    }
    
    public init(_ input:TimePath, distill:TimePrecision? = nil) {
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
    
    public init(isoString:String) throws {
    	guard let inputDate = Date.fromISOString(isoString) else {
    		print(Colors.Red("TToolkit could not convert this ISO GMT string"))
    		throw TimeStructInitError.invalidGMTISOString
    	}
    	yearElement = inputDate.yearElement
		monthElement = inputDate.monthElement
		dayElement = inputDate.dayElement
		hourElement = inputDate.hourElement
		preciseGMTISO = isoString
    }
	    
    public init(yearElement:Int, monthElement:Int, dayElement:Int, hourElement:Int, preciseGMTISO:String) {
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
		print(Colors.yellow("Comparing two TimeStructs using < operator."))
		print(Colors.dim("\(lhs.described())\t\(rhs.described())"))
		print(Colors.green("y:\(lhs.yearElement)\t\(rhs.yearElement)"))
		print(Colors.green("m:\(lhs.monthElement)\t\(rhs.monthElement)"))
		print(Colors.green("d:\(lhs.dayElement)\t\(rhs.dayElement)"))
		print(Colors.green("h:\(lhs.hourElement)\t\(rhs.hourElement)"))
        if (lhs.yearElement < rhs.yearElement) {
        	print(Colors.Green("-> Eval (year): TRUE <"))
            return true
        } else if (lhs.yearElement > rhs.yearElement) {
            print(Colors.Green("-> Eval (year): FALSE <"))
            return false
        }
        
        if (lhs.monthElement < rhs.monthElement) {
			print(Colors.Green("-> Eval (month): TRUE <"))
            return true
        } else if (lhs.monthElement > rhs.monthElement) {
			print(Colors.Green("-> Eval (month): FALSE <"))
            return false
        }
        
        if (lhs.dayElement < rhs.dayElement) {
            print(Colors.Green("-> Eval (day): TRUE <"))
        	return true
        } else if (lhs.dayElement > rhs.dayElement) {
            print(Colors.Green("-> Eval (day): FALSE <"))
        	return false
        }
        
        if (lhs.hourElement < rhs.hourElement) {
            print(Colors.Green("-> Eval (hour): FALSE <"))
            return true
        }
        print(Colors.cyan("-> Eval (fallback): FALSE <"))
		return false
    }

    static public func <= (lhs:TimeStruct, rhs:TimeStruct) -> Bool {
        return (lhs < rhs) || (lhs == rhs)
    }
    
    static public func >= (lhs:TimeStruct, rhs:TimeStruct) -> Bool {
        return (lhs > rhs) || (lhs == rhs)
    }
    
    static public func > (lhs:TimeStruct, rhs:TimeStruct) -> Bool {
		print(Colors.yellow("Comparing two TimeStructs using > operator."))
		print(Colors.dim("\(lhs.described())\t\(rhs.described())"))
		print(Colors.green("y:\(lhs.yearElement)\t\(rhs.yearElement)"))
		print(Colors.green("m:\(lhs.monthElement)\t\(rhs.monthElement)"))
		print(Colors.green("d:\(lhs.dayElement)\t\(rhs.dayElement)"))
		print(Colors.green("h:\(lhs.hourElement)\t\(rhs.hourElement)"))

        if (lhs.yearElement > rhs.yearElement) {
			print(Colors.Green("-> Eval (year): TRUE >"))
            return true
        } else if (lhs.yearElement < rhs.monthElement) {
        	print(Colors.Green("-> Eval (year): FALSE >"))
            return false
        } else if lhs.yearElement == rhs.yearElement {
        	print(Colors.dim("*punting* (year)"), terminator:"")
        }
        
        if (lhs.monthElement > rhs.monthElement) {
			print(Colors.Green("-> Eval (month): TRUE >"))
            return true
        } else if (lhs.monthElement < rhs.monthElement) {
        	print(Colors.Green("-> Eval (month): FALSE >"))
            return false
        } else if (lhs.monthElement == rhs.monthElement) {
        	print(Colors.dim("*punting* (month)"))
        }
        
        if (lhs.dayElement > rhs.dayElement) {
        	print(Colors.Green("-> Eval (day): TRUE >"))
        	return true
        } else if (lhs.dayElement < rhs.dayElement) {
        	print(Colors.Green("-> Eval (day): FLASE >"))
        	return false
        } else {
        	print(Colors.dim("*punting* (day)"))
		}
        
        if (lhs.hourElement > rhs.hourElement) {
        	print(Colors.Green("-> Eval (hour): TRUE >"))
            return true
        }
        print(Colors.Green("-> Eval (fallback): FALSE >"))
		return false
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

//Equating to Strings
public extension TimePath {
	public var monthName:String {
        get {
            switch monthElement {
            case 1:
                return "January"
            case 2:
                return "February"
            case 3:
                return "March"
            case 4:
                return "April"
            case 5:
                return "May"
            case 6:
                return "June"
            case 7:
                return "July"
            case 8:
                return "August"
            case 9:
                return "September"
            case 10:
                return "October"
            case 11:
                return "November"
            case 12:
                return "December"
            default:
                return ""
            }
        }
    }

	public func described(toPrecision precision:TimePrecision = .hourly) -> String {
        switch precision {
        case .hourly:
            return "\(yearElement)-\(monthElement). \(monthName)-\(dayElement)-\(hourElement)"
        case .daily:
            return "\(yearElement)-\(monthElement). \(monthName)-\(dayElement)"
        case .monthly:
            return "\(yearElement)-\(monthElement). \(monthName)"
        default:
            return "\(yearElement)"
        }
    }
            
	internal func theoreticalTimePath(precision:TimePrecision, for baseDirectory:URL) -> URL {
        switch precision {
        case .hourly:
            return baseDirectory.appendingPathComponent(String(yearElement), isDirectory:true).appendingPathComponent(String(monthElement) + ". " + String(monthName), isDirectory: true).appendingPathComponent(String(dayElement), isDirectory: true).appendingPathComponent(String(hourElement), isDirectory:true)
        case .daily:
            return baseDirectory.appendingPathComponent(String(yearElement), isDirectory:true).appendingPathComponent(String(monthElement) + ". " + String(monthName), isDirectory: true).appendingPathComponent(String(dayElement), isDirectory: true)
        case .monthly:
            return baseDirectory.appendingPathComponent(String(yearElement), isDirectory:true).appendingPathComponent(String(monthElement) + ". " + String(monthName), isDirectory:true)
        case .annual:
            return baseDirectory.appendingPathComponent(String(yearElement), isDirectory:true)
        }
    }
    
    internal func verifyIndicies(precision:TimePrecision, for baseDirectory:URL) throws {
    	let fm = FileManager()
		//enumerate through the stack of the specified precision
		for (_, curPrecision) in precision.stack.enumerated() {
    		let directory = self.theoreticalTimePath(precision:curPrecision, for:baseDirectory).deletingLastPathComponent()
    		let indexFile = directory.appendingPathComponent(indexFilename, isDirectory:false)
    		
    		var indexObject = try serializeJSON([String:[String]].self, file:indexFile)
    		
    		for (_, curChildFolder) in indexObject.enumerated() {
    			let folderToCheck = directory.appendingPathComponent(curChildFolder.key, isDirectory:false)
    			if fm.fileExists(atPath:folderToCheck.path) == true {
    				//child folder exists, now validate the subfolders of that
    				for (_, curChildFolderContent) in curChildFolder.value.enumerated() {
    					let folderToCheck = directory
    				}
    			} else {
    				indexObject[curChildFolder.key] = nil
    			}
    		}
		}    	
    }
    
    internal func updateIndicies(precision:TimePrecision, for baseDirectory:URL) throws {
    	//enumerate through the stack of the specified precision
		for (n, curPrecision) in precision.stack.enumerated() {
			if curPrecision != .annual { //first item in the stack is always .annual, which we are skipping
				//detemine which directory we are going to load the index file from
				let directory:URL
				switch curPrecision { 
					case .monthly:
					directory = baseDirectory
					case .daily:
					directory = self.theoreticalTimePath(precision:.annual, for:baseDirectory)
					case .hourly:
					directory = self.theoreticalTimePath(precision:.monthly, for:baseDirectory)
					case .annual:
					fatalError("Annual time precisions should not be indexed")
				}
				let indexFile = directory.appendingPathComponent(indexFilename, isDirectory:false)
			
				//try reading the index file from disk
				var indexObject:[String:[String]]
				do {
					indexObject = try serializeJSON([String:[String]].self, file:indexFile)
				} catch _ {
					indexObject = [String:[String]]()
				}
				
				//this is the function that will insert a new index value into the loaded index data
				func insertInIndex(key:Int, value:Int) {
					let keyString = String(key)
					let valueString = String(value)
					if var existingContents = indexObject[keyString] {
						if (existingContents.contains(valueString) == false) {
							existingContents.append(valueString)
							indexObject[keyString] = existingContents
						}
					} else {
						indexObject[keyString] = [valueString]
					}
				}
				
				//insert the appropriate timepath elements based on the current precision
				switch curPrecision {
				case .hourly:
					insertInIndex(key:dayElement, value:hourElement)
				case .daily:
					insertInIndex(key:monthElement, value:dayElement)
				case .monthly:
					insertInIndex(key:yearElement, value:monthElement)
				case .annual:
					fatalError("Annual time precisions should not be indexed")
				}
			
				try serializeJSON(object:indexObject, file:indexFile)
			}
		}
    }
}
