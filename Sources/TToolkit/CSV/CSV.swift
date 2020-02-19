import Foundation

fileprivate func csvBreakdown(line:String) -> [String] {
    var isTerminated = true
    var isQuoted = false
    var possibleQuoteEscape = false
    var buffer = ""
    var elements = [String]()
    var visibleBegan = false
    
    func terminate() {
        elements.append(buffer)
        possibleQuoteEscape = false
        isQuoted = false
        isTerminated = true
        buffer = ""
    }
    
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

public func readCSV(_ inputFile:URL) throws -> [[String:String]] {
    enum CSVReadingError: Error {
        case unableToConvertToString
        case noHeaderFound
        case inconsistentData
        case headerLineSkipped
    }
    let inputFileData = try Data(contentsOf:inputFile)
    //trim any invisible characters off the top
     
    guard let inputFileString = String(data:inputFileData, encoding:.utf8) else {
        throw CSVReadingError.unableToConvertToString
    }
    let inputLinesData = inputFileData.lineParse() ?? [Data]()
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

extension String {
    fileprivate func csvEncodedString() -> String {
        return "\"" + self.replacingOccurrences(of:"\"", with:"\"\"") + "\""
    }
}

extension Collection where Element: CSVEncodable {
    public func toCSV() throws -> Data {
        //enumerate over self to collect all of the keys for every child
        var buildAllColumns = Set<String>()
        for (_, row) in self.enumerated() {
            buildAllColumns = buildAllColumns.union(row.csvColumns)
        }
        
        //build the heading row
        let allColumns = buildAllColumns.sorted(by:{ $0 > $1 })
        
        let headerString = allColumns.map({ $0.csvEncodedString() }).joined(separator: ",") + "\n"
        let headerData = try headerString.safeData(using:.utf8)
        
        var dataLines = headerData
        self.explode(lanes:2, using:{ n, curRow in
            var thisLine = Array<String>(repeating:"", count:allColumns.count)
            for(_, kv) in allColumns.enumerated() {
                if let hasIndex = allColumns.firstIndex(of:kv), let hasValue = curRow.csvValue(columnName:kv) {
                    thisLine[hasIndex] = hasValue.csvEncodedString()
                }
            }
            let lineString = thisLine.joined(separator:",") + "\n"
            let didConvertToData = try lineString.safeData(using:.utf8)
            return didConvertToData
        }, merge: { n, curItem in
            dataLines.append(curItem)
        })
        return dataLines
    }
    
    public func writeCSV(to fileDestination:URL) throws {
    	let csvData = try self.toCSV()
    	try csvData.write(to:fileDestination)
    }
}
