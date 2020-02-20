import Foundation
enum ProcessError:Error {
    case processStillRunning
}
fileprivate func bashEscape(string:String) -> String {
	return "'" + string.replacingOccurrences(of:"'", with:"\'") + "'"
}

public class LoggedProcess<C>:InteractiveProcess<C> where C:Command {
    public let processQueue = DispatchQueue(label:"com.tannersilva.ttoolkit.loggged-process", attributes: [.concurrent])
    
    public var stdoutData = Data()
    public var stderrData = Data()
    
    public init(_ command:C, workingDirectory:URL) throws {
        try super.init(command:command, workingDirectory: workingDirectory)
        launchStdErrLoop()
        launchStdOutLoop()
    }
    
    public func exportResult() throws -> CommandResult {
        guard state == .exited else {
            throw ProcessError.processStillRunning
        }
        control.wait()
        let returnCommand = CommandResult(exitCode: Int(proc.terminationStatus), stdout: stdoutData.lineSlice(removeBOM: false).compactMap { String(data:$0, encoding:.utf8) }, stderr: stderrData.lineSlice(removeBOM: false).compactMap({ String(data:$0, encoding:.utf8) }))
        control.signal()
        return returnCommand
    }
    
    internal func launchStdOutLoop() {
        runGroup.enter()
        processQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            self.suspendGroup.wait()
            while self.state != .exited {
                let newLines:Data = self.readStdOut()
                if newLines.count > 0 {
                    self.control.wait()
                    self.stdoutData.append(newLines)
                    self.control.signal()
                }
                self.suspendGroup.wait()
            }
            self.runGroup.leave()
        }
    }
    internal func launchStdErrLoop() {
        runGroup.enter()
        processQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            
            self.suspendGroup.wait()
            while self.state != .exited {
                let newLines:Data = self.readStdErr()
                if newLines.count > 0 {
                    self.control.wait()
                    self.stderrData.append(contentsOf:newLines)
                    self.control.signal()
                }
                self.suspendGroup.wait()
            }
            self.runGroup.leave()
        }
    }
}

public class InteractiveProcess<C> where C:Command {
	public enum State:UInt8 {
		case running = 0
		case suspended = 1
		case exited = 2
	}
    
    public typealias CommandType = C
    public var command:CommandType
    
	public var env:[String:String]
	public var stdin:FileHandle
	public var stdout:FileHandle
	public var stderr:FileHandle
	public var workingDirectory:URL
	internal var proc = Process()
	private var stderrGuard = StringStreamGuard()
    private var stdoutGuard = StringStreamGuard()
	public var state:State = .running
	internal let control = DispatchSemaphore(value:1)
	
    public var suspendGroup = DispatchGroup()
    public var runGroup = DispatchGroup() //remains entered until the process finishes executing. Suspending does not cause this group to leave

    public init(command:C, workingDirectory:URL) throws {
		env = ProcessInfo.processInfo.environment
		let inPipe = Pipe()
		let outPipe = Pipe()
		let errPipe = Pipe()
		stdin = inPipe.fileHandleForWriting
		stdout = outPipe.fileHandleForReading
		stderr = errPipe.fileHandleForReading
        self.workingDirectory = workingDirectory
        self.command = command
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
                suspendGroup.enter()
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
                suspendGroup.leave()
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

    //MARK: Reading Output Streams As Lines
    public func readStdErr() -> [String] {
        var lineToReturn:[String]? = nil
        while lineToReturn == nil && proc.isRunning == true && state == .running {
            suspendGroup.wait()
            let bytes = stderr.readData(ofLength: 512)
            if bytes.count > 0 {
                _ = stderrGuard.processData(bytes)
                lineToReturn = stderrGuard.flushLines()
            }
        }
        return lineToReturn ?? [String]()
    }
    public func readStdOut() -> [String] {
        var lineToReturn:[String]? = nil
        while lineToReturn == nil && proc.isRunning == true && state == .running {
            suspendGroup.wait()
            let bytes = stdout.readData(ofLength: 512)
            if bytes.count > 0 {
                _ = stdoutGuard.processData(bytes)
                lineToReturn = stdoutGuard.flushLines()
            }
        }
        return lineToReturn ?? [String]()
    }

    
    //MARK: Reading Output Streams as Data
    public func readStdOut(length:Int = 512) -> Data {
        var dataToReturn:Data? = nil
        while dataToReturn == nil && proc.isRunning == true && state == .running {
            suspendGroup.wait()
            let bytes = stdout.readData(ofLength: length)
            if bytes.count > 0 {
                dataToReturn = bytes
            }
        }
        return dataToReturn ?? Data()
    }
    
    public func readStdErr(length:Int = 512) -> Data {
        var dataToReturn:Data? = nil
        while dataToReturn == nil && proc.isRunning == true && state == .running {
            suspendGroup.wait()
            let bytes = stderr.readData(ofLength: length)
            if bytes.count > 0 {
                dataToReturn = bytes
            }
        }
        return dataToReturn ?? Data()
    }
}
