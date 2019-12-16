import Foundation

public func dprint(_ input:String) {
	#if DEBUG
	print(input)
	#endif
}

public struct StringStopwatch {
	private var _startDate = Date()
	public init() {}
	public mutating func reset() {
		_startDate = Date()
	}
	public func click(_ decimals:UInt = 1) -> String {
		let elapsed = Date().timeIntervalSince(_startDate)
		let formatString = "%." + String(decimals) + "f"
		return String(format:formatString, elapsed)
	}
}

public func promptLoop(with promptingString:String, terminator:String) -> [String] {
	var promptString:String? = nil
	var arrayToReturn = [String]()
	repeat { 
		print(Colors.dim("Type '\(terminator)' to exit."))
		promptString = prompt(with:promptingString)
	} while promptString as? String != terminator
	return arrayToReturn
}

public func prompt(with promptingString:String) -> String {
	var inputVariable:String? = nil
	var i = 0
	repeat {
		if (i > 0) {
			print(Colors.Red("[ERROR]\tInvalid input. Please try again."))
		}
		
		print(Colors.Yellow(promptingString + ": "), terminator:"")
		
		i += 1
	} while ((inputVariable = readLine()) == nil || inputVariable == "")
	return inputVariable!
}

public func prompt(with promptingString:String, validChoices:[String], displayValidChoices:Bool = false) -> String {
	if (displayValidChoices == true) {
		for (_, curChoice) in validChoices.enumerated() {
			print(Colors.Magenta(" ->\t\(curChoice)"))
		}
	}

	var inputVariable:String? = nil
	var i = 0
	repeat {
		if (i > 0) {
			print(Colors.Red("[ERROR]\tInvalid input. Please try again."))
		}
		
		print(Colors.Yellow(promptingString + ": "), terminator:"")
		
		i += 1
	} while ((inputVariable = readLine()) == nil || inputVariable == "" || validChoices.contains(inputVariable!) == false)
	return inputVariable!
}


//MARK: JSON serialization
public enum JSONSerializationError:Error {
	case invalidObjectType
}
public func serializeJSON<T>(_:T.Type, file:URL) throws -> T {
	let fileData = try Data(contentsOf:file)
	guard let fileObject = try JSONSerialization.jsonObject(with:fileData) as? T else {
		throw JSONSerializationError.invalidObjectType
	}
	return fileObject
}

public func serializeJSON(object:Any, file:URL) throws {
	let jsonData = try JSONSerialization.data(withJSONObject:object)
	try jsonData.write(to:file)
}