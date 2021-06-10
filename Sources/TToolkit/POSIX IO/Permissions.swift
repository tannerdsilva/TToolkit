import Foundation
import Glibc

public struct PosixPermissions:OptionSet {
	public let rawValue:mode_t
	
	public init(rawValue:mode_t) {
		self.rawValue = rawValue
	}
	
	//user options
	public static let userAll = PosixPermissions(rawValue:S_IRWXU)
	
	public static let userRead = PosixPermissions(rawValue:S_IRUSR)
	public static let userWrite = PosixPermissions(rawValue:S_IWUSR)
	public static let userExecute = PosixPermissions(rawValue:S_IXUSR)
	
	//group options
	public static let groupAll = PosixPermissions(rawValue:S_IRWXG)
	
	public static let groupRead = PosixPermissions(rawValue:S_IRGRP)
	public static let groupWrite = PosixPermissions(rawValue:S_IWGRP)
	public static let groupExecute = PosixPermissions(rawValue:S_IXGRP)
	
	//world options
	public static let otherAll = PosixPermissions(rawValue:S_IRWXO)
	
	public static let otherRead = PosixPermissions(rawValue:S_IROTH)
	public static let otherWrite = PosixPermissions(rawValue:S_IWOTH)
	public static let otherExecute = PosixPermissions(rawValue:S_IXOTH)
	
	#if os(Linux)
	//linux specific bits
	public static let setUID = PosixPermissions(rawValue:S_ISUID)
	public static let setGID = PosixPermissions(rawValue:S_ISGID)
	public static let sticky = PosixPermissions(rawValue:S_ISVTX)
	#endif
}