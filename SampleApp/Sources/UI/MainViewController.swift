//
//  MainViewController.swift
//  SampleApp
//
//  Created by jin kim on 17/06/2019.
//  Copyright (c) 2019 SK Telecom Co., Ltd. All rights reserved.
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

import UIKit
import MediaPlayer
import Contacts
import MessageUI

import NuguCore
import NuguAgents
import NuguUtils
import NuguClientKit
import NuguUIKit

final class MainViewController: UIViewController {
    // MARK: Properties
    
    @IBOutlet private weak var nuguButton: NuguButton!
    @IBOutlet private weak var settingButton: UIButton!
    
    private lazy var voiceChromePresenter = VoiceChromePresenter(
        viewController: self,
        nuguClient: NuguCentralManager.shared.client
    )
    private lazy var displayWebViewPresenter = DisplayWebViewPresenter(
        viewController: self,
        nuguClient: NuguCentralManager.shared.client,
        clientInfo: ["buttonColor": "white"]
    )
    private lazy var audioDisplayViewPresenter = AudioDisplayViewPresenter(
        viewController: self,
        nuguClient: NuguCentralManager.shared.client
    )
    
    // MARK: Observers

    private let notificationCenter = NotificationCenter.default
    private var resignActiveObserver: Any?
    private var becomeActiveObserver: Any?
    private var asrResultObserver: Any?
    private var dialogStateObserver: Any?
    
    // Dummy
    private let tmap = NuguTmapDummy(contextManager: NuguCentralManager.shared.client.contextManager)
    
    // MARK: Override
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        initializeNugu()
        registerObservers()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        refreshNugu()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        showGuideWebIfNeeded()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        NuguCentralManager.shared.stopListening()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        
        guard let segueId = segue.identifier else {
            log.debug("segue identifier is nil")
            return
        }
        
        switch segueId {
        case "mainToGuideWeb":
            guard let webViewController = segue.destination as? WebViewController else { return }
            webViewController.initialURL = sender as? URL
            
            UserDefaults.Standard.hasSeenGuideWeb = true
        default:
            return
        }
    }
    
    // MARK: Deinitialize
    
    deinit {
        removeObservers()
        if let asrResultObserver = asrResultObserver {
            notificationCenter.removeObserver(asrResultObserver)
        }
        
        if let dialogStateObserver = dialogStateObserver {
            notificationCenter.removeObserver(dialogStateObserver)
        }
    }
}

// MARK: - private (Observer)

private extension MainViewController {
    func registerObservers() {
        // To avoid duplicated observing
        removeObservers()
        
        /**
         Catch resigning active notification to stop recognizing & wake up detector
         It is possible to keep on listening even on background, but need careful attention for battery issues, audio interruptions and so on
         */
        resignActiveObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main, using: { (_) in
            // if tts is playing for multiturn, tts and associated jobs should be stopped when resign active
            if NuguCentralManager.shared.client.dialogStateAggregator.isMultiturn == true {
                NuguCentralManager.shared.client.ttsAgent.stopTTS()
            }
            NuguCentralManager.shared.stopListening()
        })
        
        /**
         Catch becoming active notification to refresh mic status & Nugu button
         Recover all status for any issues caused from becoming background
         */
        becomeActiveObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: { [weak self] (_) in
            guard let self = self else { return }
            guard self.navigationController?.visibleViewController == self else { return }

            self.refreshNugu()
        })
    }
    
    func removeObservers() {
        if let resignActiveObserver = resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
            self.resignActiveObserver = nil
        }

        if let becomeActiveObserver = becomeActiveObserver {
            NotificationCenter.default.removeObserver(becomeActiveObserver)
            self.becomeActiveObserver = nil
        }
    }
}

// MARK: - Private (IBAction)

private extension MainViewController {
    @IBAction func showSettingsButtonDidClick(_ button: UIButton) {
        NuguCentralManager.shared.stopListening()

        performSegue(withIdentifier: "showSettings", sender: nil)
    }
    
