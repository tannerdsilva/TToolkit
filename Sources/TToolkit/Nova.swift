import Foundation
import KituraNet
import Kitura
import SSLService
import KituraCORS

public typealias AuthorityCerts = URL
extension AuthorityCerts {
	var fullchain:URL {
		return self.appendingPathComponent("fullchain.pem", isDirectory:false)
	}
	var privkey:URL {
		return self.appendingPathComponent("privkey.pem", isDirectory:false)
	}
	var baseDirectory:URL {
		return self
	}
	public func asSSLConfig(selfSigned:Bool = false) -> SSLService.Configuration {
		return SSLService.Configuration(withCACertificateDirectory:self.path, usingCertificateFile:nil, withKeyFile:nil, usingSelfSignedCerts:selfSigned, cipherSuite:"ALL")
	}
}

public class Nova {
	enum NovaError:Swift.Error {
		case noAuthorityCertificatesSpecified
	}
	
	//this class will redirect any insecure http traffic that it sees to the appropriate https
	private struct InsecureRedirector:RouterMiddleware {
		public var shouldRedirect:Bool = true
		
		func handle(request:RouterRequest, response:RouterResponse, next:@escaping () -> Void) throws {
			if (shouldRedirect == true && request.originalURL.hasPrefix("http://") == true) {
				let secureURL = request.originalURL.replacingOccurrences(of:"http://", with:"https://")
				try response.redirect(secureURL)
				try response.end()
			} else if (shouldRedirect == false) {
				print(Colors.Red("[NOVA]\tInsecure HTTP traffic will not be redirected to HTTPS")) 
			}
			next()
		}
	}
	
	private struct TrafficLogger:RouterMiddleware {
		public var shouldLog:Bool = true
		
		func handle(request:RouterRequest, response:RouterResponse, next:@escaping () -> Void) throws {
			print(Colors.dim("[\(request.method.description.uppercased())] - \(request.domain) - \(request.urlURL.path)"), terminator:"")
			if (request.queryParameters.count > 0) {
				print(Colors.dim(" - [\(request.queryParameters.count) query parameters included]"))
			} else {
				print("\n", terminator:"")
			}
			next()
		}
	}
	
	public let router = Router(mergeParameters:false, enableWelcomePage:false)
	private var secureRedirect = InsecureRedirector()
	private var logger = TrafficLogger()
	
	private var secureServers = [Int:HTTPServer]()
	private var insecureServers = [Int:HTTPServer]()
	
	public var redirectInsecureTraffic:Bool {
		set {
			secureRedirect.shouldRedirect = newValue
		}
		get {
			return secureRedirect.shouldRedirect
		}
	}
	
	public var isListening:Bool {
		set {
			for (n, curPort) in insecureServers.keys.enumerated() {
				if (newValue == true) {
					try? insecureServers[curPort]!.listen(on:curPort)
					dprint(Colors.Green("[NOVA]\tStarting server on port \(curPort)"))
				} else if (newValue == false) {
					insecureServers[curPort]!.stop()
					dprint(Colors.Red("[NOVA]\tStopping server on port \(curPort)"))
				}
			}
			
			for (n, curPort) in secureServers.keys.enumerated() {
				if (newValue == true) {
					try? secureServers[curPort]!.listen(on:curPort)
					dprint(Colors.Green("[NOVA]\tStarting server on port \(curPort)"))
				} else if (newValue == false) {
					secureServers[curPort]!.stop()
					dprint(Colors.Red("[NOVA]\tStopping server on port \(curPort)"))
				}
			}

		}
		get {
			let anyoneListening = secureServers.values.map { return $0.state == .started }
			return anyoneListening.contains(true)
		}
	}
	
	private var _epochTimer:Timer? = nil
	private var _epoching:Bool = false
	public var shouldRunEpoch:Bool {
		set {
			if (newValue == true && _epoching == false) {
				_epochTimer = Timer.scheduledTimer(withTimeInterval:2000, repeats:true, block: { [weak self] timer in
					guard let self = self, self._epoching == true else {
						timer.invalidate()
						return
					}
			
					self.epoch()
				})
			} else if (newValue == false && _epoching == true) {
				_epochTimer?.invalidate()
			}
			_epoching = newValue
		}
		get {
			return _epoching
		}
	}
	
	public init() {}

	public init(webroot:URL, insecurePorts:[Int] = [80], securePorts:[Int] = [], authority:AuthorityCerts? = nil, redirectInsecure:Bool = true, fullCors:Bool = false) throws {
		redirectInsecureTraffic = redirectInsecure
		secureRedirect.shouldRedirect = redirectInsecure

		//build the router stack
		let staticServer = StaticFileServer(path:webroot.path)
		router.all(middleware:secureRedirect)
		if (fullCors == true) {
			let kituraCors = CORS(options:Options())
			router.all(middleware:kituraCors)
		}
		router.all(middleware:logger)
		router.all(middleware:staticServer)
		
		print(Colors.Cyan("[NOVA]\t\(webroot.path)"), terminator:"")
		
		//bootstrap insecure servers
		for (i, curPort) in insecurePorts.enumerated() {
			if (i > 0) {
				print(Colors.Yellow(", "), terminator:"")
			} else if (i == 0) {
				print(Colors.Yellow("\n\tInsecure ports: "), terminator:"")
			}
			print(Colors.Yellow("\(curPort)"), terminator:"")
			do {
				let newServer = HTTPServer()
				newServer.delegate = router
				try newServer.listen(on:curPort)
				insecureServers[curPort] = newServer
			} catch let error {
				print(Colors.Red(" [FAILED]: Unable to bind to port \(curPort)"))
				throw error
			}
		}

		//bootstrap secure servers
		for (i, curPort) in securePorts.enumerated() {
			guard let authorityTest = authority else {
				print(Colors.Red("[NOVA][ERROR]\tUnable to launch nova with secure ports. No authority certificates specified with initialization."))
				throw NovaError.noAuthorityCertificatesSpecified
			}
			
			if (i > 0) {
				print(Colors.Yellow(", "), terminator:"")
			} else if (i == 0) {
				print(Colors.Yellow("\n\tSecure ports: "), terminator:"")
			}
			
			print(Colors.Yellow("\(curPort)"), terminator:"")
			do {
				let newServer = HTTPServer()
				newServer.delegate = router
				newServer.sslConfig = authorityTest.asSSLConfig()
				try newServer.listen(on:curPort)
				secureServers[curPort] = newServer
			} catch let error {
				print(Colors.Red(" [FAILED] : Unable to bind to port \(curPort)"))
				throw error
			}
		}
		
		shouldRunEpoch = true
		
		print(Colors.Green("\n[NOVA]\t[OK]"))
	}
	
	public func epoch() {}
}
