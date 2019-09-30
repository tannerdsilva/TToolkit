import Foundation
import SwiftSMTP

//extension for Mail.User for codability support
extension Mail.User: Codable {
	public enum CodingKeys: String, CodingKey {
		case name = "host"
		case email = "email"
	}
	public init(from decoder:Decoder) throws {
		let values = try decoder.container(keyedBy:CodingKeys.self)
		let name = try values.decode(String.self, forKey:.name)
		let email = try values.decode(String.self, forKey:.email)
		self.init(name:name, email:email)
	}
	public func encode(to encoder:Encoder) throws {
		var container = encoder.container(keyedBy:CodingKeys.self)
		try container.encode(self.name, forKey:.name)
		try container.encode(self.email, forKey:.email)
	}
}

//URLs for for documenting the state of the emailer on disk
fileprivate let baseURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".emailer", isDirectory:true)
fileprivate let configURL = baseURL.appendingPathComponent("config.json", isDirectory:false)
fileprivate let notifyURL = baseURL.appendingPathComponent("notify.json", isDirectory:false)
fileprivate let failedDirURL = baseURL.appendingPathComponent("failed", isDirectory:false)

public struct Emailer {
	public enum EmailError: Error {
		case invalidConfigData
		case unableToSend
		case unableToWrite
	}
	
	public enum CodingKeys: String, CodingKey {
		case host = "host"
		case email = "email"
		case password = "password"
		case name = "name"
		case admin = "admin"
		case pw = "pw"
	}

		
	public let sem = DispatchSemaphore(value:1)
	public let host:String
	public let email:String
	private let pw:String
	public let name:String
	
	public let smtp:SMTP
	public let me:Mail.User
	public let admin:Mail.User
		
	public static func installConfiguration() throws {
		//this template data...
		let templateConfigObject = [	CodingKeys.host: "smtp.office365.com",
										CodingKeys.email: "bot@emailDomain.com",
										CodingKeys.pw: "put your password here",
										CodingKeys.name: "Botty the Bot",
										CodingKeys.admin: ["name": "Human Admin", "email": "human@emailDomain.com"]
		] as [CodingKeys:Any]
		
		//...gets written to the configURL
		let data = try JSONSerialization.data(withJSONObject:templateConfigObject)
		try data.write(to:configURL)
		print(Colors.Green("Successfully write default Emailer configuration to \(configURL.path)" ))
		print(Colors.bold(Colors.Yellow("PLEASE EDIT THIS FILE WITH THE APROPRIATE EMAIL INFORMATION")))
	}
	
	public init(with configuration:URL) throws {
		let fileData = try Data(contentsOf:configURL)
		
		guard let configurationObject = try JSONSerialization.jsonObject(with:fileData) as? [String:Any] else {
			throw EmailError.invalidConfigData
		}
		
		let decoder = JSONDecoder()
		guard	let hostTest = configurationObject[CodingKeys.host.rawValue] as? String,
				let emailTest = configurationObject[CodingKeys.email.rawValue] as? String,
				let pwTest = configurationObject[CodingKeys.password.rawValue] as? String,
				let nameTest = configurationObject[CodingKeys.name.rawValue] as? String,
				let adminStringTest = configurationObject[CodingKeys.admin.rawValue] as? String,
				let adminDataTest = adminStringTest.data(using:.utf8),
				let parsedAdminTest = try? decoder.decode(Mail.User.self, from:adminDataTest) else {
			throw EmailError.invalidConfigData		
		}
		
		host = hostTest
		email = emailTest
		pw = pwTest
		name = nameTest
		
		smtp = SMTP(hostname:hostTest, email:emailTest, password:pwTest)
		me = Mail.User(name:nameTest, email:emailTest)
		admin = parsedAdminTest
	}
}

