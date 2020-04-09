import Foundation

internal let process_master_queue = DispatchQueue(label:"com.tannersilva.global.process", qos:maximumPriority, attributes:[.concurrent])

extension Priority {
	internal var process_launch_priority:DispatchQoS {
		get {
			return self.asDispatchQoS(relative:-20)
		}
	}
	
	internal var process_callback_priority:DispatchQoS {
		get {
			return self.asDispatchQoS(relative:0)
		}
	}
	
	
	internal var process_reading_fast_capture_priority:DispatchQoS {
		get {
			return self.asDispatchQoS(relative:Int(Int32.max))
		}
	}
	
	internal var process_reading_priority:DispatchQoS {
		get {
			return self.asDispatchQoS(relative:100)
		}
	}
	
	internal var process_writing_priority:DispatchQoS {
		get {
			return self.asDispatchQoS(relative:50)
		}
	}
    
    internal var process_terminate_priority:DispatchQoS {
        get {
            return self.asDispatchQoS(relative:300)
        }
    }
}

internal let global_lock_queue = DispatchQueue(label:"com.tannersilva.global.process.sync", attributes:[.concurrent])

//this queue is assigned a priority since it will be passed to a dispatchsource
internal let process_read_fast_capture = DispatchQueue(label:"com.tannersilva.global.process.read.capture", qos:Priority.highest.process_reading_fast_capture_priority, attributes:[.concurrent], target:Priority.highest.globalConcurrentQueue)

internal let process_launch_async_fast = DispatchQueue(label:"com.tannersilva.global.process.launch-serial", qos:maximumPriority, target:process_master_queue)

