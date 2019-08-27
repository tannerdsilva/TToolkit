import SwiftShell
import Regex
import Foundation

public class Authority {
	public enum RefreshError:Swift.Error {
		case sudoAuthenticationError
		case certbotError
		case certbotNotInstalled
		case unableToAuthenticate
	}
	
	public class func certificates(domains:[String], forConsumptionIn caDir:URL, webroot:URL? = nil, email:String) throws {
		//validate that sudo will allow these commands to be executed
		do {
			for (_, curDomain) in domains.enumerated() {
				let consumptionDirectory = caDir.appendingPathComponent(curDomain, isDirectory:true)
				guard validateSudoPermissions(domain:curDomain, forConsumptionIn:consumptionDirectory) == true else {
					throw RefreshError.sudoAuthenticationError
				}
			}
		} catch let error {
			switch (error) {
				//if the validation fails
				case RefreshError.sudoAuthenticationError:
					//login as sudo
					let sudoContext = CustomContext(main)
					let currentUser = run(bash:"whoami").stdout
					var currentUserPass:String? = nil
					if (currentUser != "root") {
						var i = 0
						repeat {
							if (i > 0) {
								print(Colors.Red("[ERROR]\tSudo did not accept this password for \(currentUser)"))
							}
							currentUserPass = prompt(with:"[SUDO] Please enter \(currentUser)'s password for sudo")
							i += 1
						} while (loginSudo(password:currentUserPass, logoutAfterTest:false, context:sudoContext) == false && i < 3)
		
						if (i == 3) {
							print(Colors.Red("[SUDO][ERROR]\tUnable to log in to sudo as \(currentUser). Too many login attempts."))
							throw RefreshError.unableToAuthenticate
						}
					}
					
					//clean all current domains
					print(Colors.Yellow("[AUTHORITY]\tCleaning domain permissions..."))
					for (_, curDomain) in domains.enumerated() {
						cleanSudoPermissions(domain:curDomain, sudoContext:sudoContext)
					}
					
					//install the new domain ruleset
					print(Colors.Green("[AUTHORITY]\tInstalling domain permissions..."))
					for (_, curDomain) in domains.enumerated() {
						try permitSSLInstall(domain:curDomain, toConsumptionDirectory:caDir.appendingPathComponent(curDomain, isDirectory:true), sudoContext:sudoContext)
					}
				default:
				throw error
			}
		}
		
		//spin up a temporary webserver if webroot was not provided to this function
		var tempServer:Nova? = nil
		let serveRoot = FileManager.default.temporaryDirectory.appendingPathComponent(String.random(length:10), isDirectory:true)
		if (webroot == nil) {
			if (FileManager.default.fileExists(atPath:serveRoot.path) == false) {
				try FileManager.default.createDirectory(at:serveRoot, withIntermediateDirectories:false)
			}
			tempServer = try Nova(webroot:serveRoot, redirectInsecure:false)
		}

		for (_, curDomain) in domains.enumerated() {
			let consumptionDirectory = caDir.appendingPathComponent(curDomain, isDirectory:true)
			try refreshCertificate(domain:curDomain, at:consumptionDirectory, webroot:webroot ?? serveRoot, email:email)
		}
		
		if (tempServer != nil) {
			tempServer!.isListening = false
		}
		
		if (webroot == nil && FileManager.default.fileExists(atPath:serveRoot.path) == true) {
			do {
				try FileManager.default.removeItem(at:serveRoot)
			} catch let error {
				print(Colors.Red("[ERROR]\tThere was a problem trying to remove the temporary webroot directory at \(serveRoot.path)"))
				print(error)
			}
		}
	}

	//the "one call" solution
//	public class func certificates(domain:String, forConsumptionIn directory:URL, webroot:URL, email:String, forceCertificateCopy:Bool = false) throws {
//		var tempServer:Nova? = nil
//		let serveRoot = FileManager.default.temporaryDirectory.appendingPathComponent(String.random(length:10), isDirectory:true)
//		if (webroot == nil) {
//			if (FileManager.default.fileExists(atPath:serveRoot.path) == false) {
//				try FileManager.default.createDirectory(at:serveRoot, withIntermediateDirectories:false)
//			}
//			tempServer = try Nova(webroot:serveRoot, redirectInsecure:false)
//		}
//		
//		do {
//			//try getting certs. will there be an authentication error thrown?
//			try refreshCertificates(domain:domain, at:directory, webroot:webroot ?? serveRoot, email:email)
//			if (tempServer != nil) {
//				tempServer!.isListening = false
//			}
//		} catch let error {
//			switch (error) {
//			case RefreshError.sudoAuthenticationError:
//				print(Colors.bold(Colors.Red("[AUTHORITY]\tUnable to load certificates for \(domain) to \(directory.path). Please authenticate with SUDO to allow this to be done without a password in the future.")))
//				//prompt the user for their sudo password so that we can adjust sudoers.d to permit the acquisition of these certificates
//				try permitSSLInstall(domain:domain, toConsumptionDirectory:directory)
//			
//				//try acquiring again now that the user has authenticated with sudo and the adjustments have been made
//				do {
//					try refreshCertificates(domain:domain, at:directory, webroot:webroot ?? serveRoot, email:email)
//					if (tempServer != nil) {
//						tempServer!.isListening = false
//					}
//				} catch let secondError {
//					if (tempServer != nil) {
//						tempServer!.isListening = false
//					}
//					try? FileManager.default.removeItem(at:serveRoot)
//					throw secondError
//				}
//			default:
//			throw error
//			}
//		}
//		
//	}
	
