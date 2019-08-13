import Foundation

// This code was sourced from Paulo Tanaka, and modified by Tanner Silva in 2019 for compatibility with the swift package manager on Linux.
struct ANSIColorCode {
	static let black = [0, 9]
    static let red = [1, 9]
    static let green = [2, 9]
    static let yellow = [3, 9]
    static let blue = [4, 9]
    static let magenta = [5, 9]
    static let cyan = [6, 9]
    static let white = [7, 9]
}
struct ANSIModifiers {
    static var bold = [1, 22]
    static var blink = [5, 25]
    static var dim = [2, 22]
    static var italic = [2, 23]
    static var underline = [4, 24]
    static var inverse = [7, 27]
    static var hidden = [8, 28]
    static var strikethrough = [9, 29]
}

public extension String {
	public static func random(length:Int = 32) -> String {
		let base = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
		let baseLength = base.count
		var randomString = ""
		for _ in 0..<length {
			let randomIndex = Int.random(in:0..<baseLength)
			randomString.append(base[base.index(base.startIndex, offsetBy:randomIndex)])
		}
		return randomString
	}
	
	public func bashSafe() -> String {
		return self.replacingOccurrences(of:"'", with:"\"")
	}
}

public extension Date {
	public var isoString: String {
		return ISO8601DateFormatter().string(from:self)
	}
}

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

private func apply<T>(style: [T]) -> ((_:String) -> String) {
	return { str in return "\u{001B}[\(style[0])m\(str)\u{001B}[\(style[1])m" }
}

private func getColor(color: [Int], mod: Int) -> [Int] {
	let terminator = mod == 30 || mod == 90 ? 30 : 40
	return [ color[0] + mod, color[1] + terminator ]
}

public class Colors {
    static let normalText = 30
    static let bg = 40
    static let brightText = 90
    static let brightBg = 100

    // MARK: 8-bit color functions
    public static func getTextColorer(color: Int) -> ((_:String) -> String) {
        return apply(style:["38;5;\(color)", String(normalText + 9)])
    }

    public static func colorText(text: String, color: Int) -> String {
        return Colors.getTextColorer(color:color)(text)
    }

    public static func getBgColorer(color: Int) -> ((_:String) -> String) {
        return apply(style:["48;5;\(color)", String(bg + 9)])
    }

    public static func colorBg(text: String, color: Int) -> String {
        return Colors.getBgColorer(color:color)(text)
    }

    // MARK: Normal text colors
    public static var black = apply(style:getColor(color:ANSIColorCode.black, mod: normalText))
    public static var red = apply(style:getColor(color:ANSIColorCode.red, mod: normalText))
    public static var green = apply(style:getColor(color:ANSIColorCode.green, mod: normalText))
    public static var yellow = apply(style:getColor(color:ANSIColorCode.yellow, mod: normalText))
    public static var blue = apply(style:getColor(color:ANSIColorCode.blue, mod: normalText))
    public static var magenta = apply(style:getColor(color:ANSIColorCode.magenta, mod: normalText))
    public static var cyan = apply(style:getColor(color:ANSIColorCode.cyan, mod: normalText))
    public static var white = apply(style:getColor(color:ANSIColorCode.white, mod: normalText))

    // MARK: Bright text colors
    public static var Black = apply(style:getColor(color:ANSIColorCode.black, mod: brightText))
    public static var Red = apply(style:getColor(color:ANSIColorCode.red, mod: brightText))
    public static var Green = apply(style:getColor(color:ANSIColorCode.green, mod: brightText))
    public static var Yellow = apply(style:getColor(color:ANSIColorCode.yellow, mod: brightText))
    public static var Blue = apply(style:getColor(color:ANSIColorCode.blue, mod: brightText))
    public static var Magenta = apply(style:getColor(color:ANSIColorCode.magenta, mod: brightText))
    public static var Cyan = apply(style:getColor(color:ANSIColorCode.cyan, mod: brightText))
    public static var White = apply(style:getColor(color:ANSIColorCode.white, mod: brightText))

    // MARK: Normal background colors
    public static var bgBlack = apply(style:getColor(color:ANSIColorCode.black, mod: bg))
    public static var bgRed = apply(style:getColor(color:ANSIColorCode.red, mod: bg))
    public static var bgGreen = apply(style:getColor(color:ANSIColorCode.green, mod: bg))
    public static var bgYellow = apply(style:getColor(color:ANSIColorCode.yellow, mod: bg))
    public static var bgBlue = apply(style:getColor(color:ANSIColorCode.blue, mod: bg))
    public static var bgMagenta = apply(style:getColor(color:ANSIColorCode.magenta, mod: bg))
    public static var bgCyan = apply(style:getColor(color:ANSIColorCode.cyan, mod: bg))
    public static var bgWhite = apply(style:getColor(color:ANSIColorCode.white, mod: bg))

    // MARK: Bright background colors
    public static var BgBlack = apply(style:getColor(color:ANSIColorCode.black, mod: brightBg))
    public static var BgRed = apply(style:getColor(color:ANSIColorCode.red, mod: brightBg))
    public static var BgGreen = apply(style:getColor(color:ANSIColorCode.green, mod: brightBg))
    public static var BgYellow = apply(style:getColor(color:ANSIColorCode.yellow, mod: brightBg))
    public static var BgBlue = apply(style:getColor(color:ANSIColorCode.blue, mod: brightBg))
    public static var BgMagenta = apply(style:getColor(color:ANSIColorCode.magenta, mod: brightBg))
    public static var BgCyan = apply(style:getColor(color:ANSIColorCode.cyan, mod: brightBg))
    public static var BgWhite = apply(style:getColor(color:ANSIColorCode.white, mod: brightBg))

    // MARK: Text modifiers
    public static var bold = apply(style:ANSIModifiers.bold)
    public static var blink = apply(style:ANSIModifiers.blink)
    public static var dim = apply(style:ANSIModifiers.dim)
    public static var italic = apply(style:ANSIModifiers.italic)
    public static var underline = apply(style:ANSIModifiers.underline)
    public static var inverse = apply(style:ANSIModifiers.inverse)
    public static var hidden = apply(style:ANSIModifiers.hidden)
    public static var strikethrough = apply(style:ANSIModifiers.strikethrough)
}
