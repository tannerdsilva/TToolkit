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

public struct StringStreamGuard {
//takes a data stream and returns it as whole lines. protects objects downstream from encountering incomplete character sequences.
	private var inputBuffer = Data()
	private var inputString = String()
	
	public mutating func processData(_ newData:Data) -> Bool {
		let dataToMap = (inputBuffer.count > 0) ? (inputBuffer + newData) : newData
		if let utfTest = String(data:dataToMap, encoding:.utf8) {
			inputString += utfTest
			inputBuffer.removeAll(keepingCapacity:true)
			return utfTest.contains(where:{ $0.isNewline })
		} else {
			inputBuffer.append(newData)
			return false
		}
	}
	
	public mutating func flushLines() -> [String]? {
		let start = inputString.startIndex
		let end = inputString.endIndex
		if let lastTerm = inputString.lastIndex(where:{ (someChar:Character) in
			return someChar.isNewline 
		}) {
			let newlines = String(inputString[start..<lastTerm]).split { $0.isNewline }
			if (inputString.distance(from:lastTerm, to:end) > 0) {
				inputString = String(inputString[lastTerm..<end])
			} else {
				inputString.removeAll(keepingCapacity:true)
			}
			return newlines.map { String($0) }
		} else {
			return nil
		}
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
public func serializeJSON(object:Any, file:URL) throws {
	let jsonData = try JSONSerialization.data(withJSONObject:object)
	try jsonData.write(to:file)
}