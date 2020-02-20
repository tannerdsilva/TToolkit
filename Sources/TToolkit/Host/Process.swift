import Foundation

fileprivate func bashEscape(string:String) -> String {
	return "'" + string.replacingOccurrences(of:"'", with:"\'") + "'"
}

public class InteractiveProcess {
	enum State:UInt8 {
		case running
		case suspended
		case exited
	}
	
	public var env:[String:String]
	public var stdin:FileHandle
	public var stdout:FileHandle
	public var stderr:FileHandle
	public var workingDirectory:URL
	public var proc = Process()
	public var streamGuard = StringStreamGuard()
	public var state:State = .running
	private let control = DispatchSemaphore(value:1)
	public var runGroup = DispatchGroup() //remains entered until the process finishes executing. Suspending does not cause this group to leave

	public init<C>(command:C, workingDirectory:URL? = nil, _ onComplete:@escaping(CommandResult) -> Void) throws where C:Command {
		env = ProcessInfo.processInfo.environment
		let inPipe = Pipe()
		let outPipe = Pipe()
		let errPipe = Pipe()
		stdin = inPipe.fileHandleForWriting
		stdout = outPipe.fileHandleForReading
		stderr = errPipe.fileHandleForReading
		if let hasWorkingDirectory = workingDirectory {
			self.workingDirectory = hasWorkingDirectory
		} else {
			self.workingDirectory = FileManager.default.homeDirectoryForCurrentUser
		}
		
		proc.arguments = command.arguments
		proc.executableURL = command.executable
		proc.currentDirectoryURL = workingDirectory
		proc.standardInput = inPipe
		proc.standardOutput = outPipe
		proc.standardError = errPipe
		
		proc.terminationHandler = { [weak self] someItem in
			guard let self = self else {
				return
			}
			self.control.wait()
			self.state = .exited
			self.runGroup.leave()
			self.control.signal()
		}
		
		runGroup.enter()
		do {
			try proc.run()
		} catch let error {
			runGroup.leave()
			throw error
		}
	}
	
	public func suspend() -> Bool? {
		control.wait()
		if state == .running {
			if proc.suspend() == true {
				state = .suspended
				control.signal()
				return true
			} else { 
				state = .running
				control.signal()
				return false
			}
		} else {
			control.signal()
			return nil
		}
	}
	
	public func resume() -> Bool? {
		control.wait()
		if state == .suspended {
			if proc.resume() == true {
				state = .running
				control.signal()
				return true
			} else {
				state = .suspended
				control.signal()
				return false
			}
		} else {
			control.signal()
			return nil
		}
	}
		
	public func readLine() -> [String]? {
		var lineToReturn:[String]? = nil
		while lineToReturn == nil && proc.isRunning == true && state == .running {
			let bytes = stdout.readData(ofLength:256)
			if bytes.count > 0 {
				streamGuard.processData(bytes)
				lineToReturn = streamGuard.flushLines()
			}
		}
		return lineToReturn
	}
}