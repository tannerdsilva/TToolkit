import Foundation

enum ProcessError:Error {
    case processStillRunning
}

fileprivate func bashEscape(string:String) -> String {
	return "'" + string.replacingOccurrences(of:"'", with:"\'") + "'"
}

//InteractiveProcess must be launched and destroyed on a serial thread for stability.
//This is the internal run thread that TToolkit uses to launch new InteractiveProcess instances
fileprivate let serialProcess = DispatchQueue(label:"com.tannersilva.global.process-interactive.launch", qos:Priority.highest.asDispatchQoS())

//InteractiveProcess calls on this function to serially initialize the pipes and process objects that it needs to operate
fileprivate typealias ProcessAndPipes = (stdin:Pipe, stdout:Pipe, stderr:Pipe, process:Process)
fileprivate func initializePipesAndProcessesSerially(queue:DispatchQueue) -> ProcessAndPipes {
	return queue.sync {
		let stdinputPipe = Pipe()
		let stdoutputPipe = Pipe()
		let stderrorPipe = Pipe()
		let processObject = Process()
		return (stdin:stdinputPipe, stdout:stdoutputPipe, stderr:stderrorPipe, process:processObject)
	}
}

extension Process {
	fileprivate func signal(_ sign:Int32) -> Int32 {
		return kill(processIdentifier, sign)
	}
}


public class InteractiveProcess {
    public typealias OutputHandler = (Data) -> Void
    
    public let processQueue:DispatchQueue		//what serial thread is going to be used to process the data for each class instance?
    private let callbackQueue:DispatchQueue		//what global concurrent thread is going to be used to call back the handlers
    private let runGroup:DispatchGroup			//used to signify that the object is still "working"
    private let dataGroup:DispatchGroup			//used to signify that there is data that has been passed to a handler function that hasn't been appended to the internal buffers yet
    
	public enum State:UInt8 {
		case initialized = 0
		case running = 1
		case suspended = 2
		case exited = 4
		case failed = 5
	}
    
	public var env:[String:String]
	
	public var stdinPipe:Pipe
	public var stdoutPipe:Pipe
	public var stderrPipe:Pipe
	public var stdin:FileHandle { 
		get {
			return stdinPipe.fileHandleForWriting
		}
	}
	public var stdout:FileHandle {
		get {
			return stdoutPipe.fileHandleForReading
		}
	}
	public var stderr:FileHandle {
		get {
			return stderrPipe.fileHandleForReading
		}
	}
	
	public var stdoutBuff = Data()
	public var stderrBuff = Data()

	public var workingDirectory:URL
	internal var proc:Process
	public var state:State = .initialized
    
    private var _stdoutHandler:OutputHandler? = nil
    public var stdoutHandler:OutputHandler? {
        get {
        	return processQueue.sync {
        		return _stdoutHandler
        	}
        }
        set {
            processQueue.sync {
                _stdoutHandler = newValue
            }
        }
    }
    
    private var _stderrHandler:OutputHandler? = nil
    public var stderrHandler:OutputHandler? {
        get {
        	return processQueue.sync {
				return _stderrHandler
        	}   
        }
        set {
            processQueue.sync {
                _stderrHandler = newValue
            }
        }
    }
    
    

    public init<C>(command:C, qos:Priority = .`default`, workingDirectory wd:URL, run:Bool) throws where C:Command {
		processQueue = DispatchQueue(label:"com.tannersilva.instance.process-interactive.sync", qos:qos.asDispatchQoS())
		let concurrentGlobal = DispatchQueue.global(qos:qos.asDispatchQoS())
		callbackQueue = concurrentGlobal
		
		runGroup = DispatchGroup()
		dataGroup = DispatchGroup()
		
		env = command.environment
		
		let pipesAndStuff = initializePipesAndProcessesSerially(queue:concurrentGlobal)
		
		stdinPipe = pipesAndStuff.stdin
		stdoutPipe = pipesAndStuff.stdout
		stderrPipe = pipesAndStuff.stderr
		
		proc = pipesAndStuff.process

		workingDirectory = wd
		proc.arguments = command.arguments
		proc.executableURL = command.executable
		proc.currentDirectoryURL = wd
		proc.standardInput = pipesAndStuff.stdin
		proc.standardOutput = pipesAndStuff.stdout
		proc.standardError = pipesAndStuff.stderr
		proc.qualityOfService = qos.asProcessQualityOfService()
		proc.terminationHandler = { [weak self] someItem in
			guard let self = self else {
				return
			}
			self.dataGroup.wait()
			self.processQueue.sync {
				self.state = .exited
				serialProcess.sync {
					if #available(macOS 10.15, *) {
						try? self.stdinPipe.fileHandleForReading.close()
						try? self.stdoutPipe.fileHandleForReading.close()
						try? self.stderrPipe.fileHandleForReading.close()
						
						try? self.stdinPipe.fileHandleForWriting.close()
						try? self.stdoutPipe.fileHandleForWriting.close()
						try? self.stderrPipe.fileHandleForWriting.close()
						print(Colors.Yellow("[ CLOSED ]"))
					}
				}
			}
			self.runGroup.leave()
		}
        
        stdout.readabilityHandler = { [weak self] _ in
            guard let self = self else {
                return
            }
            self.dataGroup.enter()
            let readData = self.stdout.availableData
            let bytesCount = readData.count
            if bytesCount > 0 {
				let bytesCopy = readData.withUnsafeBytes({ return Data(bytes:$0, count:bytesCount) })
				self.appendStdoutData(bytesCopy)
            }
            self.dataGroup.leave()
        }
        
        stderr.readabilityHandler = { [weak self] _ in
            guard let self = self else {
                return
            }
            self.dataGroup.enter()
            let readData = self.stderr.availableData
            let bytesCount = readData.count
            if bytesCount > 0 {
				let bytesCopy = readData.withUnsafeBytes({ return Data(bytes:$0, count:bytesCount) })
				self.appendStderrData(bytesCopy)
            }
            self.dataGroup.leave()         
        }
        
		if run {
            do {
                try self.run()
            } catch let error {
                throw error
            }
		}
    }
    
    fileprivate func appendStdoutData(_ inputData:Data) {
    	dataGroup.enter()
    	processQueue.async { [weak self] in
			guard let self = self else {
				return
			}
    		self.stdoutBuff.append(inputData)
    		self.dataGroup.leave()
    	}
    }
    
    fileprivate func appendStderrData(_ inputData:Data) {
    	dataGroup.enter()
    	processQueue.async { [weak self] in
    		guard let self = self else {
    			return
    		}
    		self.stderrBuff.append(inputData)
    		self.dataGroup.leave()
    	}
    }
    
    public func run() throws {
        try processQueue.sync {
            do {
            	runGroup.enter()
            	
            	//framework must launch processes serially for complete thread safety
            	try serialProcess.sync {
					try proc.run()
            	}
            	
                state = .running
            } catch let error {
            	runGroup.leave()
                state = .failed
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
	
	public func exportStdOut() -> Data {
		return stdoutBuff
	}
	
	public func exportStdErr() -> Data {
		return stderrBuff
	}

    public func waitForExitCode() -> Int {
		runGroup.wait()
        let returnCode = proc.terminationStatus
        return Int(returnCode)
    }
    
    deinit {
    	print(Colors.yellow("{ deinit }"))
    }
}
