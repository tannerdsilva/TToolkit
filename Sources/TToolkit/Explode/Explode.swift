//
//  ExplodeExtensions.swift
//  Cryptor
//
//  Created by Tanner Silva on 10/17/19.
//

import Foundation

extension Collection {
	//explode a collection - no return values
    public func explode(lanes:Int = ProcessInfo.processInfo.activeProcessorCount, qos:DispatchQoS.QoSClass = .unspecified, using thisFunction:@escaping (Int, Element) throws -> Void) {
        let semaphore = DispatchSemaphore(value:lanes)
        let computeThread = DispatchQueue.global(qos: qos)
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
    
    //explode a collection - allows the user to handle the merging of data themselves
    public func explode<T>(lanes:Int = ProcessInfo.processInfo.activeProcessorCount, qos:DispatchQoS.QoSClass = .unspecified, using thisFunction:@escaping (Int, Element) throws -> T?, merge mergeFunction:@escaping (Int, T) throws -> Void) {
        let semaphore = DispatchSemaphore(value:lanes)
        let mergeQueue = DispatchQueue(label:"com.ttoolkit.explode-merge")
        let computeThread = DispatchQueue.global(qos:qos)
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
    public func explode<T>(lanes:Int = ProcessInfo.processInfo.activeProcessorCount, qos:DispatchQoS.QoSClass = .unspecified, using thisFunction:@escaping (Int, Element) throws -> T?) -> Set<T> where T:Hashable {
        let semaphore = DispatchSemaphore(value:lanes)
        let mergeQueue = DispatchQueue(label:"com.ttoolkit.explode-merge")
        let computeThread = DispatchQueue.global(qos:qos)
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
    public func explode<T, U>(lanes:Int = ProcessInfo.processInfo.activeProcessorCount, qos:DispatchQoS.QoSClass = .unspecified, using thisFunction:@escaping (Int, Element) throws -> (key:T, value:U)) -> [T:U] where T:Hashable {
        let semaphore = DispatchSemaphore(value:lanes)
        let mergeQueue = DispatchQueue(label:"com.ttoolkit.explode-merge")
        let computeThread = DispatchQueue.global(qos:qos)
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
