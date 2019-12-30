import Foundation
import SwiftShell
import Shout

public enum ShellAuthentication {
	case password(String)
	case privateKey(URL)
}


public struct Host {
	public var local:Shell {
		get {
			return Local(context:CustomContext(main))
		}
	}
	
	public var current:Shell {
		get {
			return Local(context:main)
		}
	}
}