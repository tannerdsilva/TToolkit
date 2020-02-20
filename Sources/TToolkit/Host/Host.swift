import Foundation
import Shout

public enum ShellAuthentication {
	case password(String)
	case privateKey(URL)
}