    @IBAction func startRecognizeButtonDidClick(_ button: UIButton) {
        presentVoiceChrome(initiator: .user)
    }
}

// MARK: - Private (Nugu)

private extension MainViewController {
    /// Initialize to start using Nugu
    /// AudioSession is required for using Nugu
    /// Add delegates for all the components that provided by default client or custom provided ones
    func initializeNugu() {
        // UI
        voiceChromePresenter.delegate = self
        displayWebViewPresenter.delegate = self
        audioDisplayViewPresenter.delegate = self
        
        // keyword detector delegate
        NuguCentralManager.shared.client.keywordDetector.delegate = self
        
        // Phone Call & Message
        NuguCentralManager.shared.client.phoneCallAgent.delegate = self
        NuguCentralManager.shared.client.messageAgent.delegate = self
        NuguCentralManager.shared.client.locationAgent.delegate = self
        
        // Observers
        addAsrAgentObserver(NuguCentralManager.shared.client.asrAgent)
        addDialogStateObserver(NuguCentralManager.shared.client.dialogStateAggregator)
    }
    
    /// Show nugu usage guide webpage after successful login process
    func showGuideWebIfNeeded() {
        guard UserDefaults.Standard.hasSeenGuideWeb == false else { return }
        
        ConfigurationStore.shared.usageGuideUrl(deviceUniqueId: NuguCentralManager.shared.oauthClient.deviceUniqueId) { [weak self] (result) in
            switch result {
            case .success(let urlString):
                if let url = URL(string: urlString) {
                    self?.performSegue(withIdentifier: "mainToGuideWeb", sender: url)
                }
            case .failure(let error):
                log.error(error)
            }
        }
    }
    
    /// Refresh Nugu status
    /// Connect or disconnect Nugu service by circumstance
    /// Hide Nugu button when Nugu service is intended not to use or network issue has occured
    /// Disable Nugu button when wake up feature is intended not to use
    func refreshNugu() {
        guard UserDefaults.Standard.useNuguService else {
            // Exception handling when already disconnected, scheduled update in future
            nuguButton.isEnabled = false
            nuguButton.isHidden = true
            
            // Disable Nugu SDK
            NuguCentralManager.shared.disable()
            return
        }
        
        // Exception handling when already connected, scheduled update in future
        nuguButton.isEnabled = true
        nuguButton.isHidden = false
        
        // Enable Nugu SDK
        NuguCentralManager.shared.enable()
    }
}

// MARK: - Private (Voice Chrome)

private extension MainViewController {
    func presentVoiceChrome(initiator: ASRInitiator) {
        do {
            try voiceChromePresenter.presentVoiceChrome(chipsData: [
                NuguChipsButton.NuguChipsButtonType.normal(text: "오늘 몇일이야", token: nil)
            ])
            NuguCentralManager.shared.startListening(initiator: initiator)
        } catch {
            switch error {
            case VoiceChromePresenterError.networkUnreachable:
                NuguCentralManager.shared.localTTSAgent.playLocalTTS(type: .deviceGatewayNetworkError)
            default:
                log.error(error)
            }
        }
    }
}

// MARK: - Private (Chips Selection)

private extension MainViewController {
    func chipsDidSelect(selectedChips: NuguChipsButton.NuguChipsButtonType?) {
        guard let selectedChips = selectedChips,
            let window = UIApplication.shared.keyWindow else { return }
        
        let indicator = UIActivityIndicatorView(style: .whiteLarge)
        indicator.color = .black
        indicator.startAnimating()
        indicator.center = window.center
        indicator.startAnimating()
        window.addSubview(indicator)
        
        NuguCentralManager.shared.requestTextInput(text: selectedChips.text, token: selectedChips.token, requestType: .dialog) {
            DispatchQueue.main.async {
                indicator.removeFromSuperview()
            }
        }
    }
}

