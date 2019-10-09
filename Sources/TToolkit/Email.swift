import Foundation
import SwiftSMTP
import SwiftSoup

public struct RenderedTemplate {
    let html:String
    let attachments:[Attachment]
}

//extension for Mail.User for codability support
extension Mail.User: Codable {
    public enum CodingKeys: String, CodingKey {
        case name = "name"
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

public typealias HTMLRenderer = (Document) throws -> String

public struct Emailer {
    //subjects sent by Emailer always contain the following subject:
    //[EVENT] - Context
    public var context: String = "Emailer"
    public var longContext: String = "Swift emailer from TToolkit"
    
    public enum EmailError: Error {
        case invalidConfigData
        case unableToSend
        case unableToWrite
        case templateConfigWritten
        case noRecipientsFound
        case unableToReadTemplateData
    }
    
    public enum CodingKeys: String, CodingKey {
        case host = "host"
        case email = "email"
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
        let templateConfigObject = [    CodingKeys.host.stringValue: "smtp.office365.com",
                                        CodingKeys.email.stringValue: "bot@domain.com",
                                        CodingKeys.pw.stringValue: "put bots password here",
                                        CodingKeys.name.stringValue: "Botty the Bot",
                                        CodingKeys.admin.stringValue: ["name": "Human Admin", "email": "admin@domain.com"]
            ] as [String:Any]
        
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: nil)
        let data = try JSONSerialization.data(withJSONObject:templateConfigObject, options:[.prettyPrinted])
        if FileManager.default.fileExists(atPath: configURL.path) == false {
            try data.write(to:configURL)
            print(Colors.Green("Successfully write default Emailer configuration to \(configURL.path)" ))
            print(Colors.bold(Colors.Yellow("PLEASE EDIT THIS FILE WITH THE APROPRIATE EMAIL INFORMATION")))
        } else {
            print(Colors.yellow("Did not write template email configuration...there is already a configuration file."))
        }
        
    }
    
    public init() throws {
        var configurationObject:[String:Any]
        do {
            let fileData = try Data(contentsOf:configURL)
            guard let configObjTest = try JSONSerialization.jsonObject(with:fileData) as? [String:Any] else {
                throw EmailError.invalidConfigData
            }
            configurationObject = configObjTest
        } catch let error {
            switch error {
            case EmailError.invalidConfigData:
                throw error
            default:
                try Emailer.installConfiguration()
                throw EmailError.templateConfigWritten
            }
        }
        
        
        //validate all the shit exists on disk
        guard let hostTest = configurationObject[CodingKeys.host.stringValue] as? String else {
            print(Colors.Red("[EMAILER]\tError initializing...there was no host coding key found"))
            throw EmailError.invalidConfigData
        }
        
        guard let emailTest = configurationObject[CodingKeys.email.stringValue] as? String else {
            print(Colors.Red("[EMAILER]\tError initializing...there was no email coding key found"))
            throw EmailError.invalidConfigData
        }
        
        guard let pwTest = configurationObject[CodingKeys.pw.stringValue] as? String else {
            print(Colors.Red("[EMAILER]\tError initializing...there was no password coding key found"))
            throw EmailError.invalidConfigData
        }
        
        guard let nameTest = configurationObject[CodingKeys.name.stringValue] as? String else {
            print(Colors.Red("[EMAILER]\tError initializing...there was no name coding key found"))
            throw EmailError.invalidConfigData
        }
        
        guard let adminObjectTest = configurationObject[CodingKeys.admin.stringValue] as? [String:String] else {
            print(Colors.Red("[EMAILER]\tError initializing...there was no admin coding key found"))
            throw EmailError.invalidConfigData
        }
        
        guard let adminName = adminObjectTest["name"] else {
            print(Colors.Red("[EMAILER]\tError initializing...there was no admin name coding key found"))
            throw EmailError.invalidConfigData
        }
        
        guard let adminEmail = adminObjectTest["email"] else {
            print(Colors.Red("[EMAILER]\tError initializing...there was no admin email coding key found"))
            throw EmailError.invalidConfigData
        }
        
        host = hostTest
        email = emailTest
        pw = pwTest
        name = nameTest
        
        smtp = SMTP(hostname:hostTest, email:emailTest, password:pwTest)
        me = Mail.User(name:nameTest, email:emailTest)
        admin = Mail.User(name:adminName, email:adminEmail)
    }
    
