import SwiftShell
import Regex
import Foundation

public class Authority {
	public enum RefreshError:Swift.Error {
		case sudoAuthenticationError
		case certbotError
		case certbotNotInstalled
	}

	//the "one call" solution
	public class func certificates(domain:String, forConsumptionIn directory:URL, webroot:URL? = nil, email:String, forceCertificateCopy:Bool = false) throws {
		var tempServer:Nova? = nil
		let serveRoot = FileManager.default.temporaryDirectory.appendingPathComponent(String.random(length:10), isDirectory:true)
		if (webroot == nil) {
			if (FileManager.default.fileExists(atPath:serveRoot.path) == false) {
				try FileManager.default.createDirectory(at:serveRoot, withIntermediateDirectories:false)
			}
			tempServer = try Nova(webroot:serveRoot, redirectInsecure:false)
		}
		
		do {
			//try getting certs. will there be an authentication error thrown?
			try refreshCertificates(domain:domain, at:directory, webroot:webroot ?? serveRoot)
			if (tempServer != nil) {
				tempServer!.isListening = false
			}
		} catch let error {
			switch (error) {
			case RefreshError.sudoAuthenticationError:
				print(Colors.bold(Colors.Red("[AUTHORITY]\tUnable to load certificates for \(domain) to \(directory.path). Please authenticate with SUDO to allow this to be done without a password in the future.")))
				//prompt the user for their sudo password so that we can adjust sudoers.d to permit the acquisition of these certificates
				try permitSSLInstall(domain:domain, toConsumptionDirectory:directory)
			
				//try acquiring again now that the user has authenticated with sudo and the adjustments have been made
				do {
					try refreshCertificates(domain:domain, at:directory, webroot:webroot ?? serveRoot)
					if (tempServer != nil) {
						tempServer!.isListening = false
					}
				} catch let secondError {
					if (tempServer != nil) {
						tempServer!.isListening = false
					}
					try? FileManager.default.removeItem(at:serveRoot)
					throw secondError
				}
			default:
			throw error
			}
		}
		
	}
	
	//MARK: SUPPORTING FUNCTIONS
	//private refresh function
	private class func refreshCertificates(domain:String, at consumptionDirectory:URL, webroot:URL, email:String? = nil, forceCopy:Bool = false) throws -> Bool {
		let cp = URL(fileURLWithPath:run(bash:"which cp").stdout)
		let certbot = URL(fileURLWithPath:run(bash:"which certbot").stdout)
		let thisUser = run(bash:"whoami").stdout
		let chown = URL(fileURLWithPath:run(bash:"which chown").stdout)
		let fullchain_cons = consumptionDirectory.appendingPathComponent("fullchain.pem", isDirectory:false)
		let privkey_cons = consumptionDirectory.appendingPathComponent("privkey.pem", isDirectory:false)
		let domainLive = URL(fileURLWithPath:"/etc/letsencrypt/live/\(domain)/")
		let fullchain_live = domainLive.appendingPathComponent("fullchain.pem", isDirectory:false)
		let privkey_live = domainLive.appendingPathComponent("privkey.pem", isDirectory:false)

		guard certbot.path.length > 1 else {
			print(Colors.Red("Please install certbot and try again."))
			throw RefreshError.certbotNotInstalled
		}
		guard validateSudoPermissions(domain:domain, forConsumptionIn:consumptionDirectory) == true else {
			throw RefreshError.sudoAuthenticationError
		}
		
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

	
		var runCommand = "sudo -n \(certbot.path) certonly --webroot -n -v -d \(domain) -w \(webroot.path)"
		if (email != nil) {
			runCommand += " -m \(email)"
		}
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
	private class func permitSSLInstall(domain:String, toConsumptionDirectory destURL:URL, consumingUser:String = run(bash:"whoami").stdout) throws {
		enum InstallError:Swift.Error {
			case authenticationError
			case stringDataError
			case invalidSudoSyntax
			case permissionProblem
		}

		//elevate to root status (get the sudoers credentials for the actively running user)
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
			} while (validateSudo(password:currentUserPass) == false && i < 3)
			
			if (i == 3) {
				print(Colors.Red("[SUDO][ERROR]\tUnable to log in to sudo as \(currentUser). Too many login attempts."))
				throw InstallError.authenticationError
			}
		}

		var installContext = CustomContext(main)
		guard validateSudo(password:currentUserPass, logoutAfterTest:false, context:installContext) == true else {
			print(Colors.Red("Unable to login with sudo in the custom installation shell context."))
			throw InstallError.authenticationError
		}

		let certbot = URL(fileURLWithPath:installContext.run(bash:"which certbot").stdout)
		let cp = URL(fileURLWithPath:installContext.run(bash:"which cp").stdout)
		let chown = URL(fileURLWithPath:installContext.run(bash:"which chown").stdout)
		
		let allowedCommands = [	
			"\(certbot.path) certonly --webroot -n -v -d \(domain) -w *",
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
		
		guard installContext.run(bash:"visudo -cf '\(writeURL.path)'").succeeded == true else {
			try? FileManager.default.removeItem(at:writeURL)
			dprint(Colors.Red("[ERROR]\tInvalid sudo syntax."))
			throw InstallError.invalidSudoSyntax
		}
		
		let sudoersInstallResult = installContext.run(bash:"sudo \(cp.path) '\(writeURL.path)' '/etc/sudoers.d/\(consumingUser)'")
		guard sudoersInstallResult.succeeded == true else {
			dprint(Colors.Red("[ERROR]\tThere was a problem installing the sudoers file"))
			try? FileManager.default.removeItem(at:writeURL)
			throw InstallError.permissionProblem
		}
		
		try FileManager.default.removeItem(at:writeURL)
		
		dprint(Colors.Green("[OK]\t\(consumingUser) is now allowed to install SSL certs for \(domain) to \(destURL.path)"))
	}

	//MARK: SUDO
	private class func validateSudoPermissions(domain:String, forConsumptionIn directory:URL) -> Bool {
		let certbot = URL(fileURLWithPath:run(bash:"which certbot").stdout)
		let cp = URL(fileURLWithPath:run(bash:"which cp").stdout)
		let chown = URL(fileURLWithPath:run(bash:"which chown").stdout)
		let allowedList = run(bash:"sudo -l").stdout.split(separator:"\n").map { return String($0) }
		
		var certbotPassed = false	
		var owns = 0
		var cps = 0
		for (_, curListItem) in allowedList.enumerated() {
			if (curListItem =~ "NOPASSWD: \(certbot.path) certonly --webroot -n -v -d \(domain) -w *") {
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
	private class func validateSudo(password:String?, logoutAfterTest:Bool = true, context:CustomContext = CustomContext(main)) -> Bool {
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