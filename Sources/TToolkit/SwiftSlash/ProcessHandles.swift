import Foundation

internal typealias ReadHandler = (Data) -> Void
internal typealias WriteHandler = () -> Void

/*
	IODescriptor
	==============================================
	file descriptors are represented as Int32 on Darwin and Linux. IODescriptor is a protocol that defines the file descriptor value as a protocol, so that it can be extended for convenient functionality
*/
internal protocol IODescriptor {
    var _fd:Int32 { get }
}
extension Int32:IODescriptor {
    var _fd:Int32 {
        get {
            return self
        }
    }
    var fileDescriptor: Int32 {
        get {
            return self
        }
    }
}
extension IODescriptor {
    func availableData() -> Data? {
        var statbuf = stat()
        if fstat(_fd, &statbuf) < 0 {
            return nil
        }
    
        let readBlockSize:Int
        if statbuf.st_mode & S_IFMT == S_IFREG && statbuf.st_blksize > 0 {
            readBlockSize = Int(clamping:statbuf.st_blksize)
        } else {
            readBlockSize = 10240
        }

        guard var dynamicBuffer = malloc(readBlockSize + 1) else {
            return nil
        }
        defer {
            free(dynamicBuffer)
        }
    
        let amountRead = read(_fd, dynamicBuffer, readBlockSize)
        guard amountRead > 0 else {
            return nil
        }
        let bytesBound = dynamicBuffer.bindMemory(to:UInt8.self, capacity:amountRead)
        return Data(bytes:bytesBound, count:amountRead)
    }
    
    func availableDataLoop(_ outputFunction:(Data?) -> Void) {
    	var i = 0
    	var bytesCaptured = 0
        while let curData = self.availableData(), curData.count > 0 {
            outputFunction(curData)
            bytesCaptured += curData.count
            i += 1
        }
//        print(Colors.Green("Available Data Loop Itterated \(i) times for a cumulative total of \(bytesCaptured) bytes"))
    }
}

/*
	IOPipe
	========================
	IOPipe is a protocol representation of posix pipes.
	Posix pipes are a set of file descriptors that are created as unique pairs. Data written to the writing end of the pipe is readable in the reading end of the pipe.
	Posix pipes are the primary means of transporting data from external processes back to the spawning process.
*/
internal protocol IOPipe {
    var reading:IODescriptor { get }
    var writing:IODescriptor { get }
}


/*
	PipeReader
	=================================
	This is an internal class that is responsible for IO globally across all running shell commands.
	PipeReader will buffer the incoming data, break it into lines, and flush these lines out to the user-accessable instances for downstream consumption
*/
internal class PipeReader {

	/*
		HandleState
		====================================================
		For every file handle that the PipeReader needs to read, a HandleState class is created to assist in buffering, parsing, and delivering the data downstream to the consumer
		PipeReader feeds data to the appropriate HandleState as soon as it becomes available.
	*/
    private class HandleState {
        let handle:Int32
        let source:DispatchSourceProtocol
        
        private let captureQueue:DispatchQueue
        private let callbackQueue:DispatchQueue
        private let internalSync:DispatchQueue
        
        //pending new lines
        private var buffer = Data()
        
        private var handler:InteractiveProcess.OutputHandler
        
        //related to flushing the final io after a process exits
        var flushWait:DispatchSemaphore
        
        init(handle:Int32, callback:DispatchQueue, handler:@escaping(InteractiveProcess.OutputHandler), source:DispatchSourceProtocol, capture:DispatchQueue, flush:DispatchSemaphore) {
            self.handle = handle
            self.captureQueue = capture
            internalSync = DispatchQueue(label:"com.tannersilva.instance.pipe.read.internal.sync")
            callbackQueue = DispatchQueue(label:"com.tannersilva.instance.pipe.read.callback-target.serial", target:callback)
            self.handler = handler
            self.source = source
            self.flushWait = flush
        }
        
        internal func intakeData(_ data:Data) {
            internalSync.sync {
                self.buffer.append(data)
				data.withUnsafeBytes({ unsafeBuffer in
				   if unsafeBuffer.contains(where: { $0 == 10 || $0 == 13 }) {
					   self.makeLineCallback(flush:false)
				   }
				})
        	}
        }
        
        func makeLineCallback(flush:Bool) {
            callbackQueue.sync {
                if let linesToCallback = self.extractLines(flush:flush) {
                    for (_, curLine) in linesToCallback.enumerated() {
                        self.handler(curLine)
                    }
                }
            }
        }

