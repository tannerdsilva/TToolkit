import Foundation

public enum ShellAuthentication {
	case password(String)
	case privateKey(URL)
}