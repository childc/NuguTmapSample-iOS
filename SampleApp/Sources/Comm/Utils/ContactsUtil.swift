//
//  ContactsUtil.swift
//  SampleApp
//
//  Created by childc on 2021/02/26.
//  Copyright © 2021 sktelecom. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import Contacts
import os.log

import NuguCore
import NuguAgents

import RxSwift

public enum ContactMatchType: Int32 {
    case exact
    case partial
}

public class ContactsUtil {
    public static let shared = ContactsUtil()
    private static let maxRecipientCount = 70
    static fileprivate let pattern = "[^\u{AC00}-\u{D7A3}\\p{Digit}\\p{Alpha}]+"
    
    let contactStore = CNContactStore()
    private let contactsQueue: DispatchQueue = DispatchQueue(label: "ContactsUtilQueue")
    private var contactsWorkItem: DispatchWorkItem?
    private var contacts: [CNContact]?
    private var notificationObserver: NSObjectProtocol?
    private let disposeBag = DisposeBag()
    
    private init() {
        refreshLocalContacts()
        addContactsObserver()
    }
    
    deinit {
        removeContactObserver()
    }
    
    private func isGranted() -> Bool {
        let authorizationStatus = CNContactStore.authorizationStatus(for: CNEntityType.contacts)
        return authorizationStatus == .authorized
    }
    
    public func refreshLocalContacts() {
        contactsQueue.async { [unowned self] in
            self.contacts = getAllContacts()
        }
    }
    
    public func getLocalContact(complete: @escaping ([CNContact]?) -> Void) {
        contactsQueue.async { [unowned self] in
            complete(self.contacts)
        }
    }
    
    private func getAllContacts() -> [CNContact] {
        var contacts = [CNContact]()
        let keys = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName), CNContactPhoneNumbersKey as CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        
        do {
            try contactStore.enumerateContacts(with: request) { (contact, _) in
                // 전화번호가 있는 연락처만 가져온다.
                if 0 < contact.phoneNumbers.count {
                    contacts.append(contact)
                }
            }
        } catch {
            os_log("unable to fetch contacts in sendContactsToServer")
        }
        
        contacts.sort { (contact1, contact2) -> Bool in
            let fullName1 = contact1.familyName + contact1.givenName
            let fullName2 = contact2.familyName + contact2.givenName
            return fullName1.count < fullName2.count
        }
        
        return contacts
    }
}

// MARK: - Search
public extension ContactsUtil {
    enum SearchScene: String {
        case `default` = "DEFAULT"
        case t114Direct = "T114DIRECT"
        case t114Only = "T114ONLY"
        case t114Include = "T114INCLUDE"
    }
    
    func search(names: [String], label: String? = nil, type: ContactMatchType, complete: @escaping (ContactMatchType, [CNContact]) -> Void) {
        searchByNames(names, type: type) { (type, contactList) in
            var filteredContactList = [CNContact]()
            
            if let label = label {
                // 번호속성이 정의되어 있을 때
                contactList.forEach { (contact) in
                    let phoneNumbers = contact.phoneNumbers.filter { $0.label == label }
                    if 0 < phoneNumbers.count, let filteredContact = contact.mutableCopy() as? CNMutableContact {
                        filteredContact.phoneNumbers = phoneNumbers
                        filteredContactList.append(filteredContact)
                    }
                }
            } else {
                contactList.forEach { (contact) in
                    // 번호속성이 정의되어있지 않은 경우 01x로 시작하는 번호를 탐색
                    let phoneNumbers = contact.phoneNumbers.filter { $0.value.stringValue.starts(with: "01") }
                    guard 0 < phoneNumbers.count else {
                        // 결과가 없다면 그대로 전달한다.
                        filteredContactList.append(contact)
                        return
                    }

                    // 결과가 있다면 해당 결과만 선택
                    if let filteredContact = contact.mutableCopy() as? CNMutableContact {
                        filteredContact.phoneNumbers = phoneNumbers
                        filteredContactList.append(filteredContact)
                    }
                }
            }
            
            let limitedContactsList = filteredContactList[0..<min(ContactsUtil.maxRecipientCount, filteredContactList.count)]
            complete(type, Array(limitedContactsList))
        }
    }
    
    private func searchByNames(_ names: [String], type: ContactMatchType, complete: @escaping (ContactMatchType, [CNContact]) -> Void) {
        contactsQueue.async { [unowned self] in
            guard let contacts = self.contacts else {
                complete(type, [CNContact]())
                return
            }
            
            var exactlyMatchedContacts = [CNContact]()
            names.forEach { (name) in
                // exactly match logic
                let matchedList = contacts.filter { $0.fullName.supportedContactString == name.supportedContactString }
                exactlyMatchedContacts.append(contentsOf: matchedList)
            }
            if 0 < exactlyMatchedContacts.count || type == .exact {
                complete(.exact, exactlyMatchedContacts)
                return
            }
            
            var partialyMatchedContacts = [CNContact]()
            names.forEach { (name) in
                // partialy match logic
                let matchedList = contacts.filter {
                    $0.fullName.supportedContactString.contains(name.supportedContactString) || name.supportedContactString.contains($0.fullName.supportedContactString)
                }
                partialyMatchedContacts.append(contentsOf: matchedList)
            }
            
            // 모두 가져와서 정렬해야한다. (abc0000~abc5000까지 있는 경우 정렬해서 abc0000~abc0070을 보여줘야 한다는 정책 때문.
            partialyMatchedContacts.sort { (contact1, contact2) -> Bool in
                if contact1.fullName.count != contact2.fullName.count {
                    let rate1 = max(Double(names[0].count)/Double(contact1.fullName.count), Double(contact1.fullName.count)/Double(names[0].count))
                    let rate2 = max(Double(names[0].count)/Double(contact2.fullName.count), Double(contact2.fullName.count)/Double(names[0].count))
                    return rate1 < rate2
                }
                
                return contact1.fullName < contact2.fullName
            }
            
            complete(.partial, partialyMatchedContacts)
        }
    }
}

// MARK: - Observer

private extension ContactsUtil {
    func addContactsObserver() {
        removeContactObserver()
        
        notificationObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.CNContactStoreDidChange, object: nil, queue: nil) { [unowned self] _ in
            self.refreshLocalContacts()
            
            // TODO: send to server
        }
    }
    
    func removeContactObserver() {
        if let notificationObserver = notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
            self.notificationObserver = nil
        }
    }
}

// MARK: - Contacts

extension CNContact {
    func makeToken(with phoneNumber: CNPhoneNumber) -> String {
        String("name: \(fullName), phoneNumber: \(phoneNumber.stringValue.supportedContactString)".hash)
    }
    
    var fullName: String {
        return familyName + givenName
    }
}

extension String {
    var supportedContactString: String {
        return replacingOccurrences(of: ContactsUtil.pattern, with: "", options: [.regularExpression])
    }
}
