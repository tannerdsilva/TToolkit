import Foundation
enum ProcessError:Error {
    case processStillRunning
}
fileprivate func bashEscape(string:String) -> String {
	return "'" + string.replacingOccurrences(of:"'", with:"\'") + "'"
}

public class LoggedProcess:InteractiveProcess {
    public var stdoutData = Data()
    public var stderrData = Data()
    
    public init<C>(_ command:C, workingDirectory:URL) throws where C:Command {
        try super.init(command:command, workingDirectory: workingDirectory, run:false)
        stdout.readabilityHandler = { [weak self] _ in
            guard let self = self else {
                return
            }
            self.processQueue.sync {
                let readData = self.stdout.availableData
                if readData.count > 0 {
                    self.stdoutData.append(readData)
                }
            }
        }
        
        stderr.readabilityHandler = { [weak self] _ in
            guard let self = self else {
                return
            }
            self.processQueue.sync {
                let readData = self.stderr.availableData
                if readData.count > 0 {
                    self.stderrData.append(readData)
                }
            }
        }
        
        try self.run()
    }
    
    public func exportResult() throws -> CommandResult {
        try processQueue.sync {
            guard state == .exited else {
                throw ProcessError.processStillRunning
            }
            return CommandResult(exitCode: Int(proc.terminationStatus), stdout: stdoutData.lineSlice(removeBOM: false), stderr: stderrData.lineSlice(removeBOM: false))
        }
    }
    
//    internal func launchStdOutLoop() {
//        let launchGroup = DispatchGroup()
//        launchGroup.enter()
//        runGroup.enter()
//        processQueue.async { [weak self] in
//            guard let self = self else {
//                return
//            }
//            launchGroup.leave()
//            var bytesCount:Int = 0
//            self.control.wait()
//            while self.state != .exited || bytesCount > 0 {
//                self.control.signal()
//                let readBytes:Data = self.stdout.availableData
//                bytesCount = readBytes.count
//                if bytesCount > 0 {
//                    self.runGroup.enter()
//                    self.processQueue.async { [weak self] in
//                        guard let self = self else {
//                            return
//                        }
//                        self.control.wait()
//                        self.stdoutData.append(contentsOf:readBytes)
//                        self.control.signal()
//                        self.runGroup.leave()
//                    }
//                }
//                self.control.wait()
//            }
//            self.control.signal()
//            self.runGroup.leave()
//        }
//    }
//    internal func launchStdErrLoop() {
//        runGroup.enter()
//        processQueue.async { [weak self] in
//            guard let self = self else {
//                return
//            }
//            var bytesCount:Int = 0
//            while self.state != .exited || bytesCount > 0 {
//                let newBytes:Data = self.stderr.availableData
//                bytesCount = newBytes.count
//                if bytesCount > 0 {
//                    self.processQueue.async { [weak self] in
//                        guard let self = self else {
//                            return
//                        }
//                        self.control.wait()
//                        self.stderrData.append(contentsOf:newBytes)
//                        self.control.signal()
//                    }
//                }
//            }
//            self.runGroup.leave()
//        }
//    }
}

public class InteractiveProcess {
    let processQueue = DispatchQueue(label:"com.tannersilva.ttoolkit.process-interactive")
    
	public enum State:UInt8 {
		case running = 0
		case suspended = 1
		case exited = 2
	}
    
	public var env:[String:String]
	public var stdin:FileHandle
	public var stdout:FileHandle
	public var stderr:FileHandle
	public var workingDirectory:URL
	internal var proc = Process()
	public var state:State = .running

    public init<C>(command:C, workingDirectory wd:URL, run:Bool) throws where C:Command {
        env = command.environment
		let inPipe = Pipe()
		let outPipe = Pipe()
		let errPipe = Pipe()
		stdin = inPipe.fileHandleForWriting
		stdout = outPipe.fileHandleForReading
		stderr = errPipe.fileHandleForReading
        workingDirectory = wd
		proc.arguments = command.arguments
		proc.executableURL = command.executable
		proc.currentDirectoryURL = wd
		proc.standardInput = inPipe
		proc.standardOutput = outPipe
		proc.standardError = errPipe
		proc.terminationHandler = { [weak self] someItem in
			guard let self = self else {
				return
			}
            self.processQueue.sync {
                self.state = .exited
            }
		}
        if run {
            try self.run()
        }
    }
    
    public func run() throws {
        try processQueue.sync {
            do {
                try proc.run()
            } catch let error {
                throw error
            }

        }
    }
	
	public func suspend() -> Bool? {
        processQueue.sync {
            if state == .running {
                if proc.suspend() == true {
                    state = .suspended
                    return true
                } else {
                    state = .running
                    return false
                }
            } else {
                return nil
            }
        }
    }
	
	public func resume() -> Bool? {
        processQueue.sync {
            if state == .suspended {
                if proc.resume() == true {
                    state = .running
                    return true
                } else {
                    state = .suspended
                    return false
                }
            } else {
                return nil
            }
        }
	}

    //MARK: Reading Output Streams As Lines
//    public func readStdErr() -> [String] {
//        var lineToReturn:[String]? = nil
//        while lineToReturn == nil && proc.isRunning == true && state == .running {
//            let bytes = stderr.availableData
//            if bytes.count > 0 {
//                _ = stderrGuard.processData(bytes)
//                lineToReturn = stderrGuard.flushLines()
//            }
//            suspendGroup.wait()
//        }
//        return lineToReturn ?? [String]()
//    }
//    public func readStdOut() -> [String] {
//        var lineToReturn:[String]? = nil
//        while lineToReturn == nil && proc.isRunning == true && state == .running {
//            let bytes = stdout.availableData
//            if bytes.count > 0 {
//                _ = stdoutGuard.processData(bytes)
//                lineToReturn = stdoutGuard.flushLines()
//            }
//            suspendGroup.wait()
//        }
//        return lineToReturn ?? [String]()
//    }
//
//
//    //MARK: Reading Output Streams as Data
//    public func readStdOut() -> Data {
//        var dataToReturn:Data? = nil
//        while dataToReturn == nil && proc.isRunning == true && state == .running {
//            let bytes = stdout.availableData
//            if bytes.count > 0 {
//                dataToReturn = bytes
//            }
//            suspendGroup.wait()
//        }
//        return dataToReturn ?? Data()
//    }
//
//    public func readStdErr() -> Data {
//        var dataToReturn:Data? = nil
//        while dataToReturn == nil && proc.isRunning == true && state == .running {
//            let bytes = stderr.availableData
//            if bytes.count > 0 {
//                dataToReturn = bytes
//            }
//            suspendGroup.wait()
//        }
//        return dataToReturn ?? Data()
//    }
}
