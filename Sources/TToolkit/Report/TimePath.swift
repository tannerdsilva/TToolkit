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
//
//internal struct TimePathIndex:Codable {
//	enum CodingKeys:CodingKey {
//		case rangeMinimum
//		case rangeMaximum
//		case directoryContents
//	}
//
//	var rangeMinimum:TimeStruct
//	var rangeMaximum:TimeStruct
//	
//	var directoryContents:[String:[String]]
//	
//	init(from decoder:Decoder) throws {
//		let values = try decoder.container(keyedBy:CodingKeys.self)
//		rangeMinimum = try values.decode(TimeStruct.self, forKey:.rangeMinimum)
//		rangeMaximum = try values.decode(TimeStruct.self, forKey:.rangeMaximum)
//		directoryContents = try values.decode([String:[String]].self, forKey:.directoryContents)
//	}
//
//	func encode(to encoder:Encoder) throws {
//		var container = encoder.container(keyedBy:CodingKeys.self)
//		try container.encode(rangeMinimum, forKey:CodingKeys.rangeMinimum)
//		try container.encode(rangeMaximum, forKey:CodingKeys.rangeMaximum)
//		try container.encode(directoryContents, forKey:CodingKeys.directoryContents)
//	}
//}
//
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
            return baseDirectory.appendingPathComponent(String(yearElement), isDirectory: true).appendingPathComponent(String(monthElement), isDirectory: true).appendingPathComponent(String(dayElement), isDirectory: true).appendingPathComponent(String(hourElement), isDirectory:true)
        case .daily:
            return baseDirectory.appendingPathComponent(String(yearElement), isDirectory: true).appendingPathComponent(String(monthElement), isDirectory: true).appendingPathComponent(String(dayElement), isDirectory: true)
        case .monthly:
            return baseDirectory.appendingPathComponent(String(yearElement), isDirectory:true).appendingPathComponent(String(monthElement), isDirectory:true)
        case .annual:
            return baseDirectory.appendingPathComponent(String(yearElement), isDirectory:true)
        }
    }
    
    internal func updateIndicies(precision:TimePrecision, for baseDirectory:URL) throws {
    	//enumerate through the stack of the specified precision
		for (_, curPrecision) in precision.stack.enumerated() {
			let directory = self.theoreticalTimePath(precision:precision, for:baseDirectory).deletingLastPathComponent()
			let indexFile = directory.appendingPathComponent(indexFilename, isDirectory:false)
			
			var indexObject:[String:[String]]
			do {
				indexObject = try serializeJSON([String:[String]].self, file:indexFile)
			} catch _ {
				indexObject = [String:[String]]()
			}

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
			
			switch curPrecision {
			case .daily:
				insertInIndex(key:dayElement, value:hourElement)
			case .monthly:
				insertInIndex(key:monthElement, value:dayElement)
			case .annual:
				insertInIndex(key:yearElement, value:monthElement)
			default:
				break;
			}
			
			try serializeJSON(object:indexObject, file:indexFile)
		}
		
		
    }
}
