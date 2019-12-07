import Foundation

//Base Protocol
public protocol TimePath {
    var yearElement:Int { get }
	var monthElement:Int { get }
	var dayElement:Int { get }
	var hourElement:Int { get }
    var preciseGMTISO:String { get }
}

//Equating to Strings
public extension TimePath {
	var monthName:String {
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
            return "\(yearElement)-\(monthElement)-\(dayElement)-\(hourElement)"
        case .daily:
            return "\(yearElement)-\(monthElement)-\(dayElement)"
        case .monthly:
            return "\(yearElement)-\(monthElement)"
        default:
            return "\(yearElement)"
        }
    }
    
	internal func theoreticalTimePath(precision:TimePrecision, for baseDirectory:URL) -> URL {
        switch precision {
        case .hourly:
            return baseDirectory.appendingPathComponent(String(yearElement), isDirectory: true).appendingPathComponent(described(toPrecision:.monthly), isDirectory: true).appendingPathComponent(String(dayElement), isDirectory: true).appendingPathComponent(String(hourElement), isDirectory:true)
        case .daily:
            return baseDirectory.appendingPathComponent(String(yearElement), isDirectory: true).appendingPathComponent(described(toPrecision:.monthly), isDirectory: true).appendingPathComponent(String(dayElement), isDirectory: true)
        case .monthly:
            return baseDirectory.appendingPathComponent(String(yearElement), isDirectory:true).appendingPathComponent(described(toPrecision:.monthly), isDirectory:true)
        case .annual:
            return baseDirectory.appendingPathComponent(String(yearElement), isDirectory:true)
        }
    }

}

//Equatable Protocol
extension TimePath {
	static public func < (lhs:Self, rhs:Self) -> Bool {
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

    static public func <= (lhs:Self, rhs:Self) -> Bool {
        return (lhs < rhs) || (lhs == rhs)
    }
    
    static public func >= (lhs:Self, rhs:Self) -> Bool {
        return (lhs > rhs) || (lhs == rhs)
    }
    
    static public func > (lhs:Self, rhs:Self) -> Bool {
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
    
    static public func == (lhs:Self, rhs:Self) -> Bool {
        return (lhs.yearElement == rhs.yearElement) && (lhs.monthElement == rhs.monthElement) && (lhs.hourElement == rhs.hourElement) && (lhs.dayElement == rhs.dayElement)
    }
}
