import Foundation
import Glibc

public struct POSIXPermissions:OptionSet {
	public let rawValue:mode_t
	
	public init(rawValue:mode_t) {
		self.rawValue = rawValue
	}
	
	//user options
	public static let userAll = POSIXPermissions(rawValue:S_IRWXU)
	
	public static let userRead = POSIXPermissions(rawValue:S_IRUSR)
	public static let userWrite = POSIXPermissions(rawValue:S_IWUSR)
	public static let userExecute = POSIXPermissions(rawValue:S_IXUSR)
	
	//group options
	public static let groupAll = POSIXPermissions(rawValue:S_IRWXG)
	
	public static let groupRead = POSIXPermissions(rawValue:S_IRGRP)
	public static let groupWrite = POSIXPermissions(rawValue:S_IWGRP)
	public static let groupExecute = POSIXPermissions(rawValue:S_IXGRP)
	
	//world options
	public static let otherAll = POSIXPermissions(rawValue:S_IRWXO)
	
	public static let otherRead = POSIXPermissions(rawValue:S_IROTH)
	public static let otherWrite = POSIXPermissions(rawValue:S_IWOTH)
	public static let otherExecute = POSIXPermissions(rawValue:S_IXOTH)
	
	#if os(Linux)
	//linux specific bits
	public static let setUID = POSIXPermissions(rawValue:S_ISUID)
	public static let setGID = POSIXPermissions(rawValue:S_ISGID)
	public static let sticky = POSIXPermissions(rawValue:S_ISVTX)
	#endif
}