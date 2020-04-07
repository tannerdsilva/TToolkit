//
//  ExplodeExtensions.swift
//  Cryptor
//
//  Created by Tanner Silva on 10/17/19.
//

import Foundation

//explosions allow for multi-threaded collection mapping

extension Collection {
	//explode a collection - no return values
	public func explode(lanes:Int = ProcessInfo.processInfo.activeProcessorCount, qos:Priority = .`default`, using thisFunction:@escaping (Int, Element) throws -> Void) {
		let semaphore = DispatchSemaphore(value:lanes)
		let computeThread = DispatchQueue(label:"com.tannersilva.function.explode.async", qos:qos.asDispatchQoS(), attributes:[.concurrent])
		let queueingGroup = DispatchGroup()
		let flightGroup = DispatchGroup()
		for (n, curItem) in enumerated() {
			queueingGroup.enter()
			computeThread.async {
				flightGroup.enter()
				semaphore.wait()
				queueingGroup.leave()
				do {
					try thisFunction(n, curItem)
				} catch _ {}
				semaphore.signal()
				flightGroup.leave()
			}
			queueingGroup.wait()
		}
		flightGroup.wait()
	}

	//explode a collection - allows the user to handle the merging of data themselves.
	//return values of the primary `explode` block are passed to a serial thread where the user can handle the data as necessary
	public func explode<T>(lanes:Int = ProcessInfo.processInfo.activeProcessorCount, qos:Priority = .`default`, using thisFunction:@escaping (Int, Element) throws -> T?, merge mergeFunction:@escaping (Int, T) throws -> Void) {
		let semaphore = DispatchSemaphore(value:lanes)
		let computeThread = DispatchQueue(label:"com.tannersilva.function.explode.async", qos:qos.asDispatchQoS(), attributes:[.concurrent])
		let mergeQueue = DispatchQueue(label:"com.tannersilva.function.explode.sync", target:computeThread)
		let queueingGroup = DispatchGroup()
		let flightGroup = DispatchGroup()
		for (n, curItem) in enumerated() {
			queueingGroup.enter()
			computeThread.async {
				flightGroup.enter()
				semaphore.wait()
				queueingGroup.leave()
				do {
					if let returnedValue = try thisFunction(n, curItem) {
						mergeQueue.sync {
							try? mergeFunction(n, returnedValue)
						}
					}
				} catch _ {}
				semaphore.signal()
				flightGroup.leave()
			}
			queueingGroup.wait()
		}
		flightGroup.wait()
	}

	//explode a collection - returns a set of hashable objects
	public func explode<T>(lanes:Int = ProcessInfo.processInfo.activeProcessorCount, qos:Priority = .`default`, using thisFunction:@escaping (Int, Element) throws -> T?) -> Set<T> where T:Hashable {
		let semaphore = DispatchSemaphore(value:lanes)
		let computeThread = DispatchQueue(label:"com.tannersilva.function.explode.async", qos:qos.asDispatchQoS(), attributes:[.concurrent])
		let mergeQueue = DispatchQueue(label:"com.tannersilva.function.explode.sync", target:computeThread)
		let queueingGroup = DispatchGroup()
		let flightGroup = DispatchGroup()
	
		var buildData = Set<T>()
	
		for (n, curItem) in enumerated() {
			queueingGroup.enter()
			computeThread.async {
				flightGroup.enter()
				semaphore.wait()
				queueingGroup.leave()
			
				do {
					if let returnedValue = try thisFunction(n, curItem) {
						mergeQueue.sync {
							_ = buildData.update(with:returnedValue)
						}
					}
				} catch _ {}
			
				semaphore.signal()
				flightGroup.leave()
			}
			queueingGroup.wait()
		}
	
		flightGroup.wait()
		return buildData
	}

	//explode a collection - returns a dictionary
	public func explode<T, U>(lanes:Int = ProcessInfo.processInfo.activeProcessorCount, qos:Priority = .`default`, using thisFunction:@escaping (Int, Element) throws -> (key:T, value:U)) -> [T:U] where T:Hashable {
		let semaphore = DispatchSemaphore(value:lanes)
		let computeThread = DispatchQueue(label:"com.tannersilva.function.explode.async", qos:qos.asDispatchQoS(), attributes:[.concurrent])
		let mergeQueue = DispatchQueue(label:"com.tannersilva.function.explode.sync", target:computeThread)
		let queueingGroup = DispatchGroup()
		let flightGroup = DispatchGroup()
	
		var buildData = [T:U]()
		for (n, curItem) in enumerated() {
			queueingGroup.enter()
			computeThread.async {
				flightGroup.enter()
				semaphore.wait()
				queueingGroup.leave()
			
				do {
					let returnedValue = try thisFunction(n, curItem)
					if returnedValue.value != nil {
						mergeQueue.sync {
							buildData[returnedValue.key] = returnedValue.value
						}
					}
				} catch _ {}
			
				semaphore.signal()
				flightGroup.leave()
			}
			queueingGroup.wait()
		}
		flightGroup.wait()
		return buildData
	}
}
