import Dispatch
import Foundation

#if canImport(Darwin)
	import Darwin
	internal let _read = Darwin.read(_:_:_:)
	internal let _write = Darwin.write(_:_:_:)
	internal let _close = Darwin.close(_:)
	internal let o_cloexec = Darwin.O_CLOEXEC
	internal let _pipe = Darwin.pipe(_:)
#elseif canImport(Glibc)
	import Glibc
	internal let _read = Glibc.read(_:_:_:)
	internal let _write = Glibc.write(_:_:_:)
	internal let _close = Glibc.close(_:)
	internal let o_cloexec = Glibc.O_CLOEXEC
	internal let _pipe = Glibc.pipe(_:)
#endif

internal typealias ReadHandler = (Data) -> Void
internal typealias WriteHandler = () -> Void

internal protocol IODescriptor {
    var _fd:Int32 { get }
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
            readBlockSize = SSIZE_MAX
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

internal protocol IOPipe {
    var reading:IODescriptor { get }
    var writing:IODescriptor { get }
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



internal class PipeReader {
    private class HandleState {
        let handle:Int32
        let source:DispatchSourceProtocol
        private let internalSync:DispatchQueue
        private var buffer = Data()

        init(handle:Int32, source:DispatchSourceProtocol) {
            self.handle = handle
            internalSync = DispatchQueue(label:"com.tannersilva.instance.pipe.read.internal.sync")
            self.source = source
        }
        
        func intake(_ data:Data?) -> [Data]? {
            guard let newData = data, newData.count > 0 else {
                return nil
            }
            internalSync.async { [newData] in
                self.buffer.append(newData)
            }
            let hasNewLine = newData.withUnsafeBytes({ unsafeByteBuff -> Bool in
                if unsafeByteBuff.contains(where: { $0 == 10 || $0 == 13 }) {
                    return true
                }
                return false
            })
            if hasNewLine {
                return self.extractLines()
            } else {
                return nil
            }
        }
        
        internal func extractLines() -> [Data]? {
            return internalSync.sync {
                let parseResult = buffer.lineSlice(removeBOM:false, completeLinesOnly:true)
                buffer.removeAll(keepingCapacity: true)
                if parseResult.remain != nil && parseResult.remain!.count > 0 {
                    buffer.append(parseResult.remain!)
                }
                return parseResult.lines
            }
        }
    }
    
    var accessQueue:DispatchQueue
    private var handles = [Int32:PipeReader.HandleState]()
    private func access<R>(_ handle:Int32, _ work:(PipeReader.HandleState) throws -> R) rethrows -> R {
        return try accessQueue.sync {
            return try { [bufState = self.handles[handle]!] in
                try work(bufState)
            }()
        }
    }
    private func accessAsssign(_ handle:Int32, _ work:@autoclosure() throws -> PipeReader.HandleState) rethrows {
        return try accessQueue.sync(flags:[.barrier]) { [work] in
            return try self.handles[handle] = work()
        }
    }
	
	init() {
        self.accessQueue = DispatchQueue(label:"com.tannersilva.global.pipe.handle.access.sync", attributes:[.concurrent])
	}
    
    internal func readHandle(_ handle:Int32) -> [Data]? {
        var dataBuild = Data()
        while let curNewData = handle.availableData() {
            dataBuild.append(curNewData)
        }
        let newLines = access(handle) { [dataBuild] handleState in
            return handleState.intake(dataBuild)
        }
        return newLines
	}
	
	func scheduleForReading(_ handle:Int32, queue:DispatchQueue, handler:@escaping(InteractiveProcess.OutputHandler)) {
        let newSource = DispatchSource.makeReadSource(fileDescriptor:handle, queue:global_pipe_read)
        let newHandle = HandleState(handle:handle, source: newSource)
        accessAsssign(handle, newHandle)
        newSource.setEventHandler(handler: { [handle, handler, queue] in
            if let newLines = self.readHandle(handle) {
                queue.async { [newLines, handler] in
                    for (_, curLine) in newLines.enumerated() {
                        handler(curLine)
                    }
                }
            }
        })
        newSource.activate()
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
    
    internal static func rw() throws -> ExportedPipe {
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
//                fcntl(readFD, F_SETFL, O_NONBLOCK)
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
		while bytesRemaining > 0 {
			var bytesWritten = 0
			repeat {
				bytesWritten = _write(_fd, buf.advanced(by:length - bytesRemaining), bytesRemaining)
			} while (bytesWritten < 0 && errno == EINTR)
			bytesRemaining -= bytesWritten
		}
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
