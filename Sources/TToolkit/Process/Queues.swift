import Foundation

internal let process_master_queue = DispatchQueue(label:"com.tannersilva.global.process", attributes:[.concurrent])
internal let global_lock_queue = DispatchQueue(label:"com.tannersilva.global.process.sync", attributes:[.concurrent], target:process_master_queue)
internal let global_pipe_read = DispatchQueue(label:"com.tannerdsilva.global.process.handle.read", qos:maximumPriority, attributes:[.concurrent], target:process_master_queue)
internal let global_run_queue = DispatchQueue(label:"com.tannerdsilva.global.process.launch", target:process_master_queue)

extension Priority {
	internal var process_launch_priority:DispatchQoS {
		get {
            return self.asDispatchQoS(relative:0)
		}
	}
	
	internal var process_async_priority:DispatchQoS {
		get {
			return self.asDispatchQoS(relative:15)
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

internal let global_pipe_lock = DispatchQueue(label:"com.tannersilva.global.pipe-init.sync", target:global_lock_queue)

//this queue is assigned a priority since it will be passed to a dispatchsource

internal let process_launch_async_fast = DispatchQueue(label:"com.tannersilva.global.process.launch-serial")
//internal let process_intialize_serial = DispatchQueue(label:"com.tannersilva.global.process.initialize-serial", target:process_master_queue)
//
//internal let g_process_launch_queue = DispatchQueue(label:"com.tannersilva.instance.process.launch", qos:maximumPriority, target:process_master_queue)
//internal let g_process_read_queue = DispatchQueue(label:"com.tannersilva.instance.process.read", qos:maximumPriority, target:process_master_queue)
//internal let g_process_write_queue = DispatchQueue(label:"com.tannersilva.instance.process.write", qos:maximumPriority, target:process_master_queue)
//internal let g_process_callback_queue = DispatchQueue(label:"com.tannersilva.instance.process.callback", qos:maximumPriority, target:process_master_queue)
//
