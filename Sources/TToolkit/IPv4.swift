import Foundation

public struct CDIRV4 {
	public let address:AddressV4
	public let subnetNumber:UInt8
	
	public let bytes:UInt32
	public let subnetMask:UInt32
	
	public init(_ cdirString:String) throws {
		enum ParseError:Error {
			case invalidFormat
		}
		let splitSubnet = cdirString.split(separator:"/", omittingEmptySubsequences:true).map { String($0) }
		guard splitSubnet.count == 2 else {
			print("Unexpected input \(cdirString) for CDIRV4 initializer")
			throw ParseError.invalidFormat
		}
		
		guard let subnet = UInt8(splitSubnet[1]) else {
			print("Unexpected input \(cdirString) for CDIRV4 initializer. Subnet cannot be converted into Int8 value")
			throw ParseError.invalidFormat
		}
		guard subnet <= 32 else {
			throw ParseError.invalidFormat
		}
		subnetNumber = subnet
		
		address = try AddressV4(splitSubnet[0])
		bytes = address.addressInteger()
		
		subnetMask = (UInt32.max << (32 - subnet))
	}
	
	public func asString() -> String {
		return address.asString() + "/" + String(subnetNumber)
	}
}

public struct AddressV4:Comparable {
	enum InitError:Error {
		case invalidAddressString
	}
	
	public let partOne:UInt8
	public let partTwo:UInt8
	public let partThree:UInt8
	public let partFour:UInt8
	public init(_ addressString:String) throws {
		let components = addressString.split(separator:".")
		guard components.count == 4 else {
			print("\(addressString) is not a valid IPv4 address")
			throw InitError.invalidAddressString
		}
		
		guard let p1 = UInt8(components[0]) else {
			print("\(components[0]) cannot be initialized as an 8 bit integer")
			throw InitError.invalidAddressString
		}
		
		guard let p2 = UInt8(components[1]) else {
			print("\(components[1]) cannot be initialized as an 8 bit integer")
			throw InitError.invalidAddressString
		}
		
		guard let p3 = UInt8(components[2]) else {
			print("\(components[1]) cannot be initialized as an 8 bit integer")
			throw InitError.invalidAddressString
		}

		guard let p4 = UInt8(components[3]) else {
			print("\(components[1]) cannot be initialized as an 8 bit integer")
			throw InitError.invalidAddressString
		}
		
		partOne = p1
		partTwo = p2
		partThree = p3
		partFour = p4
	}
	
	public func addressInteger() -> UInt32 {
		var addressBuffer:UInt32 = UInt32(partOne)
		addressBuffer = (addressBuffer << 8) | UInt32(partTwo)
		addressBuffer = (addressBuffer << 8) | UInt32(partThree)
		addressBuffer = (addressBuffer << 8) | UInt32(partFour)
		return addressBuffer
	}
	
	public func isWithin(cdir:CDIRV4) -> Bool {
		if ((cdir.bytes & cdir.subnetMask) == (self.addressInteger() & cdir.subnetMask)) { 
			return true
		} else {
			return false
		}
	}
	
	public func asString() -> String {
		let newString = String(partOne) + "." + String(partTwo) + "." + String(partThree) + "." + String(partFour)
		return newString
	}
	
	public static func < (lhs:AddressV4, rhs:AddressV4) -> Bool {
		if (lhs.partOne < rhs.partOne) {
			return true
		} else if (lhs.partOne > rhs.partTwo) {
			return false
		}
		
		if (lhs.partTwo < rhs.partTwo) {
			return true
		} else if (lhs.partTwo > rhs.partTwo) {
			return false
		}
		
		if (lhs.partThree < rhs.partThree) {
			return true
		} else if (lhs.partTwo > rhs.partTwo) {
			return false
		}
		
		if (lhs.partFour < rhs.partFour) {
			return true
		} else {
			return false
		}
	}
	
	public static func <= (lhs:AddressV4, rhs:AddressV4) -> Bool {
		if (lhs.partOne <= rhs.partOne) {
			return true
		} else if (lhs.partOne > rhs.partTwo) {
			return false
		}
		
		if (lhs.partTwo <= rhs.partTwo) {
			return true
		} else if (lhs.partTwo > rhs.partTwo) {
			return false
		}
		
		if (lhs.partThree <= rhs.partThree) {
			return true
		} else if (lhs.partTwo > rhs.partTwo) {
			return false
		}
		
		if (lhs.partFour <= rhs.partFour) {
			return true
		} else {
			return false
		}
	}
	
	public static func >= (lhs:AddressV4, rhs:AddressV4) -> Bool {
		if (lhs.partOne >= rhs.partOne) {
			return true
		} else if (lhs.partOne < rhs.partTwo) {
			return false
		}
		
		if (lhs.partTwo >= rhs.partTwo) {
			return true
		} else if (lhs.partTwo < rhs.partTwo) {
			return false
		}
		
		if (lhs.partThree >= rhs.partThree) {
			return true
		} else if (lhs.partTwo < rhs.partTwo) {
			return false
		}
		
		if (lhs.partFour >= rhs.partFour) {
			return true
		} else {
			return false
		}
	}
	
	public static func > (lhs:AddressV4, rhs:AddressV4) -> Bool {
		if (lhs.partOne > rhs.partOne) {
			return true
		} else if (lhs.partOne < rhs.partTwo) {
			return false
		}
		
		if (lhs.partTwo > rhs.partTwo) {
			return true
		} else if (lhs.partTwo < rhs.partTwo) {
			return false
		}
		
		if (lhs.partThree > rhs.partThree) {
			return true
		} else if (lhs.partTwo < rhs.partTwo) {
			return false
		}
		
		if (lhs.partFour > rhs.partFour) {
			return true
		} else {
			return false
		}
	}
	
	public static func == (lhs:AddressV4, rhs:AddressV4) -> Bool {
		return (lhs.partOne == rhs.partOne) && (lhs.partTwo == rhs.partTwo) && (lhs.partThree == rhs.partThree) && (lhs.partFour == rhs.partFour)
	}
}
