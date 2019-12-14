import Foundation

fileprivate struct Segment {
	enum IPV6SegmentError:Error {
		case invalidLength
	}
	
	var integerRepresentation:Int64
	var fullString:String
	
	init<T>(_ input:T) throws where T:Collection, T.Element == Character {
		guard input.count <= 4 else {
			throw IPV6SegmentError.invalidLength
		}
		
		integerRepresentation = 0
		fullString = ""
	}
}


private struct AddressV6:Comparable {
	enum InitError:Error {
		case invalidAddressString
	}
	
	var segments:[Segment]

	init(_ addressString:String) throws {
		guard addressString.count <= 39 else {
			throw InitError.invalidAddressString
		}
		
		segments = [Segment]()
		
		var curSegmentString = ""
		var lastItterationWasColon = false
		for (_, curChar) in addressString.enumerated() {
			switch curChar {
				case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F", "a", "b", "c", "d", "e", "f":
					curSegmentString.append(curChar)
					if (lastItterationWasColon == false) {
						lastItterationWasColon = true
					}
				case ":":
					if (lastItterationWasColon == false) {
						let newSegment = try Segment(curSegmentString)
						segments.append(newSegment)
						curSegmentString = ""
						lastItterationWasColon = true
					} else {
						
					}
				default:
					throw InitError.invalidAddressString
			}
		}
	}
	
	public static func == (lhs:AddressV6, rhs:AddressV6) -> Bool {
		return true
	}
	
	public static func > (lhs:AddressV6, rhs:AddressV6) -> Bool {
		return true
	}
	
	public static func < (lhs:AddressV6, rhs:AddressV6) -> Bool {
		return true
	}
}

//public struct AddressV4:Comparable {
//	enum InitError:Error {
//		case invalidAddressString
//	}
//	
//	public let partOne:UInt8
//	public let partTwo:UInt8
//	public let partThree:UInt8
//	public let partFour:UInt8
//	public init(_ addressString:String) throws {
//		let components = addressString.split(separator:".")
//		guard components.count == 4 else {
//			print("\(addressString) is not a valid IPv4 address")
//			throw InitError.invalidAddressString
//		}
//		
//		guard let p1 = UInt8(components[0]) else {
//			print("\(components[0]) cannot be initialized as an 8 bit integer")
//			throw InitError.invalidAddressString
//		}
//		
//		guard let p2 = UInt8(components[1]) else {
//			print("\(components[1]) cannot be initialized as an 8 bit integer")
//			throw InitError.invalidAddressString
//		}
//		
//		guard let p3 = UInt8(components[2]) else {
//			print("\(components[1]) cannot be initialized as an 8 bit integer")
//			throw InitError.invalidAddressString
//		}
//
//		guard let p4 = UInt8(components[3]) else {
//			print("\(components[1]) cannot be initialized as an 8 bit integer")
//			throw InitError.invalidAddressString
//		}
//		
//		partOne = p1
//		partTwo = p2
//		partThree = p3
//		partFour = p4
//	}
//	
//	public func addressInteger() -> UInt32 {
//		var addressBuffer:UInt32 = UInt32(partOne)
//		addressBuffer = (addressBuffer << 8) | UInt32(partTwo)
//		addressBuffer = (addressBuffer << 8) | UInt32(partThree)
//		addressBuffer = (addressBuffer << 8) | UInt32(partFour)
//		return addressBuffer
//	}
//	
//	public func isWithin(cdir:CDIRV4) -> Bool {
//		if ((cdir.bytes & cdir.subnetMask) == (self.addressInteger() & cdir.subnetMask)) { 
//			return true
//		} else {
//			return false
//		}
//	}
//	
//	public func asString() -> String {
//		let newString = String(partOne) + "." + String(partTwo) + "." + String(partThree) + "." + String(partFour)
//		return newString
//	}
//	
//	public static func < (lhs:AddressV4, rhs:AddressV4) -> Bool {
//		if (lhs.partOne < rhs.partOne) {
//			return true
//		} else if (lhs.partOne > rhs.partTwo) {
//			return false
//		}
//		
//		if (lhs.partTwo < rhs.partTwo) {
//			return true
//		} else if (lhs.partTwo > rhs.partTwo) {
//			return false
//		}
//		
//		if (lhs.partThree < rhs.partThree) {
//			return true
//		} else if (lhs.partTwo > rhs.partTwo) {
//			return false
//		}
//		
//		if (lhs.partFour < rhs.partFour) {
//			return true
//		} else {
//			return false
//		}
//	}
//	
//	public static func <= (lhs:AddressV4, rhs:AddressV4) -> Bool {
//		if (lhs.partOne <= rhs.partOne) {
//			return true
//		} else if (lhs.partOne > rhs.partTwo) {
//			return false
//		}
//		
//		if (lhs.partTwo <= rhs.partTwo) {
//			return true
//		} else if (lhs.partTwo > rhs.partTwo) {
//			return false
//		}
//		
//		if (lhs.partThree <= rhs.partThree) {
//			return true
//		} else if (lhs.partTwo > rhs.partTwo) {
//			return false
//		}
//		
//		if (lhs.partFour <= rhs.partFour) {
//			return true
//		} else {
//			return false
//		}
//	}
//	
//	public static func >= (lhs:AddressV4, rhs:AddressV4) -> Bool {
//		if (lhs.partOne >= rhs.partOne) {
//			return true
//		} else if (lhs.partOne < rhs.partTwo) {
//			return false
//		}
//		
//		if (lhs.partTwo >= rhs.partTwo) {
//			return true
//		} else if (lhs.partTwo < rhs.partTwo) {
//			return false
//		}
//		
//		if (lhs.partThree >= rhs.partThree) {
//			return true
//		} else if (lhs.partTwo < rhs.partTwo) {
//			return false
//		}
//		
//		if (lhs.partFour >= rhs.partFour) {
//			return true
//		} else {
//			return false
//		}
//	}
//	
//	public static func > (lhs:AddressV4, rhs:AddressV4) -> Bool {
//		if (lhs.partOne > rhs.partOne) {
//			return true
//		} else if (lhs.partOne < rhs.partTwo) {
//			return false
//		}
//		
//		if (lhs.partTwo > rhs.partTwo) {
//			return true
//		} else if (lhs.partTwo < rhs.partTwo) {
//			return false
//		}
//		
//		if (lhs.partThree > rhs.partThree) {
//			return true
//		} else if (lhs.partTwo < rhs.partTwo) {
//			return false
//		}
//		
//		if (lhs.partFour > rhs.partFour) {
//			return true
//		} else {
//			return false
//		}
//	}
//	
//	public static func == (lhs:AddressV4, rhs:AddressV4) -> Bool {
//		return (lhs.partOne == rhs.partOne) && (lhs.partTwo == rhs.partTwo) && (lhs.partThree == rhs.partThree) && (lhs.partFour == rhs.partFour)
//	}
//}
