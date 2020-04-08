//
//  ExplodeExtensions.swift
//  Cryptor
//
//  Created by Tanner Silva on 10/17/19.
//

import Foundation

//explosions allow for multi-threaded collection mapping
fileprivate let _explodeGlobal = DispatchQueue(label:"com.tannersilva.function.explode.merge", attributes:[.concurrent])

extension Collection {
    fileprivate func sequenceBuffer<R>(_ work:@escaping(UnsafeBufferPointer<Element>) throws -> R) rethrows -> R {
		let buffer = UnsafeMutableBufferPointer<Element>.allocate(capacity: self.count)
        _ = buffer.initialize(from: self)
		defer {
			buffer.deallocate()
		}
		return try work(UnsafeBufferPointer(buffer))
	}

	public func explode(using thisFunction:@escaping (Int, Element) throws -> Void) {
		self.sequenceBuffer { unsafeBuff in
			print("O? \(unsafeBuff.count)")
			unsafeBuff._explode_v(using:thisFunction)
		}
	}
	
	public func explode<T>(using thisFunction:@escaping (Int, Element) -> T?, merge mergeFunction:@escaping (Int, T) -> Void) {
		self.sequenceBuffer { unsafeBuff in
			print("O? \(unsafeBuff.count)")
			unsafeBuff._explode_v_merge(using:thisFunction, merge:mergeFunction)
		}
	}
	
	public func explode<T>(using thisFunction:@escaping (Int, Element) -> T?) -> Set<T> where T:Hashable {
		return self.sequenceBuffer { unsafeBuff in
			print("O? \(unsafeBuff.count)")
			return unsafeBuff._explode_r_set(using:thisFunction)
		} ?? Set<T>()
	}
	
	public func explode<T, U>(using thisFunction:@escaping (Int, Element) -> (key:T, value:U)) -> [T:U] where T:Hashable {
		return self.sequenceBuffer { unsafeBuff in
			print("O? \(unsafeBuff.count)" )
			return unsafeBuff._explode_r_dict(using:thisFunction)
		} ?? [T:U]()
	}
}


extension UnsafeBufferPointer {
	//explode - no return values	
	fileprivate func _explode_v(using thisFunction:@escaping (Int, Element) throws -> Void) {
		guard let startIndex = baseAddress else {
			return
		}
		let value = ProcessInfo.processInfo.activeProcessorCount
        let launchGroup = DispatchGroup()
		let global = Priority.`default`.globalConcurrentQueue
		let masterQueue = DispatchQueue(label:"com.tannersilva.function.explode.merge", attributes:[.concurrent])
		var queues = [DispatchQueue]()
		for i in 0..<value {
			let newQueue = DispatchQueue(label:"com.tannersilva.function.explode.merge", target:masterQueue)
			queues.append(newQueue)
		}
		let callbackQueue = DispatchQueue(label:"com.tannersilva.function.explode.merge")
		DispatchQueue.concurrentPerform(iterations:count) { n in
			launchGroup.enter()
			let index = n % value
			let curQueue = queues[index]
//               launchSem.wait()
//               defer {
//                   launchSem.signal()
//               }
			print("\(n) - \(count) - \(index)")
			curQueue.async {
				defer {
					launchGroup.leave()
				}
				try? thisFunction(n, startIndex.advanced(by:n).pointee)
			}
		}
		launchGroup.leave()
		print("fin?")
	}

