import Foundation

internal let process_master_queue = DispatchQueue(label:"com.tannersilva.global.process", attributes:[.concurrent])
internal let file_handle_guard = DispatchQueue(label:"com.tannersilva.global.process.fh.sync", target:process_master_queue)
internal let global_lock_queue = DispatchQueue(label:"com.tannersilva.global.process.sync", attributes:[.concurrent], target:process_master_queue)
internal let global_pipe_read = DispatchQueue(label:"com.tannerdsilva.global.process.handle.read", qos:maximumPriority, attributes:[.concurrent])
internal let global_run_queue = DispatchQueue(label:"com.tannerdsilva.global.process.launch", target:process_master_queue)

internal let global_pipe_lock = DispatchQueue(label:"com.tannersilva.global.pipe-init.sync", target:global_lock_queue)

internal let process_launch_async_fast = DispatchQueue(label:"com.tannersilva.global.process.launch-serial")