	//MARK: SUPPORTING FUNCTIONS
	//private refresh function
	private class func refreshCertificate(domain:String, at consumptionDirectory:URL, webroot:URL, email:String) throws -> Bool {
		let cp = URL(fileURLWithPath:run(bash:"which cp").stdout)
		let certbot = URL(fileURLWithPath:run(bash:"which certbot").stdout)
		let thisUser = run(bash:"whoami").stdout
		let chown = URL(fileURLWithPath:run(bash:"which chown").stdout)
		let fullchain_cons = consumptionDirectory.appendingPathComponent("fullchain.pem", isDirectory:false)
		let privkey_cons = consumptionDirectory.appendingPathComponent("privkey.pem", isDirectory:false)
		let domainLive = URL(fileURLWithPath:"/etc/letsencrypt/live/\(domain)/")
		let fullchain_live = domainLive.appendingPathComponent("fullchain.pem", isDirectory:false)
		let privkey_live = domainLive.appendingPathComponent("privkey.pem", isDirectory:false)
		
		//copies certificates from the letsencrypt live directory to the destination directory
		func copyCerts() throws {		
			let fullchainResult = run(bash:"sudo -n \(cp.path) '\(fullchain_live.path)' '\(consumptionDirectory.path)'")
			let privkeyResult = run(bash:"sudo -n \(cp.path) '\(privkey_live.path)' '\(consumptionDirectory.path)'")
		
			guard fullchainResult.succeeded == true else {
				print(Colors.Red(fullchainResult.stdout))
				print(Colors.Red("[AUTHORITY]\tThere was an error trying to copy the fullchain.pem file from the live directory to the consumption directory"))
				throw RefreshError.certbotError
			}
		
			guard privkeyResult.succeeded == true else {
				print(Colors.Red(privkeyResult.stdout))
				print(Colors.Red("[AUTHORITY]\tThere was an error trying to copy the privkey.pem file from the live directory to the consumption directory"))
				throw RefreshError.certbotError
			}
		}
		
		//owns the certificates at the given consumption directory to the given user.
		func chownCerts() throws {
			let fullchainOwnResult = run(bash:"sudo -n \(chown.path) \(thisUser):\(thisUser) '\(fullchain_cons.path)'")
			let privkeyOwnResult = run(bash:"sudo -n \(chown.path) \(thisUser):\(thisUser) '\(privkey_cons.path)'")
		
			guard fullchainOwnResult.succeeded == true else {
				print(Colors.Red(fullchainOwnResult.stdout))
				print(Colors.Red("There was an error trying to own the fullchain.pem file for user \(thisUser)"))
				throw RefreshError.certbotError
			}
		
			guard privkeyOwnResult.succeeded == true else {
				print(Colors.Red(fullchainOwnResult.stdout))
				print(Colors.Red("There was an error trying to own the privkey.pem file for user \(thisUser)"))
				throw RefreshError.certbotError
			}
		}

	
		let runCommand = "sudo -n \(certbot.path) certonly --webroot -n -v -d \(domain) --agree-tos -w \(webroot.path) --email \(email)"
		
		let runResult = run(bash:runCommand)
		guard runResult.succeeded == true else {
			dprint(Colors.Red("[AUTHORITY]\tunable to update certificates. sudo authentication error."))
			dprint(runResult.stdout)
			dprint(Colors.Red(runResult.stderror))
			throw RefreshError.certbotError
		}
		
		if runResult.stdout =~ "Congratulations! Your certificate and chain have been saved" {
			dprint(Colors.Green("[AUTHORITY]\tNew certificates acquired from the issuing authority."))
			try copyCerts()
			try chownCerts()
			return true
		} else if (runResult.stdout =~ "Certificate not yet due for renewal; no action taken.") {
			if (FileManager.default.fileExists(atPath:fullchain_cons.path) == false || FileManager.default.fileExists(atPath:fullchain_cons.path) == false) {
				try copyCerts()
				try chownCerts()
				dprint(Colors.Green("[AUTHORITY]\tNo certificates are due for renewal. However, the keys could not be found in the consumption directory. They have now been installed."))
				return true
			} else {
				dprint(Colors.dim("[AUTHORITY]\tNo certificates are due for renewal. Nothing as done."))
			}
		}
		return false
	}
	
	//installs the necessary permissions into sudoers to allow for easier utilization in the future
	private class func permitSSLInstall(domain:String, toConsumptionDirectory destURL:URL, consumingUser:String = run(bash:"whoami").stdout, sudoContext:CustomContext) throws {
		enum InstallError:Swift.Error {
			case authenticationError
			case stringDataError
			case invalidSudoSyntax
			case permissionProblem
		}
			