// MARK: - DisplayWebViewPresenterDelegate

extension MainViewController: DisplayWebViewPresenterDelegate {    
    func onDisplayWebViewNuguButtonClick() {
        presentVoiceChrome(initiator: .user)
    }
}

// MARK: - AudioDisplayViewPresenterDelegate

extension MainViewController: AudioDisplayViewPresenterDelegate {
    func displayControllerShouldUpdateTemplate(template: AudioPlayerDisplayTemplate) {
        NuguCentralManager.shared.displayPlayerController.update(template)
    }
    
    func displayControllerShouldUpdateState(state: AudioPlayerState) {
        NuguCentralManager.shared.displayPlayerController.update(state)
    }
    
    func displayControllerShouldUpdateDuration(duration: Int) {
        NuguCentralManager.shared.displayPlayerController.update(duration)
    }
    
    func displayControllerShouldRemove() {
        NuguCentralManager.shared.displayPlayerController.remove()
    }
    
    func onAudioDisplayViewNuguButtonClick() {
        presentVoiceChrome(initiator: .user)
    }
    
    func onAudioDisplayViewChipsSelect(selectedChips: NuguChipsButton.NuguChipsButtonType?) {
        chipsDidSelect(selectedChips: selectedChips)
    }
}

// MARK: - KeywordDetectorDelegate

extension MainViewController: KeywordDetectorDelegate {
    func keywordDetectorDidDetect(keyword: String?, data: Data, start: Int, end: Int, detection: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.presentVoiceChrome(initiator: .wakeUpKeyword(
                keyword: keyword,
                data: data,
                start: start,
                end: end,
                detection: detection
                )
            )
        }
    }
    
    func keywordDetectorDidStop() {}
    
    func keywordDetectorStateDidChange(_ state: KeywordDetectorState) {
        switch state {
        case .active:
            DispatchQueue.main.async { [weak self] in
                self?.nuguButton.startFlipAnimation()
            }
        case .inactive:
            DispatchQueue.main.async { [weak self] in
                self?.nuguButton.stopFlipAnimation()
            }
        }
    }
    
    func keywordDetectorDidError(_ error: Error) {}
}

// MARK: - VoiceChromePresenterDelegate

extension MainViewController: VoiceChromePresenterDelegate {
    func voiceChromeWillShow() {
        nuguButton.isActivated = false
    }
    
    func voiceChromeWillHide() {
        nuguButton.isActivated = true
    }
    
    func voiceChromeChipsDidClick(chips: NuguChipsButton.NuguChipsButtonType) {
        chipsDidSelect(selectedChips: chips)
    }
}

// MARK: - Observers

private extension MainViewController {
    func addAsrAgentObserver(_ object: ASRAgentProtocol) {
        asrResultObserver = object.observe(NuguAgentNotification.ASR.Result.self, queue: .main) { (notification) in
            switch notification.result {
            case .complete:
                DispatchQueue.main.async {
                    NuguCentralManager.shared.asrBeepPlayer.beep(type: .success)
                }
            case .error(let error, _):
                DispatchQueue.main.async {
                    switch error {
                    case ASRError.listenFailed:
                        NuguCentralManager.shared.asrBeepPlayer.beep(type: .fail)
                    case ASRError.recognizeFailed:
                        NuguCentralManager.shared.localTTSAgent.playLocalTTS(type: .deviceGatewayRequestUnacceptable)
                    default:
                        NuguCentralManager.shared.asrBeepPlayer.beep(type: .fail)
                    }
                }
            default: break
            }
        }
    }
    
    func addDialogStateObserver(_ object: DialogStateAggregator) {
        dialogStateObserver = object.observe(NuguClientNotification.DialogState.State.self, queue: nil) { [weak self] (notification) in
            log.debug("dialog satate: \(notification.state), multiTurn: \(notification.multiTurn), chips: \(notification.chips.debugDescription)")

            switch notification.state {
            case .listening:
                DispatchQueue.main.async {
                    NuguCentralManager.shared.asrBeepPlayer.beep(type: .start)
                }
            case .thinking:
                DispatchQueue.main.async { [weak self] in
                    self?.nuguButton.pauseDeactivateAnimation()
                }
            default:
                break
            }
        }
    }
}