//public struct Emailer: Codable {
//	public enum EmailError: Error {
//		case invalidConfigData
//		case unableToSend
//	}
//	
//	public enum CodingKeys: CodingKey {
//		var stringValue: String {
//			switch self {
//				case .host:
//					return "smtpHost"
//				case .email:
//					return "email"
//				case .password:
//					return "password"
//				case .serviceName:
//					return "serviceName"
//				case .admin:
//					return "adminEmail"
//				case .notify:
//					return "notifyEmails"
//			}
//		}
//		case host
//		case email
//		case password
//		case serviceName
//		case admin
//		case notify
//	}
//	
//	var sem = DispatchSemaphore(value:1)
//	
//	var host:String
//	var email:String
//	private var pw:String
//	var name:String
//
//	var smtp:SMTP
//	var me:Mail.User
//	var admin:Mail.User
//	var notify:[Mail.User]
//	
//	private static func writeTemplate(to thisFile:URL) throws {
//		var encoder = JSONEncoder()
//		var container = encoder.container(keyedBy:CodingKeys.self)
//		try container.encode("smtp.office365.com", forKey:.host)
//		try container.encode("bot@escalantegolf.com", forKey:.email)
//		try container.encode("here", forKey:.password)
//		try container.encode("someDaemon", forKey:.serviceName)
//		try container.encode(["name": "goes here", "email": "email@somedomain.com"], forKey:.admin)
//		try container.encode([], forKey:.notify)
//	}
//		
//	static func templateConfiguration() -> Emailer {
//		return self.init()
//	}
//	
//	fileprivate init() {
//		host = "smtp.office365.com"
//		email = "bot@escalantegolf.com"
//		pw = "here"
//		smtp = SMTP(hostname:host, email:email, password:pw)
//		name = "someDaemon"
//		me = Mail.User(name:name, email:email)
//		admin = Mail.User(name:"goes here", email:"email@somedomain.com")
//		notify = [Mail.User]()
//	}
//	
//	init(from configuration:URL) throws {
//		let readData = try Data(contentsOf:configuration)
//		let decoder = JSONDecoder()
//		self = try decoder.decode(Emailer.self, from:readData)
//	}
//	
//	init(from decoder:Decoder) throws {
//		let values = try decoder.container(keyedBy:CodingKeys.self)
//		host = try values.decode(String.self, forKey:.host)
//		email = try values.decode(String.self, forKey:.email)
//		pw = try values.decode(String.self, forKey:.password)
//		smtp = SMTP(hostname:host, email:email, password:pw)
//		name = try values.decode(String.self, forKey:.serviceName)
//		me = Mail.User(name:name, email:email)
//		admin = try values.decode(Mail.User.self, forKey:.admin)
//		notify = try values.decode([Mail.User].self, forKey:.nofify)
//	}
//	func encode(to encoder:Encoder) throws {
//		var container = encoder.container(keyedBy:CodingKeys.self)
//		try container.encode(host, forKey:.host)
//		try container.encode(email, forKey:.email)
//		try container.encode(pw, forKey:.password)
//		try container.encode(name, forKey:.serviceName)
//		try container.encode(admin, forKey:.admin)
//		try container.encode(notify, forKey:.notify)
//	}
//	static func writeTemplateConfig(to thisFile:URL) throws {
//		let baseObject = [	"host": "smtp.office365.com",
//							"email": "bot@somedomain.com",
//							"password": "here",
//							"admin": [ "name": "keanu reeves",
//										"email": "human@somedomain.com" ]
//							]
//							
//		let jsonData = try JSONSerialization.data(withJSONObject:baseObject, options:[.prettyPrinted])
//		try jsonData.write(to: thisFile)
//	}
//	
//	init(name:String, configURL:URL) throws {
//		dprint(Colors.Yellow("[SMTP]\tInitializing SMTP sender with data from \(configURL.path)"))
//		guard let configData = try? Data(contentsOf:configURL) else {
//			print(Colors.Red("[SMTP][ERROR]Could not read contents of \(configURL.path)"))
//			try Emailer.writeTemplateConfig(to:configURL)
//			print(Colors.bold(Colors.Green("A TEMPLATE CONFIGURATION FILE HAS BEEN WRITTEN")))
//			throw EmailError.invalidConfigData
//		}
//		let decoder = JSONDecoder()
//		let product = try decoder.decode([Mail.User].self, from:configData)
//		guard let configObject = try? JSONSerialization.jsonObject(with:configData) as? [String:String] else {
//			print(Colors.Red("Invalid SMTP data found in the emailer configuration file"))
//			throw EmailError.invalidConfigData
//		}
//		guard	let hostString = configObject["host"] as? String,
//				let emailString = configObject["email"] as? String,
//				let pw = configObject["password"] as? String,
//				let adminObject = configObject["admin"] as? [String:String],
//				let adminName = adminObject["name"] as? String,
//				let adminEmail = adminObject["email"] as? String else {
//			print(Colors.Red("Invalid SMTP data found in the emailer configuration file"))
//			throw EmailError.invalidConfigData		
//		}
//		smtp = SMTP(hostname:hostString, email:emailString, password:pw)
//		me = Mail.User(name:name, email:emailString)
//		admin = Mail.User(name:adminName, email:adminEmail)
//	}
//	
//	func notifyAdmin(subject:String, body:String) {
//		let waitGroup = DispatchGroup()
//		waitGroup.enter()
//	}
//}