	//explode a collection - allows the user to handle the merging of data themselves.
	//return values of the primary `explode` block are passed to a serial thread where the user can handle the data as necessary
	fileprivate func _explode_v_merge<T>(using thisFunction:@escaping (Int, Element) throws -> T?, merge mergeFunction:@escaping (Int, T) throws -> Void) {
		guard let startIndex = baseAddress else {
			return
		}
		let value = ProcessInfo.processInfo.activeProcessorCount
        let launchGroup = DispatchGroup()
		let global = Priority.`default`.globalConcurrentQueue
		let masterQueue = DispatchQueue(label:"com.tannersilva.function.explode.master", attributes:[.concurrent])
		var queues = [DispatchQueue]()
		for i in 0..<value {
			let newQueue = DispatchQueue(label:"com.tannersilva.function.explode.branch", target:masterQueue)
			queues.append(newQueue)
		}
		let callbackQueue = DispatchQueue(label:"com.tannersilva.function.explode.merge")
		DispatchQueue.concurrentPerform(iterations:count) { n in
			launchGroup.enter()
			let index = n % value
			let curQueue = queues[index]
//               launchSem.wait()
//               defer {
//                   launchSem.signal()
//               }
			print("\(n) - \(count) - \(index)")
			curQueue.async {
				defer {
					launchGroup.leave()
				}
				if let returnedValue = try? thisFunction(n, startIndex.advanced(by:n).pointee) {
					callbackQueue.sync {
						try? mergeFunction(n, returnedValue)
					}
				}
			}
		}
		launchGroup.leave()
		print("fin?")
		return callbackQueue.sync { return }
	}

	//explode a collection - returns a set of hashable objects
	fileprivate func _explode_r_set<T>(using thisFunction:@escaping (Int, Element) throws -> T?) -> Set<T> where T:Hashable {
		guard let startIndex = baseAddress else {
			return Set<T>()
		}
		let value = ProcessInfo.processInfo.activeProcessorCount
        let launchGroup = DispatchGroup()
		var buildData = Set<T>()
		let global = Priority.`default`.globalConcurrentQueue
		let masterQueue = DispatchQueue(label:"com.tannersilva.function.explode.merge", attributes:[.concurrent])
		var queues = [DispatchQueue]()
		for i in 0..<value {
			let newQueue = DispatchQueue(label:"com.tannersilva.function.explode.merge", target:masterQueue)
			queues.append(newQueue)
		}
		let callbackQueue = DispatchQueue(label:"com.tannersilva.function.explode.merge")
		DispatchQueue.concurrentPerform(iterations:count) { n in
			launchGroup.enter()
			let index = n % value
			let curQueue = queues[index]
//               launchSem.wait()
//               defer {
//                   launchSem.signal()
//               }
			print("\(n) - \(count) - \(index)")
			curQueue.async {
				defer {
					launchGroup.leave()
				}
				if let returnedValue = try? thisFunction(n, startIndex.advanced(by:n).pointee) {
					callbackQueue.sync {
						buildData.update(with:returnedValue)
					}
				}
			}
		}
		launchGroup.leave()
		print("fin?")
		return callbackQueue.sync { return buildData }
	}

	//explode a collection - returns a dictionary
	fileprivate func _explode_r_dict<T, U>(using thisFunction:@escaping (Int, Element) throws -> (key:T, value:U)) -> [T:U] where T:Hashable {
		guard let startIndex = baseAddress else {
			return [T:U]()
		}
		let value = ProcessInfo.processInfo.activeProcessorCount
        let launchGroup = DispatchGroup()
		var buildData = [T:U]()
		let global = Priority.`default`.globalConcurrentQueue
		let masterQueue = DispatchQueue(label:"com.tannersilva.function.explode.merge", attributes:[.concurrent])
		var queues = [DispatchQueue]()
		for i in 0..<value {
			let newQueue = DispatchQueue(label:"com.tannersilva.function.explode.merge", target:masterQueue)
			queues.append(newQueue)
		}
		let callbackQueue = DispatchQueue(label:"com.tannersilva.function.explode.merge")
		DispatchQueue.concurrentPerform(iterations:count) { n in
			launchGroup.enter()
			let index = n % value
			let curQueue = queues[index]
//               launchSem.wait()
//               defer {
//                   launchSem.signal()
//               }
			print("\(n) - \(count) - \(index)")
			curQueue.async {
				if let returnedValue = try? thisFunction(n, startIndex.advanced(by:n).pointee) {
					if returnedValue.value != nil {
						callbackQueue.sync {
							buildData[returnedValue.key] = returnedValue.value
						}
					}
				}
			}
		}
		launchGroup.wait()
		print("fin?")
		return callbackQueue.sync { return buildData }
	}
}