// MARK: - Phone Call

extension MainViewController: PhoneCallAgentDelegate {
    private class PhoneCallManager {
        static let shared = PhoneCallManager()
        @Atomic var context = PhoneCallContext(state: .idle, template: nil, recipient: nil)
        @Atomic var currentContacts = [String: String]()
        @Atomic var templatId = ""
    }
    
    public func phoneCallAgentRequestContext() -> PhoneCallContext {
        return PhoneCallManager.shared.context
    }
    
    public func phoneCallAgentDidReceiveSendCandidates(item: PhoneCallCandidatesItem, header: Downstream.Header) {
        log.debug("phoneCallAgentDidReceiveSendCandidates \(item)")
        guard item.intent == .call else { return }
        
        var names = [String]()
        var searchType: ContactMatchType = .exact
        if let serverContacts = item.candidates?.filter({ $0.type != .t114 }),
           0 < serverContacts.count {
            // search exact match
            searchType = .exact
            names.append(contentsOf: serverContacts.map { (person) -> String in
                return person.name
            })
        } else if let intendedName = item.recipientIntended?.name {
            // search partial match
            searchType = .partial
            names.append(intendedName)
        }
        
        ContactsUtil.shared.search(names: names, label: item.recipientIntended?.label, type: searchType) { (type, contactList) in
            var personList = [PhoneCallPerson]()
            contactList.forEach { (contact) in
                contact.phoneNumbers.forEach { (phoneNumber) in
                    // PhoneNumber를 서버로 전송할 수 없고(개인정보이슈), Person별로 token을 가지고 있으므로 같은 사람의 여러 연락처를 쪼갠다.
                    let token = contact.makeToken(with: phoneNumber.value)
                    PhoneCallManager.shared.currentContacts[token] = phoneNumber.value.stringValue.supportedContactString
                    
                    let phoneCallPerson = PhoneCallPerson(
                        name: contact.fullName,
                        type: .contact,
                        profileImgUrl: nil,
                        category: nil,
                        address: nil,
                        businessHours: nil,
                        history: nil,
                        numInCallHistory: nil,
                        token: token,
                        score: nil,
                        contacts: [
                            PhoneCallPerson.Contact(
                                label: item.recipientIntended?.label == nil ? nil :  PhoneCallPerson.Contact.Label(rawValue: item.recipientIntended!.label!),
                                number: nil
                            )
                        ]
                    )
                    personList.append(phoneCallPerson)
                }
            }
            
            if personList.count == 0,
               let t114List = item.candidates?.filter({ $0.type == .t114 }) {
                // 로컬 검색 결과가 없으면 T114정보를 보낸다.
                personList.append(contentsOf: t114List)
            }
            
            let template = PhoneCallContext.Template(intent: item.intent, callType: item.callType, recipientIntended: item.recipientIntended, candidates: personList, searchScene: item.searchScene)
            let context = PhoneCallContext(state: .idle, template: template, recipient: nil)
            PhoneCallManager.shared.context = context
            
            NuguCentralManager.shared.client.phoneCallAgent.requestSendCandidates(candidatesItem: item, header: header) { (state) in
                log.debug("requestSendCandidates state: \(state)")
            }
        }
    }
    