		guard sudoContext.run(bash:"sudo whoami").stdout == "root" else {
			print(Colors.Red("[AUTHORITY]\tpermitSSLInstall must be given a sudo-granted shell context"))
			throw InstallError.authenticationError
		}

		let certbot = URL(fileURLWithPath:sudoContext.run(bash:"which certbot").stdout)
		let cp = URL(fileURLWithPath:sudoContext.run(bash:"which cp").stdout)
		let chown = URL(fileURLWithPath:sudoContext.run(bash:"which chown").stdout)
		
		let allowedCommands = [	
			"\(certbot.path) certonly --webroot -n -v -d \(domain) --agree-tos -w *",
			"\(cp.path) /etc/letsencrypt/live/\(domain)/fullchain.pem \(destURL.path)",
			"\(cp.path) /etc/letsencrypt/live/\(domain)/privkey.pem \(destURL.path)",
			"\(chown.path) \(consumingUser)\\:\(consumingUser) \(destURL.appendingPathComponent("fullchain.pem", isDirectory:false).path)",
			"\(chown.path) \(consumingUser)\\:\(consumingUser) \(destURL.appendingPathComponent("privkey.pem", isDirectory:false).path)",
		]
		let sudoersLines = allowedCommands.map { someCommand in
			return "\(consumingUser) ALL=(ALL) NOPASSWD: " + someCommand
		}
		let sudoersString = sudoersLines.joined(separator:"\n") + "\n"
		
		guard let sudoersData = sudoersString.data(using:.utf8) else {
			print(Colors.Red("[ERROR]\tUnable to convert String data to .utf8"))
			throw InstallError.stringDataError
		}
		
		let writeURL = FileManager.default.temporaryDirectory.appendingPathComponent(String.random(length:10), isDirectory:false)
		try sudoersData.write(to:writeURL)
		
		guard sudoContext.run(bash:"visudo -cf '\(writeURL.path)'").succeeded == true else {
			try? FileManager.default.removeItem(at:writeURL)
			dprint(Colors.Red("[ERROR]\tInvalid sudo syntax."))
			throw InstallError.invalidSudoSyntax
		}
		
		let dashedDomain = domain.replacingOccurrences(of:".", with:"-")
		let destinationPath = URL(fileURLWithPath:"/etc/sudoers.d/").appendingPathComponent(dashedDomain, isDirectory:false)
		
		let sudoersInstallResult = sudoContext.run(bash:"sudo \(cp.path) '\(writeURL.path)' '\(destinationPath.path)'")
		guard sudoersInstallResult.succeeded == true else {
			dprint(Colors.Red("[ERROR]\tThere was a problem installing the sudoers file"))
			try? FileManager.default.removeItem(at:writeURL)
			throw InstallError.permissionProblem
		}
		
		try FileManager.default.removeItem(at:writeURL)
		
		dprint(Colors.Green("[OK]\t\(consumingUser) is now allowed to install SSL certs for \(domain) to \(destURL.path)"))
	}

	//MARK: SUDO
	private class func cleanSudoPermissions(domain:String, sudoContext:CustomContext) {
		let dashedDomain = domain.replacingOccurrences(of:".", with:"-")
		let sudoersPath = URL(fileURLWithPath:"/etc/sudoers.d/").appendingPathComponent(dashedDomain, isDirectory:false)
		let rm = URL(fileURLWithPath:run(bash:"which rm").stdout)
		sudoContext.run(bash:"sudo \(rm.path) '\(sudoersPath.path)'")
	}
	
	private class func validateSudoPermissions(domain:String, forConsumptionIn directory:URL) -> Bool {
		let certbot = URL(fileURLWithPath:run(bash:"which certbot").stdout)
		let cp = URL(fileURLWithPath:run(bash:"which cp").stdout)
		let chown = URL(fileURLWithPath:run(bash:"which chown").stdout)
		let allowedList = run(bash:"sudo -l").stdout.split(separator:"\n").map { return String($0) }
		
		var certbotPassed = false	
		var owns = 0
		var cps = 0
		for (_, curListItem) in allowedList.enumerated() {
			if (curListItem =~ "NOPASSWD: \(certbot.path) certonly --webroot -n -v -d \(domain) --agree-tos -w *") {
				certbotPassed = true
			} else if (curListItem =~ "NOPASSWD: \(cp.path) .*\(domain)/.*\(directory.path)") {
				cps += 1
			} else if (curListItem =~ "NOPASSWD: \(chown.path) .*\(directory.path)") {
				owns += 1
			}
		}
		
		return (owns == 2 && cps == 2 && certbotPassed == true)
	}

	//tries to elevate to sudo with the given shell context with a given password.
	private class func loginSudo(password:String?, logoutAfterTest:Bool = true, context:CustomContext = CustomContext(main)) -> Bool {
		if (password == nil) {
			return false
		}
		let testRun = context.run(bash:"echo '' | { echo '\(password!)'; cat -; } | sudo -S whoami &> /dev/null")
		if (logoutAfterTest == true) {
			context.run(bash:"sudo -k") //logout again if necessary
		}
		return testRun.succeeded
	}
}