    private func loadRecipients(named groupName:String, includeAdmin:Bool) throws -> [Mail.User] {
        if groupName == "" && includeAdmin == true {
            return [admin]
        }
        let decoder = JSONDecoder()
        let groupDataURL = baseURL.appendingPathComponent(groupName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: groupDataURL.path) == true else {
            throw EmailError.noRecipientsFound
        }
        
        let groupData = try Data(contentsOf:groupDataURL)
        var users = try decoder.decode([Mail.User].self, from: groupData)
        if (includeAdmin) {
            users.append(admin)
        }
        return users
    }
    
    public func subjectLine(for event:String) -> String {
        return "[" + event.uppercased() + "]" + " - " + context
    }
    
    public func loadTemplate(named:String, renderer:HTMLRenderer) throws -> RenderedTemplate {
        let fileName = named + ".html"
        let html = try Data(contentsOf:baseURL.appendingPathComponent(fileName, isDirectory:false))
        guard let dataString = String(data:html, encoding:.utf8) else {
            throw EmailError.invalidConfigData
        }
        let htmlDocument = try SwiftSoup.parse(dataString)
        let manipulatedHTML = try renderer(htmlDocument)
        let enumeratePath = baseURL.appendingPathComponent(named, isDirectory: true)
        var attachmentsToBuild = [Attachment]()
        for (_, curFile) in try FileManager.default.contentsOfDirectory(atPath: enumeratePath.path).enumerated() {
            do {
                let thisFile = enumeratePath.appendingPathComponent(curFile, isDirectory: false)
                let thisFileData = try Data(contentsOf:thisFile)
                let thisAttachment = Attachment(data:thisFileData, mime:thisFile.mimeType(), name:thisFile.lastPathComponent, inline:true)
                attachmentsToBuild.append(thisAttachment)
            } catch _ {}
        }
        return RenderedTemplate(html:manipulatedHTML, attachments:attachmentsToBuild)
    }
    
    public func sendTemplate(_ renderedTemplate:RenderedTemplate, with thisSubject:String, to recipients:[Mail.User]) throws {
        //make the main html attachment
        let html = Attachment(htmlContent: renderedTemplate.html, relatedAttachments: renderedTemplate.attachments)
        let mail = Mail(from:me, to:recipients, subject:thisSubject, attachments:[html])
    }
    
    private func send(mail:Mail) throws {
        var waitGroup = DispatchGroup()
        waitGroup.enter()
        var sendError:Error? = nil
        smtp.send(mail) { error in
            if (error != nil) {
                sendError = error
                print(Colors.Red("Error sending email to \(mail.to.count) recipients: \(String(describing:error))"))
            } else {
                dprint(Colors.Green("Email sent."))
            }
            waitGroup.leave()
        }
        waitGroup.wait()
        if let hadError = sendError {
            throw hadError
        }
    }
    
    
    public func notify(recipients groupName:String, of event:String, data:[String:String], notifyAdmin:Bool = false, attachments:[Attachment] = [], subject:String? = nil) throws {
        let usersToNotify = try loadRecipients(named: groupName, includeAdmin: notifyAdmin)
        try notify(recipients: usersToNotify, of: event, data: data, attachments: attachments, subject:subject)
    }
    
    public func notify(recipients usersToNotify:[Mail.User], of event:String, data:[String:String], attachments:[Attachment] = [], subject:String? = nil) throws {
        let subjectToSend = subject ?? subjectLine(for: event)
        
        var bodyString = "==============================\n"
        bodyString += "\(event.uppercased()) @ \(longContext)\n"
        bodyString += "UTC :: \(Date())\n"
        bodyString += "==============================\n\n"
        for (_, curPair) in data.enumerated() {
            bodyString += curPair.key.lowercased()
            bodyString += "\t-> \""
            bodyString += curPair.value
            bodyString += "\"\n"
        }
        
        let mail = Mail(from:me, to:usersToNotify, subject:subjectToSend, text:bodyString, attachments: attachments)
        
        try send(mail:mail)
    }
    
    public func sendTest() throws {
        try notify(recipients: [admin], of: "Test", data: [:])
    }
}
