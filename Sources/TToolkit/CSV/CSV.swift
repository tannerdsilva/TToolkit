import Foundation

//when a CSV file is broken into lines, the lines are converted into strings and passed into this function.
//this function is responsible for parsing the relevant quotes and escape sequences, and returning the result as an array of strings
fileprivate func csvBreakdown(line:String) -> [String] {
    var isTerminated = true	//as `line` is parsed, 
    var isQuoted = false
    var possibleQuoteEscape = false
    var buffer = ""
    var elements = [String]()
    
    //terminate a column
    func terminate() {
        elements.append(buffer)
        possibleQuoteEscape = false
        isQuoted = false
        isTerminated = true
        buffer = ""
    }
    
    //itterate through the string. the result can be produced by watching for only a few key characters.
    for (_, curChar) in line.enumerated() {
    	if (isTerminated == false) {
			switch curChar {
			case "\"":
				if (possibleQuoteEscape == true) {
					buffer.append("\"")
					possibleQuoteEscape = false
				} else {
					possibleQuoteEscape = true
				}
			case ",":
				if (isQuoted == true && possibleQuoteEscape == false) {
					buffer.append(",")
				} else {
					if (possibleQuoteEscape == true) {
						possibleQuoteEscape = false
					}
					terminate()
				}
			default:
				if (possibleQuoteEscape == true) {
					possibleQuoteEscape = false
				}
				buffer.append(curChar)
			}
		} else {
			isTerminated = false
			//determine if this string is quoted
			switch curChar {
			case "\"":
				isQuoted = true
			case ",":
				terminate()
			default:
				buffer.append(curChar)
				isQuoted = false
			}
		}
    }
    terminate()
    return elements
}

public protocol CSVEncodable {
    var csvColumns:Set<String> { get }
    func csvValue(columnName:String) -> String?
}

public protocol CSVDecodable {
    init(_ csvData:[[String:String]])
}

extension CSVEncodable {
    public func csvDictionary() -> [String:String] {
        var dictionaryToBuild = [String:String]()
        for (_, someColumn) in self.csvColumns.enumerated() {
            dictionaryToBuild[someColumn] = self.csvValue(columnName: someColumn)
        }
        return dictionaryToBuild
    }
}

extension Dictionary:CSVEncodable where Key == String, Value == String {
    public var csvColumns:Set<String> {
        get {
            return Set<String>(keys)
        }
    }
    
    public func csvValue(columnName:String) -> String? {
        return self[columnName]
    }
}
enum CSVReadingError: Error {
	case unableToConvertToString
	case noHeaderFound
	case inconsistentData
	case headerLineSkipped
}


extension Data {
	public func parseCSV() throws -> [[String:String]] {
	    enum CSVReadingError: Error {
			case unableToConvertToString
			case noHeaderFound
			case inconsistentData
			case headerLineSkipped
		}

		let inputLinesData = self.lineParse() ?? [Data]()
		let inputFileLines = inputLinesData.compactMap { String(data:$0, encoding:.utf8) }

		guard inputFileLines.count > 0 else {
			throw CSVReadingError.noHeaderFound
		}

		let csvHeader = csvBreakdown(line:inputFileLines[0])
		var parsedLines = [[String:String]]()
		for (n, curLine) in inputFileLines.enumerated() {
			if n != 0 {
				let parsedLine = csvBreakdown(line:curLine).map({ String($0) })
				var thisLine = [String:String]()
				for (nn, lineItem) in parsedLine.enumerated() {
					if (nn < csvHeader.count) {
						thisLine[csvHeader[nn]] = lineItem
					}
				}
				parsedLines.append(thisLine)
			}
		}
		return parsedLines
	}
	
	public func explodeCSV() throws -> [[String:String]] {
		var inputLinesData = self.lineParse() ?? [Data]()
		guard inputLinesData.count > 0 else {
			return [[String:String]]()
		}
		guard let firstLineString = String(data:inputLinesData.remove(at:0), encoding:.utf8) else {
			throw CSVReadingError.noHeaderFound
		}
		let headerLine = csvBreakdown(line:firstLineString)
		let returnLines:[[String:String]] = inputLinesData.explode(using: { (_, curItem) -> [String:String]? in
			let itemString = String(data:curItem, encoding:.utf8)
			if (itemString != nil) {
				let parsedLine = csvBreakdown(line:itemString!)
				var thisLine = [String:String]()
				for (n, curParsedItem) in parsedLine.enumerated() {
					if (n < headerLine.count) {
						thisLine[headerLine[n]] = curParsedItem
					}
				}
				return thisLine
			} else {
				return nil
			}
		})
		return returnLines
		
	}
}

public func readCSV(_ inputFile:URL) throws -> [[String:String]] {
    return try Data(contentsOf:inputFile).parseCSV()
}

fileprivate let CarriageReturn:UnicodeScalar = "\r"
fileprivate let LineFeed:UnicodeScalar = "\n"
fileprivate let DoubleQuote:UnicodeScalar = "\""
fileprivate let Nul:UnicodeScalar = UnicodeScalar(0)
fileprivate let illecalCharacters = CharacterSet(charactersIn:"\(DoubleQuote),\(CarriageReturn)\(LineFeed)")

extension String {
    fileprivate func csvEncodedString() -> String {
        if self.rangeOfCharacter(from: illecalCharacters) != nil {
			// A double quote must be preceded by another double quote
			let value = self.replacingOccurrences(of: String(DoubleQuote), with: "\"\"")
			// Quote fields containing illegal characters
			return "\"\(value)\""
		}
		return self
    }
}

extension Collection where Element: CSVEncodable {
    //export a CSV with the option of some added computational *firepower*
    public func toCSV(explode:Bool = true) throws -> Data {
    	//enumerate over self to collect all of the keys for every child
        var buildAllColumns = Set<String>()
        for (_, row) in self.enumerated() {
            buildAllColumns = buildAllColumns.union(row.csvColumns)
        }
        
        //build the heading row
        let allColumns = buildAllColumns.sorted(by:{ $0 > $1 })
        
        let headerString = allColumns.map({ $0.trimmingCharacters(in:CharacterSet.whitespacesAndNewlines).csvEncodedString() }).joined(separator: ",") + "\n"
        
        var dataLines = headerString.data(using:.utf8)!
		self.explode(using:{ n, curRow in
			var thisLine = Array<String>(repeating:"", count:allColumns.count)
			for(_, kv) in allColumns.enumerated() {
				if let hasIndex = allColumns.firstIndex(of:kv), let hasValue = curRow.csvValue(columnName:kv) {
					thisLine[hasIndex] = hasValue.csvEncodedString()
				}
			}
			let lineString = thisLine.joined(separator:",") + "\n"
			let dataConvert = lineString.data(using:.utf8)!
			return dataConvert
		}, merge: { n, curItem in
			dataLines.append(curItem)
		})
        return dataLines
    }
    
    public func writeCSV(to fileDestination:URL) throws {
    	let csvData = try self.toCSV()
    	try csvData.write(to:fileDestination)
    }
    
    
    //append a set of lines to a csv file using a collection of CSVEncodable conformant elements
    public func appendCSV(to fileToAppend:URL) throws {
    	var parsedData = try readCSV(fileToAppend)
    	parsedData.append(contentsOf:self.compactMap({ $0.csvDictionary() }))
    	try parsedData.toCSV().write(to:fileToAppend)
    }
}