    public func phoneCallAgentDidReceiveMakeCall(callType: PhoneCallType, recipient: PhoneCallPerson, header: Downstream.Header) -> PhoneCallErrorCode? {
        guard .callar != callType else { return .callTypeNotSupported }
        guard let phoneNumber: String = {
            guard recipient.type != .t114 else {
                return recipient.contacts?.first?.number
            }
            
            guard let contactHash = recipient.token,
                  let contactNumber = PhoneCallManager.shared.currentContacts[contactHash] else {
                return nil
            }

            return contactNumber
        }() else {
            return .none
        }
        
        DispatchQueue.main.async {
            guard let phoneCallUrl = URL(string: "tel://\(phoneNumber.supportedContactString)"),
                  UIApplication.shared.canOpenURL(phoneCallUrl) else { return }
            
            UIApplication.shared.open(phoneCallUrl, options: [:]) { (success) in
                log.debug("making phone call \(success)")
            }
        }
        
        return nil
    }
}

// MARK: - Message

extension MainViewController: MessageAgentDelegate, MFMessageComposeViewControllerDelegate {
    private class MessageManager {
        static let shared = MessageManager()
        @Atomic var context: MessageAgentContext?
        @Atomic var currentContacts = [String: String]()
    }
    
    func messageAgentRequestContext() -> MessageAgentContext? {
        return MessageManager.shared.context
    }
    
    func messageAgentDidReceiveSendCandidates(item: MessageCandidatesItem, header: Downstream.Header) {
        guard item.intent == "SEND" else { return }
        
        var names = [String]()
        var searchType: ContactMatchType = .exact
        if let serverContacts = item.candidates,
           0 < serverContacts.count {
            // search exact match
            searchType = .exact
            names.append(contentsOf: serverContacts.map { $0.name }.compactMap({ $0 }))
        } else if let intendedName = item.recipientIntended?.name {
            // search partial match
            searchType = .partial
            names.append(intendedName)
        }
        
        ContactsUtil.shared.search(names: names, label: item.recipientIntended?.label, type: searchType) { (type, contacts) in
            var contactList  = [MessageAgentContact]()
            contacts.forEach { (contact) in
                // PhoneNumber를 서버로 전송할 수 없고(개인정보이슈), Person별로 token을 가지고 있으므로 같은 사람의 여러 연락처를 쪼갠다.
                contact.phoneNumbers.forEach { (phoneNumber) in
                    let token = contact.makeToken(with: phoneNumber.value)
                    MessageManager.shared.currentContacts[token] = phoneNumber.value.stringValue.supportedContactString
                    
                    let messageContact = MessageAgentContact(
                        name: contact.fullName,
                        type: item.candidates?.first?.type?.rawValue ?? "CONTACT",
                        number: nil,
                        label: item.recipientIntended?.label,
                        profileImgUrl: nil,
                        message: nil,
                        time: nil,
                        numInMessageHistory: nil,
                        token: token,
                        score: nil
                    )
                    contactList.append(messageContact)
                }
            }

            let template = MessageAgentContext.Template(info: nil, recipientIntended: item.recipientIntended, searchScene: item.searchScene, candidates: contactList, messageToSend: nil)
            MessageManager.shared.context = MessageAgentContext(readActivity: "IDLE", token: nil, template: template)

            NuguCentralManager.shared.client.messageAgent.requestSendCandidates(candidatesItem: item, header: header, completion: nil)
        }
    }
    
    func messageAgentDidReceiveSendMessage(recipient: MessageAgentContact, header: Downstream.Header) -> String? {
        guard MFMessageComposeViewController.canSendText() else {
            return "지금안됨"
        }
        
        DispatchQueue.main.async { [weak self] in
            let messageViewController = MFMessageComposeViewController()
            messageViewController.messageComposeDelegate = self
            
            if let token = recipient.token,
               let phoneNumber = MessageManager.shared.currentContacts[token] {
                messageViewController.recipients = [phoneNumber]
                messageViewController.body = recipient.message?.text
                
                self?.present(messageViewController, animated: true, completion: nil)
            }
        }
        
        return nil
    }
    
    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: true, completion: nil)
    }
}

extension MainViewController: LocationAgentDelegate {
    func locationAgentRequestLocationInfo() -> LocationInfo? {
        return LocationInfo(latitude: "37.715133.", longitude: "126.734086")
    }
}
