import Foundation
import KituraNet
import Kitura
import SSLService

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
		return SSLService.Configuration(withCACertificateDirectory:self.path, usingCertificateFile:self.fullchain.path, withKeyFile:self.privkey.path, usingSelfSignedCerts:selfSigned, cipherSuite:"ALL")
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
			print("[\(request.method.description.uppercased())] - \(request.originalURL)")
			next()
		}
	}
	
	public let router = Router(mergeParameters:false, enableWelcomePage:false)
	private var secureRedirect = InsecureRedirector()
	private var logger = TrafficLogger()
	private var servers = [HTTPServer]()
	
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
				if (newValue == true && insecureServers[curPort]!.state != .started) {
					try? insecureServers[curPort]!.listen(on:curPort)
				} else if (newValue == false && insecureServers[curPort]!.state == .started) {
					insecureServers[curPort]!.stop()
				}
			}
			
			for (n, curPort) in secureServers.keys.enumerated() {
				if (newValue == true && secureServers[curPort]!.state != .started) {
					try? secureServers[curPort]!.listen(on:curPort)
				} else if (newValue == false && secureServers[curPort]!.state == .started) {
					secureServers[curPort]!.stop()
				}
			}

		}
		get {
			let anyoneListening = secureServers.values.map { return $0.state == .started }
			return anyoneListening.contains(true)
		}
	}
	
	public init(webroot:URL, insecurePorts:[Int] = [80], securePorts:[Int] = [], authority:AuthorityCerts? = nil, redirectInsecure:Bool = true) throws {
		redirectInsecureTraffic = redirectInsecure
		secureRedirect.shouldRedirect = redirectInsecure
		
		//build the router stack
		let staticServer = StaticFileServer(path:webroot.path)
		router.all(middleware:secureRedirect)
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
				servers.append(newServer)
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
				servers.append(newServer)
			} catch let error {
				print(Colors.Red(" [FAILED] : Unable to bind to port \(curPort)"))
				throw error
			}
		}
		
		print(Colors.Green("\n[NOVA]\t[OK]"))
	}
}