        func extractLines(flush:Bool) -> [Data]? {
			let parseResult = buffer.lineSlice(removeBOM:false, completeLinesOnly:!flush)
			buffer.removeAll(keepingCapacity: true)
			
			if flush == false {
				//add any incomplete lines back into the queue
				if parseResult.remain != nil && parseResult.remain!.count > 0 {
					buffer.append(parseResult.remain!)
				} else {
					print(Colors.bgMagenta("DID NOT APPEND NONFLUSHED DATA \(parseResult.remain?.count) \(parseResult.lines?.count) \(parseResult.lines?.map({ $0.count }).reduce(0, +))"))
				}
			}
			return parseResult.lines
        }
        
        //flushes all lines from the buffer queue
        func flushAll(_ terminatingAction:@escaping() -> Void) {
        	captureQueue.async { [terminatingAction] in
				self.internalSync.sync { [terminatingAction] in
					self.makeLineCallback(flush:true)
					terminatingAction()
					self.source.cancel()
					
					//signal the flush semaphore, if one exists
					self.flushWait.signal()
				}
            }
        }
        
        func initiateCapture() {
        	captureQueue.sync {
        		self.handle.availableDataLoop({ (someData) in 
        			if let realData = someData, realData.count > 0 {
        				self.intakeData(realData)
        			}
        		})
        	}
        }
    }
    var accessSync:DispatchQueue
    
    private var handles = [Int32:PipeReader.HandleState]()

	init() {
        self.accessSync = DispatchQueue(label:"com.tannersilva.global.pipe.handle.access.sync", attributes:[.concurrent], target:process_master_queue)
	}
    
	func scheduleForReading(_ handle:Int32, queue:DispatchQueue, handler:@escaping(InteractiveProcess.OutputHandler)) {
        let intakeQueue = DispatchQueue(label:"com.tannersilva.instance.pipe.handle.read.capture", target:global_pipe_read)
        let newSource = DispatchSource.makeReadSource(fileDescriptor:handle, queue:intakeQueue)
        let flushSemaphore = DispatchSemaphore(value:0)
        let newHandleState = PipeReader.HandleState(handle:handle, callback: queue, handler:handler, source: newSource, capture: intakeQueue, flush:flushSemaphore)
        newSource.setEventHandler(handler: { [handle, newHandleState] in
            handle.availableDataLoop({ [newHandleState] (someData) in
                if let validateData = someData {
                    newHandleState.intakeData(validateData)
                }
            })
        })
        newSource.activate()
        accessSync.async(flags:[.barrier]) { [newHandleState] in
            self.handles[handle] = newHandleState
        }
    }
    
    fileprivate func asyncRemove(_ handle:Int32) {
        accessSync.async(flags:[.barrier]) { [handle, self] in
            self.handles[handle] = nil
        }
    }
    
    func unschedule(_ handle:Int32, _ closingWork:@escaping() -> Void) {
        accessSync.sync(flags:[.barrier]) { [self, handle, closingWork] in
        	self.handles[handle]?.initiateCapture()
            self.handles[handle]?.flushAll({ [self, handle, closingWork] in
                closingWork()
                self.asyncRemove(handle)
            })
        }
    }
    
    //this is used by the user instances immediately after waitpid to ensure that io has flushed properly after a process has finished running
    func awaitFlush(_ handle:Int32) {
        let waitSemaphore:DispatchSemaphore? = accessSync.sync { [self, handle] in
    		let returnSem = self.handles[handle]?.flushWait
    		print(Colors.dim("Returning semaphore for waiting: \(returnSem)"))
    		return returnSem
    	}
    	if waitSemaphore != nil {
    		waitSemaphore!.wait()
    	}
    }
}
internal let globalPR = PipeReader()

//the exported pipe is passed to forked child processes. would rather pass structured data to forking
internal enum pipe_errors:Error {
    case unableToCreatePipes
}
internal struct ExportedPipe:Hashable {
    let reading:Int32
    let writing:Int32
    
    internal static func nullPipe() throws -> ExportedPipe {
        let read = open("/dev/null", O_RDWR)
        let write = open("/dev/null", O_WRONLY)
        _ = fcntl(read, F_SETFL, O_NONBLOCK)
        _ = fcntl(write, F_SETFL, O_NONBLOCK)
        guard read != -1 && write != -1 else {
            throw pipe_errors.unableToCreatePipes
        }
        return ExportedPipe(r:read, w:write)
    }
    
    internal static func rw(nonblock:Bool = false) throws -> ExportedPipe {
        let fds = UnsafeMutablePointer<Int32>.allocate(capacity:2)
        defer {
            fds.deallocate()
        }
        
        let rwfds = file_handle_guard.sync {
            return _pipe(fds)
        }
        
        switch rwfds {
            case 0:
                let readFD = fds.pointee
                let writeFD = fds.successor().pointee
				if nonblock == false || nonblock == true {
//					_ = fcntl(readFD, F_SETFL, O_NONBLOCK)
//					_ = fcntl(writeFD, F_SETFL, O_NONBLOCK)
				}
                print(Colors.magenta("created for reading [NONBLOCK]: \(readFD)"))
                print(Colors.magenta("created for writing: \(writeFD)"))
                return ExportedPipe(r:readFD, w:writeFD)
            default:
                throw pipe_errors.unableToCreatePipes
        }
    }

    init(reading:Int32, writing:Int32) {
        self.reading = reading
        self.writing = writing
    }
    
    init(r:Int32, w:Int32) {
        self.writing = w
        self.reading = r
    }
    
    func closeReading() {
        file_handle_guard.async { [reading = self.reading] in
            _ = _close(reading)
        }
    }
    
    func closeWriting() {
        file_handle_guard.async { [writing = self.writing] in
            _ = _close(writing)
        }
    }

    func close() {
        file_handle_guard.async { [reading = self.reading, writing = self.writing] in
            _ = _close(writing)
            _ = _close(reading)
        }
    }
    
    func hash(into hasher:inout Hasher) {
        hasher.combine(reading)
        hasher.combine(writing)
    }
    
    static func == (lhs:ExportedPipe, rhs:ExportedPipe) -> Bool {
        return lhs.reading == rhs.reading && lhs.writing == rhs.writing
    }
}

internal class ProcessHandle:Hashable, IODescriptor {
	enum ProcessHandleError:Error {
		case handleClosed
	}
	
	fileprivate let internalSync:DispatchQueue
	
	private var _isClosed:Bool
	var isClosed:Bool {
		get {
			return internalSync.sync {
				return _isClosed
			}
		}
	}
	
	internal let _fd:Int32
	var fileDescriptor:Int32 {
		get {
			internalSync.sync {
				return _fd
			}
		}
	}
	
	init(fd:Int32) {
		self._fd = fd
		self.internalSync = DispatchQueue(label:"com.tannersilva.instance.process-handle.sync", target:global_lock_queue)
		self._isClosed = false
	}
	
	func write(_ stringObj:String) throws {
		let stringData = try stringObj.safeData(using:.utf8)
		try self.write(stringData)
	}
	
	func write(_ dataObj:Data) throws {
		try internalSync.sync {
			guard _isClosed != true else {
				throw ProcessHandleError.handleClosed
			}
			try dataObj.withUnsafeBytes({
				if let hasBaseAddress = $0.baseAddress {
					try write(buf:hasBaseAddress, length:dataObj.count)
				}
			})
		}
	}
	
	fileprivate func write(buf:UnsafeRawPointer, length:Int) throws {
		var bytesRemaining = length
		var bytesWritten = _write(_fd, buf.advanced(by:length - bytesRemaining), bytesRemaining)
	}
    
	func availableData() -> Data? {
		return try? internalSync.sync {
			guard _isClosed != true else {
				throw ProcessHandleError.handleClosed
			}
			var statbuf = stat()
			if fstat(_fd, &statbuf) < 0 {
				return nil
			}
		
			let readBlockSize:Int
			if statbuf.st_mode & S_IFMT == S_IFREG && statbuf.st_blksize > 0 {
				readBlockSize = Int(clamping:statbuf.st_blksize)
			} else {
				readBlockSize = 1024 * 8
			}
		
			guard var dynamicBuffer = malloc(readBlockSize + 1) else {
				return nil
			}
			defer {
				free(dynamicBuffer)
			}
		
			let amountRead = read(_fd, dynamicBuffer, readBlockSize)
			guard amountRead > 0 else {
				return nil
			}
			let bytesBound = dynamicBuffer.bindMemory(to:UInt8.self, capacity:amountRead)
			return Data(bytes:bytesBound, count:amountRead)
		}
	}

	func hash(into hasher:inout Hasher) {
		hasher.combine(_fd)
	}
	
	static func == (lhs:ProcessHandle, rhs:ProcessHandle) -> Bool {
		return lhs._fd == rhs._fd
	}
}
