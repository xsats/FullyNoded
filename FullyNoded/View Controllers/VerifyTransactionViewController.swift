//
//  VerifyTransactionViewController.swift
//  FullyNoded
//
//  Created by Peter on 9/4/20.
//  Copyright © 2020 Fontaine. All rights reserved.
//

import UIKit

class VerifyTransactionViewController: UIViewController, UINavigationControllerDelegate, UITextFieldDelegate, UIDocumentPickerDelegate {
    
    var smartFee = Double()
    var txSize = Int()
    var rejectionMessage = ""
    var txValid: Bool?
    var memo = ""
    var txFee = Double()
    var fxRate: Double?
    var txid = ""
    var psbtDict:NSDictionary!
    var doneBlock: ((Bool) -> Void)?
    let spinner = ConnectingView()
    var unsignedPsbt = ""
    var signedRawTx = ""
    var outputsString = ""
    var inputArray = [[String:Any]]()
    var inputTableArray = [[String:Any]]()
    var outputArray = [[String:Any]]()
    var index = 0
    var inputTotal = Double()
    var outputTotal = Double()
    var miningFee = ""
    var recipients = [String]()
    var addressToVerify = ""
    var sweeping = Bool()
    var alertStyle = UIAlertController.Style.actionSheet
    var signatures = [[String:String]]()
    var signedTxInputs = NSArray()
    var alreadyBroadcast = false
    var confs = 0
    var labelText = "no label added"
    var memoText = "no memo added"
    var id:UUID!
    var hasSigned = false
    var isSigning = false
    var wallet:Wallet?
    var bitcoinCoreWallets = [String()]
    var walletIndex = 0
    
    @IBOutlet weak private var verifyTable: UITableView!
    @IBOutlet weak private var exportButtonOutlet: UIButton!
    @IBOutlet weak private var bumpFeeOutlet: UIButton!
    @IBOutlet weak private var signOutlet: UIButton!
    @IBOutlet weak private var sendOutlet: UIButton!
    @IBOutlet weak private var exportBackgroundView: UIView!
    @IBOutlet weak private var bumpFeeBackgroundView: UIView!
    @IBOutlet weak private var signBackgroundView: UIView!
    @IBOutlet weak private var sendBackgroundView: UIView!
    @IBOutlet weak private var buttonsBackgroundView: UIVisualEffectView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationController?.delegate = self
        
        verifyTable.delegate = self
        verifyTable.dataSource = self
        
        configureViews()
        
        activeWallet { [weak self] w in
            guard let self = self else { return }
            
            self.wallet = w
            
            if w == nil {
                showAlert(vc: self, title: "", message: "You are not working with a FN Wallet, this means functionality will be limited, toggle on a FN wallet to get full functionality.")
            }
        }
        
        if unsignedPsbt != "" || signedRawTx != "" {
            enableExportButton()
            
            if unsignedPsbt != "" {
                processPsbt(unsignedPsbt)
            } else {
                load()
            }
            
        } else {
            promptToAddTx()
        }
    }
    
    private func processPsbt(_ psbt: String) {
        Reducer.makeCommand(command: .walletprocesspsbt, param: "\"\(psbt)\", true, \"ALL\", true") { [weak self] (object, errorDescription) in
            guard let self = self else { return }
            
            guard let dict = object as? NSDictionary, let processedPsbt = dict["psbt"] as? String else {
                showAlert(vc: self, title: "", message: "There was an issue processing your psbt with the active wallet: \(errorDescription ?? "unknown error")")
                return
            }
            
            self.finalizePsbt(processedPsbt)
        }
    }
    
    private func finalizePsbt(_ psbt: String) {
        Reducer.makeCommand(command: .finalizepsbt, param: "\"\(psbt)\"") { [weak self] (object, errorDescription) in
            guard let self = self else { return }

            guard let result = object as? NSDictionary, let complete = result["complete"] as? Bool else {
                showAlert(vc: self, title: "", message: "There was an issue finalizing your psbt: \(errorDescription ?? "unknown error")")
                return
            }

            self.enableExportButton()

            guard complete, let hex = result["hex"] as? String else {
                guard let psbt = result["psbt"] as? String else {
                    showAlert(vc: self, title: "", message: "There was an issue finalizing your psbt: \(errorDescription ?? "unknown error")")
                    return
                }

                self.unsignedPsbt = psbt
                self.enableSignButton()
                self.load()

                return
            }

            self.signedRawTx = hex
            self.load()
        }
        
        // Finalizes locally - here for testing purposes
//        guard let hex = Keys.finalize(psbt) else {
//            return
//        }
//
//        print("hex: \(hex)")
    }
    
    private func enableExportButton() {
        enableView(exportBackgroundView)
        enableButton(exportButtonOutlet)
    }
    
    private func enableBumpFeeButton() {
        enableView(bumpFeeBackgroundView)
        enableButton(bumpFeeOutlet)
    }
    
    private func enableSignButton() {
        enableView(signBackgroundView)
        enableButton(signOutlet)
    }
    
    private func enableSendButton() {
        enableView(sendBackgroundView)
        enableButton(sendOutlet)
    }
    
    private func disableSendButton() {
        disableView(sendBackgroundView)
        disableButton(sendOutlet)
    }
    
    private func disableSignButton() {
        disableView(signBackgroundView)
        disableButton(signOutlet)
    }
    
    private func disableBumpButton() {
        disableButton(bumpFeeOutlet)
        disableView(bumpFeeBackgroundView)
    }
    
    private func disableExportButton() {
        disableView(exportBackgroundView)
        disableButton(exportButtonOutlet)
    }
    
    private func configureViews() {
        disableSendButton()
        disableBumpButton()
        disableSignButton()
        disableExportButton()
        
        buttonsBackgroundView.clipsToBounds = true
        buttonsBackgroundView.layer.cornerRadius = 8
        
        roundCorners(exportBackgroundView)
        roundCorners(bumpFeeBackgroundView)
        roundCorners(signBackgroundView)
        roundCorners(sendBackgroundView)
        
        let tap: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tap)
        
        if (UIDevice.current.userInterfaceIdiom == .pad) {
          alertStyle = UIAlertController.Style.alert
        }
        
        if alreadyBroadcast {
            if confs == 0 {
                enableBumpFeeButton()
            }
        } else {
            if signedRawTx == "" && unsignedPsbt != "" && !hasSigned {
                enableSignButton()
            } else if signedRawTx != "" {
                enableSendButton()
            }
        }
    }
    
    private func roundCorners(_ view: UIView) {
        DispatchQueue.main.async {
            view.layer.cornerRadius = 8
            view.clipsToBounds = true
            view.layer.borderWidth = 0.5
        }
    }
    
    private func enableButton(_ button: UIButton) {
        DispatchQueue.main.async {
            button.isEnabled = true
            button.alpha = 1
        }
    }
    
    private func disableButton(_ button: UIButton) {
        DispatchQueue.main.async {
            button.isEnabled = false
            button.alpha = 0.3
        }
    }
    
    private func enableView(_ view: UIView) {
        DispatchQueue.main.async {
            view.layer.borderColor = UIColor.lightGray.cgColor
        }
    }
    
    private func disableView(_ view: UIView) {
        DispatchQueue.main.async {
            view.layer.borderColor = UIColor.clear.cgColor
        }
    }
    
    private func copy(_ text: String) {
        DispatchQueue.main.async {
            UIPasteboard.general.string = text
        }
    }
    
    private func promptToAddTx() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let alert = UIAlertController(title: "Add Transaction", message: "You can add a transaction in a number of ways.", preferredStyle: self.alertStyle)
            
            alert.addAction(UIAlertAction(title: "Upload File", style: .default, handler: { action in
                self.presentUploader()
            }))
            
            alert.addAction(UIAlertAction(title: "Paste Text", style: .default, handler: { action in
                self.pasteAction()
            }))
            
            alert.addAction(UIAlertAction(title: "QR Code", style: .default, handler: { action in
                self.scanQr()
            }))
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { action in }))
            alert.popoverPresentationController?.sourceView = self.view
            self.present(alert, animated: true) {}
        }
    }
    
    private func scanQr() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.performSegue(withIdentifier: "segueToScanPsbt", sender: self)
        }
    }
    
    private func pasteAction() {
        if let data = UIPasteboard.general.data(forPasteboardType: "com.apple.traditional-mac-plain-text") {
            guard let string = String(bytes: data, encoding: .utf8) else {
                showAlert(vc: self, title: "Not a psbt?", message: "Looks like you do not have valid text on your clipboard")
                return
            }
            
            processPastedString(string)
        } else if let string = UIPasteboard.general.string {
            
           processPastedString(string)
        } else {
            
            showAlert(vc: self, title: "", message: "Not valid text. You can copy and paste the base64 text of a psbt or a signed raw transaction with this button.")
        }
    }
    
    private func processPastedString(_ string: String) {
        let processed = string.condenseWhitespace()
        if Keys.validPsbt(processed) {
            enableExportButton()
            processPsbt(processed)
        } else if Keys.validTx(processed) {
            enableExportButton()
            signedRawTx = processed
            load()
        } else {
            showAlert(vc: self, title: "Invalid", message: "Whatever you pasted was not a valid psbt or raw transaction.")
        }
    }
    
    private func presentUploader() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let documentPicker = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .import)
            documentPicker.delegate = self
            documentPicker.modalPresentationStyle = .formSheet
            self.present(documentPicker, animated: true, completion: nil)
        }
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard controller.documentPickerMode == .import else { return }
        
        guard let text = try? String(contentsOf: urls[0].absoluteURL), Keys.validTx(text) else {
            
            guard let data = try? Data(contentsOf: urls[0].absoluteURL) else {
                spinner.removeConnectingView()
                showAlert(vc: self, title: "Invalid File", message: "That is not a recognized format, generally it will be a .psbt or .txn file.")
                return
            }
            
            unsignedPsbt = data.base64EncodedString()
            processPsbt(unsignedPsbt)
            
            return
        }
                    
        signedRawTx = text
        load()
    }
    
    @IBAction func addTransactionAction(_ sender: Any) {
        promptToAddTx()
    }
    
    @objc func tapToAdd(_ sender: UIButton) {
        promptToAddTx()
    }
    
    @IBAction func exportAction(_ sender: Any) {
        if signedRawTx != "" {
            exportTxn(txn: signedRawTx)
        } else {
            exportPsbt(psbt: unsignedPsbt)
        }
    }
    
    @IBAction func sendAction(_ sender: Any) {
        if signedRawTx != "" {
            broadcast()
        } else {
            showAlert(vc: self, title: "", message: "Transaction not fully signed, you can export it to another signer or sign it if the sign button is enabled.")
        }
    }
    
    @IBAction func bumpFeeAction(_ sender: Any) {
        if confs == 0 && alreadyBroadcast {
            bumpFee()
        } else {
            showAlert(vc: self, title: "", message: "You can only bump the fee for transactions that have zero confirmations.")
        }
    }
    
    @IBAction func signAction(_ sender: Any) {
        isSigning = true
        spinner.addConnectingView(vc: self, description: "signing...")
        Signer.sign(psbt: self.unsignedPsbt) { [weak self] (signedPsbt, rawTx, errorMessage) in
            guard let self = self else { return }
                        
            self.disableSignButton()
            
            if signedPsbt != nil {
                self.unsignedPsbt = signedPsbt!
                self.load()
                
            } else if rawTx != nil {
                self.unsignedPsbt = ""
                self.signedRawTx = rawTx!
                self.enableSendButton()
                self.load()
                
            } else {
                self.spinner.removeConnectingView()
                showAlert(vc: self, title: "Error Signing", message: errorMessage ?? "unknown")
            }
        }
    }
    
    private func saveNewTx(_ txid: String) {
        var transaction = [String:Any]()
        
        self.id = UUID()
        transaction["id"] = self.id
        transaction["label"] = labelText
        transaction["memo"] = memoText
        transaction["date"] = Date()
        transaction["txid"] = txid
        
        if let fx = fxRate {
            transaction["originFxRate"] = fx
        }
        
        if let w = self.wallet {
            transaction["walletId"] = w.id
        }
        
        CoreDataService.saveEntity(dict: transaction, entityName: .transactions) { _ in }
    }
    
    private func bumpFee() {
        spinner.addConnectingView(vc: self, description: "increasing fee...")
        
        var bumpfee:BTC_CLI_COMMAND = .bumpfee
        
        let version = UserDefaults.standard.object(forKey: "version") as? String ?? "0.20"
        
        if version.contains("0.21.") {
            bumpfee = .psbtbumpfee
        }
        
        Reducer.makeCommand(command: bumpfee, param: "\"\(txid)\"") { [weak self] (response, errorMessage) in
            guard let self = self else { return }
            
            guard let result = response as? NSDictionary, let originalFee = result["origfee"] as? Double, let newFee = result["fee"] as? Double else {
                self.spinner.removeConnectingView()
                showAlert(vc: self, title: "There was an issue increasing the fee.", message: errorMessage ?? "unknown")
                return
            }
            
            guard let psbt = result["psbt"] as? String else {
                self.spinner.removeConnectingView()
                if let txid = result["txid"] as? String {
                    self.saveNewTx(txid)
                    displayAlert(viewController: self, isError: false, message: "fee bumped from \(originalFee.avoidNotation) to \(newFee.avoidNotation)")
                } else if let errors = result["errors"] as? NSArray {
                    showAlert(vc: self, title: "There was an error increasing the fee.", message: "\(errors)")
                }
                return
            }
            
            self.signedRawTx = ""
            
            Signer.sign(psbt: psbt) { (signedPsbt, rawTx, errorMessage) in
                self.spinner.removeConnectingView()
                
                self.disableBumpButton()
                
                if signedPsbt != nil {
                    self.unsignedPsbt = signedPsbt!
                    self.load()
                    showAlert(vc: self, title: "Fee increased to \(newFee.avoidNotation)", message: "The transaction still needs more signatures before it can be broadcast.")
                    
                } else if rawTx != nil {
                    self.signedRawTx = rawTx!
                    self.enableSendButton()
                    self.disableSignButton()
                    self.load()
                    showAlert(vc: self, title: "Fee increased to \(newFee.avoidNotation)", message: "Tap the send button to broadcast the new transaction.")
                    
                } else {
                    showAlert(vc: self, title: "Error Signing", message: errorMessage ?? "unknown")
                }
            }
        }
    }
    
    private func updateLabel(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.spinner.label.text = text
        }
    }
    
    private func load() {
        if !isSigning {
            spinner.addConnectingView(vc: self, description: "getting exchange rate....")
        } else {
            updateLabel("reloading signed transaction...")
        }
        
        inputArray.removeAll()
        inputTableArray.removeAll()
        outputArray.removeAll()
        recipients.removeAll()
        signatures.removeAll()
        outputsString = ""
        
        FiatConverter.sharedInstance.getFxRate { [weak self] exchangeRate in
            guard let self = self else { return }
            
            self.fxRate = exchangeRate
            
            if self.unsignedPsbt == "" {
                self.updateLabel("decoding raw transaction...")
                self.executeNodeCommand(method: .decoderawtransaction, param: "\"\(self.signedRawTx)\"")
            } else {
                self.updateLabel("decoding psbt...")
                
                self.executeNodeCommand(method: .decodepsbt, param: "\"\(self.unsignedPsbt)\"")
            }
        }
    }
    
    @objc func dismissKeyboard() {
        view.endEditing(true)
    }
    
    func executeNodeCommand(method: BTC_CLI_COMMAND, param: String) {
        
        func send() {
            Reducer.makeCommand(command: .sendrawtransaction, param: param) { [weak self] (response, errorMessage) in
                guard let self = self else { return }
                
                guard let _ = response as? String else {
                    self.spinner.removeConnectingView()
                    displayAlert(viewController: self, isError: true, message: errorMessage ?? "")
                    return
                }
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    self.disableSendButton()
                    self.spinner.removeConnectingView()
                    self.navigationItem.title = "Sent ✓"
                    displayAlert(viewController: self, isError: false, message: "Transaction sent ✓")
                }
            }
        }
        
        func decodePsbt() {
            Reducer.makeCommand(command: .decodepsbt, param: param) { [weak self] (object, errorDesc) in
                guard let self = self else { return }
                
                guard let dict = object as? NSDictionary else {
                    self.spinner.removeConnectingView()
                    displayAlert(viewController: self, isError: true, message: errorDesc ?? "")
                    return
                }
                
                self.psbtDict = dict
                
                if let inputs = dict["inputs"] as? NSArray, inputs.count > 0 {
                    for input in inputs {
                        if let inputDict = input as? NSDictionary {
                            if let signatures = inputDict["partial_signatures"] as? NSDictionary {
                                for (key, value) in signatures {
                                    self.signatures.append(["\(key)":(value as? String ?? "")])
                                }
                            }
                        }
                    }
                }
                
                if let txDict = dict["tx"] as? NSDictionary {
                    
                    if let size = txDict["vsize"] as? Int {
                        self.txSize = size
                    }
                    
                    if let id = txDict["txid"] as? String {
                        self.txid = id
                        self.loadLabelAndMemo()
                    }
                    
                    self.parseTransaction(tx: txDict)
                }
            }
        }
        
        func decodeTx() {
            Reducer.makeCommand(command: .decoderawtransaction, param: param) { [weak self] (object, errorDesc) in
                guard let self = self else { return }
                
                guard let dict = object as? NSDictionary else {
                    self.spinner.removeConnectingView()
                    displayAlert(viewController: self, isError: true, message: errorDesc ?? "")
                    return
                }
                
                if let size = dict["vsize"] as? Int {
                    self.txSize = size
                }
                
                if let id = dict["txid"] as? String {
                    self.txid = id
                    self.loadLabelAndMemo()
                }
                
                if let inputs = dict["vin"] as? NSArray {
                    self.signedTxInputs = inputs
                }
                
                self.parseTransaction(tx: dict)
            }
        }
        
        switch method {
        case .sendrawtransaction:
            send()
            
        case .decodepsbt:
            decodePsbt()
            
        case .decoderawtransaction:
            decodeTx()
            
        default:
            break
        }
    }
    
    func parseTransaction(tx: NSDictionary) {
        if let inputs = tx["vin"] as? NSArray, let outputs = tx["vout"] as? NSArray {
            parseOutputs(outputs: outputs)
            parseInputs(inputs: inputs, completion: getFirstInputInfo)
        }
    }
    
    func getFirstInputInfo() {
        index = 0
        getInputInfo(index: index)
    }
    
    func getInputInfo(index: Int) {
        let dict = inputArray[index]
        if let txid = dict["txid"] as? String, let vout = dict["vout"] as? Int {
            parsePrevTx(method: .gettransaction, param: "\"\(txid)\", true", vout: vout, txid: txid)
        }
    }
    
    func parseInputs(inputs: NSArray, completion: @escaping () -> Void) {
        for (index, i) in inputs.enumerated() {
            if let input = i as? NSDictionary {
                if let txid = input["txid"] as? String, let vout = input["vout"] as? Int {
                    let dict = ["inputNumber":index + 1, "txid":txid, "vout":vout as Any] as [String : Any]
                    inputArray.append(dict)
                    
                    if index + 1 == inputs.count {
                        completion()
                    }
                }
            }
        }
    }
    
    func parseOutputs(outputs: NSArray) {
        for (i, o) in outputs.enumerated() {
            if let output = o as? NSDictionary {
                if let scriptpubkey = output["scriptPubKey"] as? NSDictionary, let amount = output["value"] as? Double {
                    let addresses = scriptpubkey["addresses"] as? NSArray ?? []
                    let number = i + 1
                    var addressString = ""
                    
                    if addresses.count > 0 {
                        if addresses.count > 1 {
                            for a in addresses {
                                addressString += a as! String + " "
                            }
                        } else {
                            addressString = addresses[0] as? String ?? ""
                        }
                    }
                    
                    outputTotal += amount
                    var isChange = true
                    
                    for recipient in recipients {
                        if addressString == recipient {
                            isChange = false
                        }
                    }
                    
                    if sweeping {
                        isChange = false
                    }
                    
                    var amountString = amount.avoidNotation
                    
                    if fxRate != nil {
                        amountString += " btc / \(fiatAmount(btc: amount))"
                    }
                                        
                    let outputDict:[String:Any] = [
                        "index": number,
                        "amount": amountString,
                        "address": addressString,
                        "isChange": isChange,
                        "isOursBitcoind": false,// Hardcode at this stage and update before displaying
                        "isOursFullyNoded": false,
                        "walletLabel": "",
                        "lifehash": LifeHash.image(addressString) ?? UIImage(),
                        "signable": false,
                        "signerLabel": "",
                        "isDust": amount < 0.00020000
                    ]
                    
                    outputArray.append(outputDict)
                }
            }
        }
    }
    
    func parsePrevTxOutput(outputs: NSArray, vout: Int) {
        if outputs.count > 0 {
            for o in outputs {
                if let output = o as? NSDictionary {
                    if let n = output["n"] as? Int {
                        if n == vout {
                            //this is our inputs output, we can now get the amount and address for the input (PITA)
                            var addressString = ""
                            
                            if let scriptpubkey = output["scriptPubKey"] as? NSDictionary {
                                if let addresses = scriptpubkey["addresses"] as? NSArray {
                                    if addresses.count > 1 {
                                        for a in addresses {
                                            addressString += a as! String + " "
                                        }
                                        
                                    } else {
                                        addressString = addresses[0] as! String
                                    }
                                }
                            }
                            
                            if let amount = output["value"] as? Double {
                                inputTotal += amount
                                var amountString = amount.avoidNotation
                                
                                if fxRate != nil {
                                    amountString += " btc / \(fiatAmount(btc: amount))"
                                }
                                
                                let inputDict:[String:Any] = [
                                    "index": index + 1,
                                    "amount": amountString,
                                    "address": addressString,
                                    "lifehash": LifeHash.image(addressString) ?? UIImage(),
                                    "isOurs": false,// Hardcode at this stage and update before displaying
                                    "isDust": amount < 0.00020000
                                ]
                                
                                inputTableArray.append(inputDict)
                            }
                        }
                    }
                }
            }
        } else {
            let inputDict:[String:Any] = [
                "index": index + 1,
                "amount": "unknown",
                "address": "unknown",
                "lifehash": UIImage(),
                "isOurs": false,// Hardcode at this stage and update before displaying
                "isDust": true
            ]
            
            inputTableArray.append(inputDict)
        }
        
        if index + 1 < inputArray.count {
            index += 1
            getInputInfo(index: index)
            
        } else if index + 1 == inputArray.count {
            index = 0
            txFee = inputTotal - outputTotal
            
            if inputTotal > 0.0 {
                let txfeeString = txFee.avoidNotation
                if fxRate != nil {
                    self.miningFee = "\(txfeeString) btc / \(fiatAmount(btc: self.txFee))"
                } else {
                    self.miningFee = "\(txfeeString) btc / error fetching fx rate"
                }
            } else {
                self.miningFee = "No fee data. Go to settings to opt in to Esplora use."
            }
            
            verifyInputs()
        }
    }
    
    private func verifyInputs() {
        if index < inputTableArray.count {
            self.updateLabel("verifying input #\(self.index + 1) out of \(self.inputTableArray.count)")
            
            if let address = inputTableArray[index]["address"] as? String, address != "unknown", address != "" {
                Reducer.makeCommand(command: .getaddressinfo, param: "\"\(address)\"") { [weak self] (response, errorMessage) in
                    guard let self = self else { return }
                    
                    guard errorMessage == nil else {
                        self.spinner.removeConnectingView()
                        if errorMessage!.contains("Wallet file not specified (must request wallet RPC through") {
                            showAlert(vc: self, title: "No wallet specified!", message: "Please go to your Active Wallet tab and toggle on a wallet then try this operation again, for certain commands Bitcoin Core needs to know which wallet to talk to.")
                        } else {
                            showAlert(vc: self, title: "Error", message: errorMessage ?? "unknown")
                        }
                        
                        return
                    }
                    
                    if let dict = response as? NSDictionary {
                        let solvable = dict["solvable"] as? Bool ?? false
                        let keypath = dict["hdkeypath"] as? String ?? "no key path"
                        let labels = dict["labels"] as? NSArray ?? ["no label"]
                        let desc = dict["desc"] as? String ?? "no descriptor"
                        var isChange = dict["ischange"] as? Bool ?? false
                        let fingerprint = dict["hdmasterfingerprint"] as? String ?? "no fingerprint"
                        let script = dict["script"] as? String ?? ""
                        let sigsrequired = dict["sigsrequired"] as? Int ?? 0
                        let pubkeys = dict["pubkeys"] as? [String] ?? []
                        var labelsText = ""
                        if labels.count > 0 {
                            for label in labels {
                                if label as? String == "" {
                                    labelsText += "no label "
                                } else {
                                    labelsText += "\(label as? String ?? "") "
                                }
                            }
                        } else {
                            labelsText += "no label "
                        }
                        
                        if desc.contains("/1/") {
                            isChange = true
                        }
                        
                        self.inputTableArray[self.index]["isOurs"] = solvable
                        self.inputTableArray[self.index]["hdKeyPath"] = keypath
                        self.inputTableArray[self.index]["isChange"] = isChange
                        self.inputTableArray[self.index]["label"] = labelsText
                        self.inputTableArray[self.index]["fingerprint"] = fingerprint
                        self.inputTableArray[self.index]["desc"] = desc
                        
                        if script == "multisig" && self.signedRawTx == "" {
                            self.inputTableArray[self.index]["sigsrequired"] = sigsrequired
                            self.inputTableArray[self.index]["pubkeys"] = pubkeys
                            var numberOfSigs = 0
                            
                            // Will only be any for a psbt
                            for (i, sigs) in self.signatures.enumerated() {
                                for (key, _) in sigs {
                                    for pk in pubkeys {
                                        if pk == key {
                                            numberOfSigs += 1
                                        }
                                    }
                                }
                                
                                if i + 1 == self.signatures.count {
                                    self.inputTableArray[self.index]["signatures"] = "\(numberOfSigs) out of \(sigsrequired) signatures"
                                }
                                
                            }
                            
                        } else {
                            // Will only be any for a signed raw transaction
                            if self.signedTxInputs.count > 0 {
                                self.inputTableArray[self.index]["signatures"] = "Unsigned"
                                let input = self.signedTxInputs[self.index] as? NSDictionary ?? [:]
                                let scriptsig = input["scriptSig"] as? NSDictionary ?? [:]
                                let hex = scriptsig["hex"] as? String ?? ""
                                
                                if hex != "" {
                                    self.inputTableArray[self.index]["signatures"] = "Signatures complete"
                                } else {
                                    if let txwitness = input["txinwitness"] as? NSArray {
                                        
                                        if txwitness.count > 1 {
                                            self.inputTableArray[self.index]["signatures"] = "Signatures complete"
                                        }
                                    }
                                }
                            }
                        }
                        self.index += 1
                        self.verifyInputs()
                    }
                }
            } else {
                self.index += 1
                self.verifyInputs()
            }
        } else {
            self.index = 0
            verifyOutputs()
        }
    }
    
    private func verifyOutputs() {
        if index < outputArray.count {
            self.updateLabel("verifying output #\(self.index + 1) out of \(self.outputArray.count)")
            
            if let address = outputArray[index]["address"] as? String, address != "" {
                Reducer.makeCommand(command: .getaddressinfo, param: "\"\(address)\"") { [weak self] (response, errorMessage) in
                    guard let self = self else { return }
                    
                    if let dict = response as? NSDictionary {
                        let solvable = dict["solvable"] as? Bool ?? false
                        let keypath = dict["hdkeypath"] as? String ?? "no key path"
                        let labels = dict["labels"] as? NSArray ?? ["no label"]
                        let desc = dict["desc"] as? String ?? "no descriptor"
                        var isChange = dict["ischange"] as? Bool ?? false
                        let fingerprint = dict["hdmasterfingerprint"] as? String ?? "no fingerprint"
                        var labelsText = ""
                        
                        if labels.count > 0 {
                            for label in labels {
                                if label as? String == "" {
                                    labelsText += "no label "
                                } else {
                                    labelsText += "\(label as? String ?? "") "
                                }
                            }
                        } else {
                            labelsText += "no label "
                        }
                        
                        if desc.contains("/1/") {
                            isChange = true
                        }
                        
                        self.outputArray[self.index]["isOursBitcoind"] = solvable
                        self.outputArray[self.index]["hdKeyPath"] = keypath
                        self.outputArray[self.index]["isChange"] = isChange
                        self.outputArray[self.index]["label"] = labelsText
                        self.outputArray[self.index]["fingerprint"] = fingerprint
                        self.outputArray[self.index]["desc"] = desc
                        
                        // Currently only verify address if the node knows about it.. otherwise we have to brute force 200k addresses...
                        // will add a dedicated verify button for unsolvable to cross check against all wallets
                        // also adding a signer verify button to show whether FN is able to sign for the output or not
                        if solvable && self.wallet != nil {
                            // Only do this if we are not using the default wallet.
                            Keys.verifyAddress(address, keypath, desc) { (isOursFullyNoded, walletLabel, signable, signer) in
                                self.outputArray[self.index]["isOursFullyNoded"] = isOursFullyNoded
                                self.outputArray[self.index]["walletLabel"] = walletLabel
                                self.outputArray[self.index]["signable"] = signable
                                self.outputArray[self.index]["signerLabel"] = signer
                                self.index += 1
                                self.verifyOutputs()
                            }
                        } else {
                            self.outputArray[self.index]["isOursFullyNoded"] = false
                            self.outputArray[self.index]["walletLabel"] = ""
                            self.index += 1
                            self.verifyOutputs()
                        }
                    }
                }
            } else {
                self.index += 1
                self.verifyOutputs()
            }
        } else {
            guard signedRawTx != "" else {
                getFeeRate()
                return
            }
            
            if !alreadyBroadcast {
                updateLabel("verifying mempool accept...")
                
                Reducer.makeCommand(command: .testmempoolaccept, param: "[\"\(signedRawTx)\"]") { [weak self] (response, errorMessage) in
                    guard let self = self else { return }
                    
                    guard let arr = response as? NSArray, arr.count > 0,
                        let dict = arr[0] as? NSDictionary,
                        let allowed = dict["allowed"] as? Bool else {
                        self.getFeeRate()
                        return
                    }
                    
                    self.txValid = allowed
                    
                    if allowed {
                        self.enableSendButton()
                    }
                    
                    self.rejectionMessage = dict["reject-reason"] as? String ?? ""
                    self.getFeeRate()
                }
            } else {
                self.getFeeRate()
            }
        }
    }
    
    private func getFeeRate() {
        let target = UserDefaults.standard.object(forKey: "feeTarget") as? Int ?? 432
        
        updateLabel("estimating smart fee...")
        
        Reducer.makeCommand(command: .estimatesmartfee, param: "\(target)") { [weak self] (response, errorMessage) in
            guard let self = self else { return }
            
            guard let dict = response as? NSDictionary, let feeRate = dict["feerate"] as? Double else {
                self.loadTableData()
                return
            }
            
            let inSatsPerKb = Double(feeRate) * 100000000.0
            self.smartFee = inSatsPerKb / 1000.0
            self.loadTableData()
        }
    }
    
    private func fiatAmount(btc: Double) -> String {
        guard let fxRate = fxRate else { return "error getting fiat rate" }
        let fiat = fxRate * btc
        let roundedFiat = Double(round(100*fiat)/100)
        return "$\(roundedFiat.withCommas())"
    }
    
    func loadTableData() {
        DispatchQueue.main.async { [weak self] in
            self?.verifyTable.reloadData()
        }
        spinner.removeConnectingView()
        
        guard let _ = KeyChain.getData("UnlockPassword") else {
            showAlert(vc: self, title: "You are not using the app securely...", message: "Anyone who gets access to this device will be able to spend your Bitcoin, we urge you to add a lock password via the lock button on the home screen.")
            
            return
        }
    }
    
    func parsePrevTx(method: BTC_CLI_COMMAND, param: String, vout: Int, txid: String) {
        
        func decodeRaw() {
            updateLabel("decoding inputs previous output...")
            Reducer.makeCommand(command: .decoderawtransaction, param: param) { [weak self] (object, errorDescription) in
                guard let self = self else { return }
                
                guard let txDict = object as? NSDictionary, let outputs = txDict["vout"] as? NSArray else {
                    self.spinner.removeConnectingView()
                    displayAlert(viewController: self, isError: true, message: "Error decoding raw transaction")
                    return
                }
                
                self.parsePrevTxOutput(outputs: outputs, vout: vout)
            }
        }
        
        func getRawTx() {
            updateLabel("fetching inputs previous output...")
            Reducer.makeCommand(command: .getrawtransaction, param: "\"\(txid)\"") { [weak self] (response, errorMessage) in
                guard let self = self else { return }
                
                guard let hex = response as? String else {
                    
                    guard let errorMessage = errorMessage else {
                        self.spinner.removeConnectingView()
                        displayAlert(viewController: self, isError: true, message: "Error parsing inputs")
                        return
                    }
                    
                    guard errorMessage.contains("No such mempool transaction") else {
                        self.spinner.removeConnectingView()
                        displayAlert(viewController: self, isError: true, message: "Error parsing inputs: \(errorMessage)")
                        return
                    }
                    
                    Reducer.makeCommand(command: .gettransaction, param: "\"\(txid)\", true") { (response, errorMessage) in
                        guard let dict = response as? NSDictionary, let hex = dict["hex"] as? String else {
                            
                            guard let useEsplora = UserDefaults.standard.object(forKey: "useEsplora") as? Bool, useEsplora else {
                                
                                if UserDefaults.standard.object(forKey: "useEsplora") == nil && UserDefaults.standard.object(forKey: "useEsploraAlert") == nil {
                                    showAlert(vc: self, title: "Unable to fetch input.", message: "Pruned nodes can not lookup input details for inputs that are associated with transactions which are not owned by the active wallet. In order to see inputs in detail you can enable Esplora (Blockstream's block explorer) over Tor in \"Settings\".")
                                    
                                    UserDefaults.standard.setValue(true, forKey: "useEsploraAlert")
                                }
                                
                                self.parsePrevTxOutput(outputs: [], vout: 0)
                                return
                            }
                            
                            self.updateLabel("fetching inputs previous output with Esplora...")
                            
                            let fetcher = GetTx.sharedInstance
                            fetcher.fetch(txid: txid) { [weak self] rawHex in
                                guard let self = self else { return }
                                
                                guard let rawHex = rawHex else {
                                    // Esplora must be down, pass an empty array instead
                                    self.parsePrevTxOutput(outputs: [], vout: 0)
                                    return
                                }
                                
                                self.parsePrevTx(method: .decoderawtransaction, param: "\"\(rawHex)\"", vout: vout, txid: txid)
                            }
                            return
                        }
                        self.parsePrevTx(method: .decoderawtransaction, param: "\"\(hex)\"", vout: vout, txid: txid)
                    }
                    return
                }
                self.parsePrevTx(method: .decoderawtransaction, param: "\"\(hex)\"", vout: vout, txid: txid)
            }
        }
        
        switch method {
        case .decoderawtransaction:
            decodeRaw()
            
        case .gettransaction:
            getRawTx()
            
        default:
            break
        }
        
    }
    
    private func defaultCell(_ indexPath: IndexPath) -> UITableViewCell {
        let cell = verifyTable.dequeueReusableCell(withIdentifier: "defaultCell", for: indexPath)
        configureCell(cell)
        
        let addButton = cell.viewWithTag(2) as! UIButton
        addButton.addTarget(self, action: #selector(tapToAdd(_:)), for: .touchUpInside)
        
        return cell
    }
    
    private func confsCell(_ indexPath: IndexPath) -> UITableViewCell {
        let confsCell = verifyTable.dequeueReusableCell(withIdentifier: "miningFeeCell", for: indexPath)
        configureCell(confsCell)
        
        let label = confsCell.viewWithTag(1) as! UILabel
        let imageView = confsCell.viewWithTag(2) as! UIImageView
        let background = confsCell.viewWithTag(3)!
        background.layer.cornerRadius = 5
        imageView.tintColor = .white
        label.text = "\(confs) confirmations"
        
        if confs > 0 {
            background.backgroundColor = .systemGreen
            imageView.image = UIImage(systemName: "checkmark.seal")
        } else {
            background.backgroundColor = .systemRed
            imageView.image = UIImage(systemName: "exclamationmark.triangle")
        }
        return confsCell
    }
    
    private func mempoolAcceptCell(_ indexPath: IndexPath) -> UITableViewCell {
        let mempoolAcceptCell = verifyTable.dequeueReusableCell(withIdentifier: "miningFeeCell", for: indexPath)
        configureCell(mempoolAcceptCell)
        
        let label = mempoolAcceptCell.viewWithTag(1) as! UILabel
        let imageView = mempoolAcceptCell.viewWithTag(2) as! UIImageView
        let background = mempoolAcceptCell.viewWithTag(3)!
        background.layer.cornerRadius = 5
        imageView.tintColor = .white
        
        if txValid != nil {
            if txValid! {
                label.text = "Mempool acception verified ✓"
                background.backgroundColor = .systemGreen
                imageView.image = UIImage(systemName: "checkmark.seal")
            } else {
                label.text = "Transaction invalid! Reason: \(rejectionMessage)"
                background.backgroundColor = .systemRed
                imageView.image = UIImage(systemName: "exclamationmark.triangle")
            }
        } else {
            if unsignedPsbt != "" {
                label.text = "Transaction incomplete."
            } else {
                label.text = "This feature requires at least Bitcoin Core 0.20.0"
            }
            
            background.backgroundColor = .darkGray
            imageView.image = UIImage(systemName: "exclamationmark.triangle")
        }
        
        mempoolAcceptCell.selectionStyle = .none
        label.textColor = .lightGray
        label.adjustsFontSizeToFitWidth = true
        return mempoolAcceptCell
    }
    
    private func txidCell(_ indexPath: IndexPath) -> UITableViewCell {
        let txidCell = verifyTable.dequeueReusableCell(withIdentifier: "miningFeeCell", for: indexPath)
        configureCell(txidCell)
        
        let txidLabel = txidCell.viewWithTag(1) as! UILabel
        let imageView = txidCell.viewWithTag(2) as! UIImageView
        let background = txidCell.viewWithTag(3)!
        background.layer.cornerRadius = 5
        background.backgroundColor = .systemBlue
        imageView.tintColor = .white
        imageView.image = UIImage(systemName: "rectangle.and.paperclip")
        txidLabel.text = txid
        txidCell.selectionStyle = .none
        txidLabel.textColor = .lightGray
        txidLabel.adjustsFontSizeToFitWidth = true
        return txidCell
    }
    
    private func inputCell(_ indexPath: IndexPath) -> UITableViewCell {
        let inputCell = verifyTable.dequeueReusableCell(withIdentifier: "inputOutputCell", for: indexPath)
        configureCell(inputCell)
        
        let inputIndexLabel = inputCell.viewWithTag(1) as! UILabel
        let inputAmountLabel = inputCell.viewWithTag(2) as! UILabel
        let inputAddressLabel = inputCell.viewWithTag(3) as! UILabel
        let inputIsOursImage = inputCell.viewWithTag(4) as! UIImageView
        let inputIsOursLabel = inputCell.viewWithTag(5) as! UILabel
        let inputTypeLabel = inputCell.viewWithTag(6) as! UILabel
        let utxoLabel = inputCell.viewWithTag(7) as! UILabel
        let isChangeImageView = inputCell.viewWithTag(8) as! UIImageView
        let lifehashImageView = inputCell.viewWithTag(9) as! UIImageView
        let isDustImageView = inputCell.viewWithTag(10) as! UIImageView
        let backgroundView1 = inputCell.viewWithTag(11)!
        let backgroundView2 = inputCell.viewWithTag(12)!
        let backgroundView3 = inputCell.viewWithTag(13)!
        let signaturesLabel = inputCell.viewWithTag(14) as! UILabel
        let descTextView = inputCell.viewWithTag(15) as! UITextView
        let sigsBackgroundView = inputCell.viewWithTag(16)!
        let sigsImageView = inputCell.viewWithTag(17) as! UIImageView
        let copyAddressButton = inputCell.viewWithTag(18) as! UIButton
        let copyDescButton = inputCell.viewWithTag(19) as! UIButton
                
        backgroundView1.layer.cornerRadius = 5
        backgroundView2.layer.cornerRadius = 5
        backgroundView3.layer.cornerRadius = 5
        sigsBackgroundView.layer.cornerRadius = 5
        isDustImageView.tintColor = .white
        isChangeImageView.tintColor = .white
        inputIsOursImage.tintColor = .white
        sigsImageView.tintColor = .white
        descTextView.clipsToBounds = true
        descTextView.layer.cornerRadius = 8
        descTextView.layer.borderWidth = 0.5
        descTextView.layer.borderColor = UIColor.darkGray.cgColor
        
        if indexPath.row < inputTableArray.count {
            let input = inputTableArray[indexPath.row]
            
            let isOurs = input["isOurs"] as? Bool ?? false
            let isChange = input["isChange"] as? Bool ?? false
            let label = input["label"] as? String ?? "no label"
            let isDust = input["isDust"] as? Bool ?? false
            let signatureStatus = input["signatures"] as? String ?? "no signature data"
            let desc = input["desc"] as? String ?? "no descriptor"
            let lifehash = input["lifehash"] as? UIImage ?? UIImage()
            let inputAddress = input["address"] as! String
            
            utxoLabel.text = label
            signaturesLabel.text = signatureStatus
            descTextView.text = desc
            lifehashImageView.image = lifehash
            sigsImageView.image = UIImage(systemName: "signature")
            
            inputIndexLabel.text = "Input #\(input["index"] as! Int)"
            inputAmountLabel.text = "\((input["amount"] as! String))"
            inputAddressLabel.text = inputAddress
            
            copyAddressButton.restorationIdentifier = inputAddress
            copyDescButton.restorationIdentifier = desc
            
            copyAddressButton.addTarget(self, action: #selector(copyAddress(_:)), for: .touchUpInside)
            copyDescButton.addTarget(self, action: #selector(copyDesc(_:)), for: .touchUpInside)
            
            if signatureStatus == "Signatures complete" {
                sigsBackgroundView.backgroundColor = .systemGreen
            } else if self.signatures.count > 0 {
                sigsBackgroundView.backgroundColor = .systemOrange
            } else {
                sigsBackgroundView.backgroundColor = .systemRed
            }
            
            if isDust {
                isDustImageView.image = UIImage(systemName: "exclamationmark.triangle")
                backgroundView3.backgroundColor = .systemRed
            } else {
                isDustImageView.image = UIImage(systemName: "checkmark.circle.fill")
                backgroundView3.backgroundColor = .systemGreen
            }
            
            if isChange {
                isChangeImageView.image = UIImage(systemName: "arrow.2.circlepath")
                backgroundView2.backgroundColor = .systemPurple
                inputTypeLabel.text = "Change input"
            } else {
                isChangeImageView.image = UIImage(systemName: "arrow.down.left")
                backgroundView2.backgroundColor = .systemBlue
                inputTypeLabel.text = "Receive input"
            }
            
            if isOurs {
                backgroundView1.backgroundColor = .systemGreen
                inputIsOursImage.image = UIImage(systemName: "checkmark.circle.fill")
                
                if let walletLabel = wallet?.label {
                    inputIsOursLabel.text = "Owned by \(walletLabel)"
                } else {
                    inputIsOursLabel.text = "Owned by the Active Wallet"
                }
                
            } else {
                inputTypeLabel.text = "Unknown type"
                backgroundView2.backgroundColor = .systemGray
                backgroundView1.backgroundColor = .systemGray
                inputIsOursImage.image = UIImage(systemName: "questionmark.diamond.fill")
                isChangeImageView.image = UIImage(systemName: "questionmark.diamond.fill")
                
                if let walletLabel = wallet?.label {
                    inputIsOursLabel.text = "Not owned by \(walletLabel)"
                } else {
                    inputIsOursLabel.text = "Not owned by the Active Wallet"
                }
            }
        }
        
        return inputCell
    }
    
    private func outputCell(_ indexPath: IndexPath) -> UITableViewCell {
        let outputCell = verifyTable.dequeueReusableCell(withIdentifier: "outputCell", for: indexPath)
        configureCell(outputCell)
        
        let outputIndexLabel = outputCell.viewWithTag(1) as! UILabel
        let outputAmountLabel = outputCell.viewWithTag(2) as! UILabel
        let outputAddressLabel = outputCell.viewWithTag(3) as! UILabel
        let outputIsOursImage = outputCell.viewWithTag(4) as! UIImageView
        let lifehashImageView = outputCell.viewWithTag(5) as! UIImageView
        let verifiedByFnImageView = outputCell.viewWithTag(6) as! UIImageView
        let labelLabel = outputCell.viewWithTag(7) as! UILabel
        let isChangeImageView = outputCell.viewWithTag(8) as! UIImageView
        let verifiedByFnLabel = outputCell.viewWithTag(9) as! UILabel
        let isDustImageView = outputCell.viewWithTag(10) as! UIImageView
        let backgroundView1 = outputCell.viewWithTag(11)!
        let backgroundView2 = outputCell.viewWithTag(12)!
        let backgroundView3 = outputCell.viewWithTag(13)!
        let verifiedByFnBackgroundView = outputCell.viewWithTag(14)!
        let descTextView = outputCell.viewWithTag(15) as! UITextView
        let signableBackgroundView = outputCell.viewWithTag(16)!
        let signableImageView = outputCell.viewWithTag(17) as! UIImageView
        let signerLabel = outputCell.viewWithTag(18) as! UILabel
        let verifiedByNodeLabel = outputCell.viewWithTag(19) as! UILabel
        let addressTypeLabel = outputCell.viewWithTag(20) as! UILabel
        let copyAddressButton = outputCell.viewWithTag(21) as! UIButton
        let copyDescriptorButton = outputCell.viewWithTag(22) as! UIButton
        let verifyOwnerButton = outputCell.viewWithTag(23) as! UIButton
                
        signableBackgroundView.layer.cornerRadius = 5
        verifiedByFnBackgroundView.layer.cornerRadius = 5
        backgroundView1.layer.cornerRadius = 5
        backgroundView2.layer.cornerRadius = 5
        backgroundView3.layer.cornerRadius = 5
        descTextView.layer.cornerRadius = 8
        descTextView.layer.borderWidth = 0.5
        descTextView.layer.borderColor = UIColor.darkGray.cgColor
        
        signableImageView.tintColor = .white
        isDustImageView.tintColor = .white
        isChangeImageView.tintColor = .white
        outputIsOursImage.tintColor = .white
        verifiedByFnImageView.tintColor = .white
                        
        if indexPath.row < outputArray.count {
            let output = outputArray[indexPath.row]
            
            let outputAddress = output["address"] as? String ?? ""
            let signable = output["signable"] as? Bool ?? false
            let signer =  output["signerLabel"] as? String ?? ""
            let walletLabel = output["walletLabel"] as? String ?? ""
            let isOursFullyNoded = output["isOursFullyNoded"] as? Bool ?? false
            let isOursBitcoind = output["isOursBitcoind"] as? Bool ?? false
            let isChange = output["isChange"] as? Bool ?? false
            let label = output["label"] as? String ?? "no label"
            let isDust = output["isDust"] as? Bool ?? false
            let desc = output["desc"] as? String ?? "no descriptor"
            let lifehash = output["lifehash"] as? UIImage ?? UIImage()
            
            labelLabel.text = label
            descTextView.text = desc
            lifehashImageView.layer.magnificationFilter = .nearest
            lifehashImageView.image = lifehash
            
            outputIndexLabel.text = "Output #\(output["index"] as! Int)"
            outputAmountLabel.text = "\((output["amount"] as! String))"
            outputAddressLabel.text = outputAddress
            
            copyAddressButton.restorationIdentifier = outputAddress
            verifyOwnerButton.restorationIdentifier = outputAddress + " " + "\(indexPath.row)"
            copyDescriptorButton.restorationIdentifier = desc
            
            copyAddressButton.addTarget(self, action: #selector(copyAddress(_:)), for: .touchUpInside)
            copyDescriptorButton.addTarget(self, action: #selector(copyDesc(_:)), for: .touchUpInside)
            verifyOwnerButton.addTarget(self, action: #selector(verifyOwner(_:)), for: .touchUpInside)
            
            if isOursFullyNoded {
                verifiedByFnLabel.text = "Owned by \(walletLabel)"
                verifiedByFnImageView.image = UIImage(systemName: "checkmark.seal.fill")
                verifiedByFnBackgroundView.backgroundColor = .systemGreen
            } else {
                verifyOwnerButton.alpha = 1
                if isOursBitcoind {
                    if self.wallet != nil && !outputAddress.hasPrefix("2") && !outputAddress.hasPrefix("3") {
                        verifiedByFnLabel.text = "WARNING ADDRESS INVALID!!!"
                        verifiedByFnImageView.image = UIImage(systemName: "exclamationmark.triangle.fill")
                        verifiedByFnBackgroundView.backgroundColor = .systemRed
                    } else {
                        verifiedByFnLabel.text = "Unable to determine"
                        verifiedByFnImageView.image = UIImage(systemName: "questionmark.diamond.fill")
                        verifiedByFnBackgroundView.backgroundColor = .systemGray
                    }
                    
                } else {
                    verifiedByFnLabel.text = "Not verified by Fully Noded"
                    verifiedByFnImageView.image = UIImage(systemName: "questionmark.diamond.fill")
                    verifiedByFnBackgroundView.backgroundColor = .systemGray
                }
            }
            
            if signable {
                signableImageView.image = UIImage(systemName: "checkmark.square.fill")
                signableBackgroundView.backgroundColor = .systemGreen
                signerLabel.text = "Signable by \(signer)"
            } else {
                if self.wallet != nil {
                    signableImageView.image = UIImage(systemName: "xmark.square.fill")
                    signableBackgroundView.backgroundColor = .systemRed
                    signerLabel.text = "Can not sign!"
                } else {
                    signableImageView.image = UIImage(systemName: "questionmark.diamond.fill")
                    signableBackgroundView.backgroundColor = .systemRed
                    signerLabel.text = "Unable to determine"
                }
            }
            
            if isDust {
                isDustImageView.image = UIImage(systemName: "exclamationmark.triangle")
                backgroundView3.backgroundColor = .systemRed
            } else {
                isDustImageView.image = UIImage(systemName: "checkmark.circle.fill")
                backgroundView3.backgroundColor = .systemGreen
            }
            
            if isChange {
                isChangeImageView.image = UIImage(systemName: "arrow.2.circlepath")
                backgroundView2.backgroundColor = .systemPurple
                addressTypeLabel.text = "Change address"
            } else {
                isChangeImageView.image = UIImage(systemName: "arrow.up.right")
                backgroundView2.backgroundColor = .systemBlue
                addressTypeLabel.text = "Receive address"
            }
            
            var activeWalletLabel = "Bitcoin Core"
            
            if self.wallet != nil {
                activeWalletLabel = self.wallet!.label
            }
            
            if isOursBitcoind {
                verifyOwnerButton.alpha = 0
                verifiedByNodeLabel.text = "Owned by Bitcoin Core"
                backgroundView1.backgroundColor = .systemGreen
                outputIsOursImage.image = UIImage(systemName: "checkmark.circle.fill")
            } else {
                verifyOwnerButton.alpha = 1
                verifiedByNodeLabel.text = "Not owned by \(activeWalletLabel)"
                backgroundView1.backgroundColor = .systemGray
                outputIsOursImage.image = UIImage(systemName: "questionmark.diamond.fill")
                
                isChangeImageView.image = UIImage(systemName: "questionmark.diamond.fill")
                backgroundView2.backgroundColor = .systemGray
                addressTypeLabel.text = "Address type unknown"
            }
        }
        
        return outputCell
    }
    
    private func miningFeeCell(_ indexPath: IndexPath) -> UITableViewCell {
        let miningFeeCell = verifyTable.dequeueReusableCell(withIdentifier: "miningFeeCell", for: indexPath)
        miningFeeCell.selectionStyle = .none
        configureCell(miningFeeCell)
        
        let miningLabel = miningFeeCell.viewWithTag(1) as! UILabel
        miningLabel.textColor = .lightGray
        
        let imageView = miningFeeCell.viewWithTag(2) as! UIImageView
        imageView.tintColor = .white
        
        let background = miningFeeCell.viewWithTag(3)!
        background.layer.cornerRadius = 5
        
        if inputTotal > 0.0 {
            if txFee < 0.00050000 {
                background.backgroundColor = .systemGreen
                imageView.image = UIImage(systemName: "checkmark.circle")
            } else {
                background.backgroundColor = .systemRed
                imageView.image = UIImage(systemName: "exclamationmark.triangle")
            }
            
            miningLabel.text = miningFee + " / \(satsPerByte()) sats per byte"
            
        } else {
            background.backgroundColor = .systemOrange
            imageView.image = UIImage(systemName: "questionmark.circle")
            miningLabel.text = miningFee
        }
        
        return miningFeeCell
    }
    
    private func etaCell(_ indexPath: IndexPath) -> UITableViewCell {
        let etaCell = verifyTable.dequeueReusableCell(withIdentifier: "miningFeeCell", for: indexPath)
        etaCell.selectionStyle = .none
        configureCell(etaCell)
        
        let etaLabel = etaCell.viewWithTag(1) as! UILabel
        etaLabel.textColor = .lightGray
        
        let imageView = etaCell.viewWithTag(2) as! UIImageView
        imageView.tintColor = .white
        
        let background = etaCell.viewWithTag(3)!
        background.layer.cornerRadius = 5
        
        if inputTotal > 0.0 {
            var feeWarning = ""
            let percentage = (satsPerByte() / smartFee) * 100
            let rounded = Double(round(10*percentage)/10)
            if satsPerByte() > smartFee, rounded.isFinite {
                feeWarning = "The fee paid for this transaction is \(Int(rounded - 100))% greater then your target."
            } else if rounded.isFinite {
                feeWarning = "The fee paid for this transaction is \(Int(100 - rounded))% less then your target."
            } else {
                feeWarning = "Unable to determine fee difference."
            }
            
            if percentage >= 90 && percentage <= 110 {
                background.backgroundColor = .systemGreen
                imageView.image = UIImage(systemName: "checkmark.circle")
                etaLabel.text = "Fee is on target for a confirmation in approximately \(eta()) or \(feeTarget()) blocks"
            } else {
                if percentage <= 90 {
                    background.backgroundColor = .systemRed
                    imageView.image = UIImage(systemName: "tortoise")
                    etaLabel.text = feeWarning
                } else {
                    background.backgroundColor = .systemRed
                    imageView.image = UIImage(systemName: "hare")
                    etaLabel.text = feeWarning
                }
            }
        } else {
            imageView.image = UIImage(systemName: "questionmark.circle")
            background.backgroundColor = .systemOrange
            etaLabel.text = "No fee data. Go to settings to opt in to Esplora use."
        }
        
        return etaCell
    }
    
    private func transactionLabelCell(_ indexPath: IndexPath) -> UITableViewCell {
        let labelCell = verifyTable.dequeueReusableCell(withIdentifier: "memoLabelCell", for: indexPath)
        configureCell(labelCell)
        let label = labelCell.viewWithTag(1) as! UILabel
        let button = labelCell.viewWithTag(2) as! UIButton
        button.addTarget(self, action: #selector(updateLabelMemoAction), for: .touchUpInside)
        button.showsTouchWhenHighlighted = true
        label.text = labelText
        return labelCell
    }
    
    private func transactionMemoCell(_ indexPath: IndexPath) -> UITableViewCell {
        let labelCell = verifyTable.dequeueReusableCell(withIdentifier: "memoLabelCell", for: indexPath)
        configureCell(labelCell)
        let label = labelCell.viewWithTag(1) as! UILabel
        let button = labelCell.viewWithTag(2) as! UIButton
        button.addTarget(self, action: #selector(updateLabelMemoAction), for: .touchUpInside)
        button.showsTouchWhenHighlighted = true
        label.text = memoText
        return labelCell
    }
    
    @objc func verifyOwner(_ sender: UIButton) {
        guard let id = sender.restorationIdentifier else { return }
        let arr = id.split(separator: " ")
        let address = "\(arr[0])"
        guard let index = Int(arr[1]) else { return }
                
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let alert = UIAlertController(title: "Verify Owner", message: "This address does not belong to the current Active Wallet, you can run this check to see if any of your other wallets are the owner.", preferredStyle: self.alertStyle)
            
            alert.addAction(UIAlertAction(title: "Verify Owner", style: .default, handler: { action in
                self.spinner.addConnectingView(vc: self, description: "checking other FN wallets...")
                self.getBitcoinCoreWallets(address, index)
            }))
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { action in }))
            alert.popoverPresentationController?.sourceView = self.view
            self.present(alert, animated: true) {}
        }
    }
    
    private func checkEachWallet(_ address: String, _ walletsToCheck: [String], _ int: Int) {
        var updatedOutput = outputArray[int]
        
        func resetActiveWallet() {
            UserDefaults.standard.set(self.wallet!.name, forKey: "walletName")
        }
        
        if walletIndex < walletsToCheck.count {
            let wallet = walletsToCheck[walletIndex]
            UserDefaults.standard.set(wallet, forKey: "walletName")
            
            Reducer.makeCommand(command: .getaddressinfo, param: "\"\(address)\"") { [weak self] (response, errorMessage) in
                guard let self = self else { resetActiveWallet(); return }
                
                if let dict = response as? NSDictionary, let solvable = dict["solvable"] as? Bool, solvable {
                    let keypath = dict["hdkeypath"] as? String ?? "no key path"
                    let labels = dict["labels"] as? NSArray ?? ["no label"]
                    let desc = dict["desc"] as? String ?? "no descriptor"
                    var isChange = dict["ischange"] as? Bool ?? false
                    let fingerprint = dict["hdmasterfingerprint"] as? String ?? "no fingerprint"
                    var labelsText = ""
                    
                    if labels.count > 0 {
                        for label in labels {
                            if label as? String == "" {
                                labelsText += "no label "
                            } else {
                                labelsText += "\(label as? String ?? "") "
                            }
                        }
                    } else {
                        labelsText += "no label "
                    }
                    
                    if desc.contains("/1/") {
                        isChange = true
                    }
                    updatedOutput["isOursBitcoind"] = solvable
                    updatedOutput["hdKeyPath"] = keypath
                    updatedOutput["isChange"] = isChange
                    updatedOutput["label"] = labelsText
                    updatedOutput["fingerprint"] = fingerprint
                    updatedOutput["desc"] = desc
                    
                    // Currently only verify address if the node knows about it.. otherwise we have to brute force 200k addresses...
                    // will add a dedicated verify button for unsolvable to cross check against all wallets
                    // also adding a signer verify button to show whether FN is able to sign for the output or not
                    
                    Keys.verifyAddress(address, keypath, desc) {(isOursFullyNoded, walletLabel, signable, signer) in
                        updatedOutput["isOursFullyNoded"] = isOursFullyNoded
                        updatedOutput["walletLabel"] = walletLabel
                        updatedOutput["signable"] = signable
                        updatedOutput["signerLabel"] = signer
                        
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            
                            resetActiveWallet()
                            self.outputArray[int] = updatedOutput
                            self.verifyTable.reloadData()
                            self.spinner.removeConnectingView()
                            showAlert(vc: self, title: "", message: "Owned by \(walletLabel ?? "Bitcoin Core") ✓")
                        }
                        
                        return
                    }
                } else {
                    self.walletIndex += 1
                    self.checkEachWallet(address, walletsToCheck, int)
                }
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                resetActiveWallet()
                self.verifyTable.reloadData()
                self.spinner.removeConnectingView()
                showAlert(vc: self, title: "", message: "Address not owned by any of the FN Wallets associated with this node.")
            }
        }
    }
    
    private func getFullyNodedWallets(_ address: String,_ int: Int) {
        var walletsToCheck = [String]()
        CoreDataService.retrieveEntity(entityName: .wallets) { [weak self] wallets in
            guard let self = self else { return }
            
            guard let wallets = wallets, wallets.count > 0, let activeWallet = self.wallet else { return }
            
            for (i, wallet) in wallets.enumerated() {
                let walletStruct = Wallet(dictionary: wallet)
                
            if activeWallet.id != walletStruct.id {
                    for (b, bitcoinCoreWallet) in self.bitcoinCoreWallets.enumerated() {
                        if bitcoinCoreWallet == walletStruct.name {
                            walletsToCheck.append(walletStruct.name)
                        }
                        if b + 1 == self.bitcoinCoreWallets.count {
                            if i + 1 == wallets.count {
                                self.checkEachWallet(address, walletsToCheck, int)
                            }
                        }
                    }
                } else if i + 1 == wallets.count {
                    self.checkEachWallet(address, walletsToCheck, int)
                }
            }
        }
    }
    
    func getBitcoinCoreWallets(_ address: String, _ int: Int) {
        bitcoinCoreWallets.removeAll()
        Reducer.makeCommand(command: .listwalletdir, param: "") { [weak self] (response, errorMessage) in
            guard let self = self else { return }
            
            guard let dict = response as? NSDictionary else {
                DispatchQueue.main.async {
                    self.spinner.removeConnectingView()
                    displayAlert(viewController: self, isError: true, message: "error getting wallets: \(errorMessage ?? "")")
                }
                return
            }
            
            self.parseWallets(dict, address, int)
        }
    }
    
    private func parseWallets(_ walletDict: NSDictionary, _ address: String, _ int: Int) {
        guard let walletArr = walletDict["wallets"] as? NSArray else { return }
        
        for (i, wallet) in walletArr.enumerated() {
            guard let walletDict = wallet as? NSDictionary, let walletName = walletDict["name"] as? String else {
                    return
            }
            
            bitcoinCoreWallets.append(walletName)
            
            if i + 1 == walletArr.count {
                getFullyNodedWallets(address, int)
            }
        }
    }
    
    @objc func copyAddress(_ sender: UIButton) {
        UIPasteboard.general.string = sender.restorationIdentifier
        
        showAlert(vc: self, title: "", message: "Address copied ✓")
    }
    
    @objc func copyDesc(_ sender: UIButton) {
        UIPasteboard.general.string = sender.restorationIdentifier
        
        showAlert(vc: self, title: "", message: "Descriptor copied ✓")
    }
    
    private func loadLabelAndMemo() {
        CoreDataService.retrieveEntity(entityName: .transactions) { [weak self] transactions in
            guard let self = self else { return }
            
            guard let transactions = transactions, transactions.count > 0 else {
                self.saveNewTx(self.txid)
                return
            }
            
            var alreadySaved = false
            
            for (i, transaction) in transactions.enumerated() {
                let txStruct = TransactionStruct(dictionary: transaction)
                if txStruct.txid == self.txid {
                    alreadySaved = true
                    self.id = txStruct.id!
                    self.labelText = txStruct.label
                    self.memoText = txStruct.memo
                }
                
                if i + 1 == transactions.count && !alreadySaved {
                    self.saveNewTx(self.txid)
                }
            }
        }
    }
    
    @objc func updateLabelMemoAction() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.performSegue(withIdentifier: "segueToTxLabelMemo", sender: self)
        }
    }
    
    private func configureView(_ view: UIView) {
        view.clipsToBounds = true
        view.layer.cornerRadius = 8
        view.layer.borderColor = UIColor.lightGray.cgColor
        view.layer.borderWidth = 0.5
    }
    
    private func configureCell(_ cell: UITableViewCell) {
        cell.selectionStyle = .none
        configureView(cell)
    }
    
    private func satsPerByte() -> Double {
        let satsPerByte = (txFee * 100000000.0) / Double(txSize)
        return Double(round(10*satsPerByte)/10)
    }
    
    private func feeTarget() -> Int {
        let ud = UserDefaults.standard
        return ud.object(forKey: "feeTarget") as? Int ?? 432
    }
    
    private func eta() -> String {
        var eta = ""
        let seconds = ((feeTarget() * 10) * 60)
        
        if seconds < 86400 {
            
            if seconds < 3600 {
                eta = "\(seconds / 60) minutes"
                
            } else {
                eta = "\(seconds / 3600) hours"
            }
            
        } else {
            eta = "\(seconds / 86400) days"
        }
        
        let todaysDate = Date()
        let futureDate = Date(timeInterval: Double(seconds), since: todaysDate)
        eta += " on \(formattedDate(date: futureDate))"
        return eta
    }
    
    private func formattedDate(date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MMM-dd hh:mm"
        let strDate = dateFormatter.string(from: date)
        return strDate
    }
    
    private func broadcastPrivately() {
        spinner.addConnectingView(vc: self, description: "broadcasting...")
        
        Broadcaster.sharedInstance.send(rawTx: self.signedRawTx) { [weak self] id in
            guard let self = self else { return }
            
            if id == self.txid {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .refreshWallet, object: nil, userInfo: nil)
                    self.disableSendButton()
                    self.spinner.removeConnectingView()
                    showAlert(vc: self, title: "", message: "Transaction sent ✓")
                }
            } else {
                self.showError(error: "Error broadcasting privately, try again and use your node instead. Error: \(id ?? "unknown")")
            }
        }
    }
    
    private func broadcastWithMyNode() {
        spinner.addConnectingView(vc: self, description: "broadcasting...")
        
        Reducer.makeCommand(command: .sendrawtransaction, param: "\"\(self.signedRawTx)\"") { [weak self] (response, errorMesage) in
            guard let self = self else { return }
            
            guard let id = response as? String else {
                self.showError(error: "Error broadcasting: \(errorMesage ?? "unknown error")")
                return
            }
            
            DispatchQueue.main.async {
                if self.txid == id {
                    NotificationCenter.default.post(name: .refreshWallet, object: nil, userInfo: nil)
                    self.disableSendButton()
                    self.spinner.removeConnectingView()
                    showAlert(vc: self, title: "", message: "Transaction sent ✓")
                } else {
                    self.spinner.removeConnectingView()
                    showAlert(vc: self, title: "Hmmm we got a strange response...", message: id)
                }
            }
        }
    }
    
    private func broadcast() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let alert = UIAlertController(title: "Broadcast with your node?", message: "You can optionally broadcast this transaction using Blockstream's esplora API over Tor V3 for improved privacy.", preferredStyle: self.alertStyle)
            
            alert.addAction(UIAlertAction(title: "Privately", style: .default, handler: { action in
                self.broadcastPrivately()
            }))
            
            alert.addAction(UIAlertAction(title: "Use my node", style: .default, handler: { action in
                self.broadcastWithMyNode()
            }))
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { action in }))
            alert.popoverPresentationController?.sourceView = self.view
            self.present(alert, animated: true) {}
        }
    }
    
    private func showError(error: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.spinner.removeConnectingView()
            showAlert(vc: self, title: "Uh oh", message: error)
        }
    }
    
    @objc func copyTxid() {
        DispatchQueue.main.async { [unowned vc = self] in
            let pasteBoard = UIPasteboard.general
            pasteBoard.string = vc.txid
            displayAlert(viewController: vc, isError: false, message: "Transaction ID copied to clipboard")
        }
    }
        
    func textFieldDidEndEditing(_ textField: UITextField) {
        if textField.text != "" {
            memo = textField.text!
        }
    }
    
    private func exportPsbt(psbt: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let alert = UIAlertController(title: "Share as a .psbt file, text or QR?", message: "Sharing as a .psbt file allows you to send the psbt directly to your Coldcard or to Electrum 4.0 for signing", preferredStyle: self.alertStyle)
            
            alert.addAction(UIAlertAction(title: ".psbt file", style: .default, handler: { action in
                self.convertPSBTtoData(string: psbt)
            }))
            
            alert.addAction(UIAlertAction(title: "Text", style: .default, handler: { action in
                self.shareText(psbt)
            }))
            
            alert.addAction(UIAlertAction(title: "QR", style: .default, handler: { action in
                self.unsignedPsbt = psbt
                self.exportAsQR()
            }))
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { action in }))
            alert.popoverPresentationController?.sourceView = self.view
            self.present(alert, animated: true) {}
        }
    }
    
    private func exportAsQR() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.performSegue(withIdentifier: "segueToExportPsbtAsQr", sender: self)
        }
    }
    
    private func shareText(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let activityViewController = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            
            if UIDevice.current.userInterfaceIdiom == .pad {
                activityViewController.popoverPresentationController?.sourceView = self.view
                activityViewController.popoverPresentationController?.sourceRect = CGRect(x: 0, y: 0, width: 100, height: 100)
            }
            
            self.present(activityViewController, animated: true) {}
        }
    }
    
    private func exportTxn(txn: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let alert = UIAlertController(title: "Export as text or QR?", message: "", preferredStyle: self.alertStyle)
            
            alert.addAction(UIAlertAction(title: "Text", style: .default, handler: { action in
                self.shareText(txn)
            }))
            
            alert.addAction(UIAlertAction(title: "QR", style: .default, handler: { action in
                self.exportAsQR()
            }))
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { action in }))
            alert.popoverPresentationController?.sourceView = self.view
            self.present(alert, animated: true) {}
        }
    }
    
    private func convertPSBTtoData(string: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let data = Data(base64Encoded: string) else { return }
            
            var label = self.labelText
            
            if label == "" {
                label = "FullyNoded"
            }
                        
            let fileManager = FileManager.default
            let fileURL = fileManager.temporaryDirectory.appendingPathComponent("\(label).psbt")
            
            try? data.write(to: fileURL)
            
            let controller = UIDocumentPickerViewController(url: fileURL, in: .exportToService)
            self.present(controller, animated: true)
        }
    }
    
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
        if segue.identifier == "segueToExportPsbtAsQr" {
            
            if let vc = segue.destination as? QRDisplayerViewController {
                
                if unsignedPsbt != "" {
                    vc.psbt = unsignedPsbt
                    vc.headerIcon = UIImage(systemName: "square.and.arrow.up")
                    vc.headerText = "PSBT"
                    vc.descriptionText = "This psbt still needs more signatures to be complete, you can share it with another signer."
                    
                } else if signedRawTx != "" {
                    vc.text = signedRawTx
                    vc.headerIcon = UIImage(systemName: "square.and.arrow.up")
                    vc.headerText = "Signed Transaction"
                    vc.descriptionText = "You can save this signed transaction and broadcast it later or share it with someone else."
                    
                }
            }
        }
        
        if segue.identifier == "segueToTxLabelMemo" {
            if let vc = segue.destination as? TransactionLabelMemoViewController {
                vc.txid = self.txid
                vc.labelText = labelText
                vc.memoText = memoText
                vc.doneBlock = { result in
                    self.labelText = result[0]
                    self.memoText = result[1]
                    
                    DispatchQueue.main.async {
                        self.verifyTable.reloadSections(IndexSet(arrayLiteral: 0, 1), with: .none)
                        showAlert(vc: self, title: "", message: "Transaction updated ✓")
                    }
                }
            }
        }
        
        if segue.identifier == "segueToScanPsbt" {
            guard let vc = segue.destination as? QRScannerViewController else { return }
            
            vc.fromSignAndVerify = true
            vc.onAddressDoneBlock = { [weak self] tx in
                guard let self = self, let tx = tx else { return }
                
                if Keys.validPsbt(tx) {
                    self.processPsbt(tx)
                } else if Keys.validTx(tx) {
                    self.signedRawTx = tx
                    self.load()
                }
            }
        }
    }
}

extension VerifyTransactionViewController: UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        if unsignedPsbt == "" && signedRawTx == "" {
            return 1
        } else {
            return 8
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if unsignedPsbt == "" && signedRawTx == "" {
            return 1
        } else {
            switch section {
            case 4:
                return inputArray.count
                
            case 5:
                return outputArray.count
                
            case 0, 3, 1, 6, 2, 7:
                return 1
                
            default:
                return 0
            }
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch indexPath.section {
        case 4:
            return 441
            
        case 5:
            return 522
        
        case 1:
            return 150
            
        case 0, 2:
            return 50
            
        case 3, 6, 7:
            return 80
            
        default:
            return 0
            
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard inputTableArray.count > 0 && outputArray.count > 0 else {
            return defaultCell(indexPath)
        }
        
        tableView.separatorColor = .lightGray
        
        switch indexPath.section {
            
        case 0:
            return transactionLabelCell(indexPath)
            
        case 1:
            return transactionMemoCell(indexPath)
            
        case 2:
            if !alreadyBroadcast {
                return mempoolAcceptCell(indexPath)
            } else {
                return confsCell(indexPath)
            }
            
        case 3:
            return txidCell(indexPath)
            
        case 4:
            return inputCell(indexPath)
            
        case 5:
            return outputCell(indexPath)
            
        case 6:
            return miningFeeCell(indexPath)
            
        case 7:
            return etaCell(indexPath)
            
        default:
            return UITableViewCell()
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
                
        let header = UIView()
        header.backgroundColor = UIColor.clear
        header.frame = CGRect(x: 0, y: 0, width: view.frame.size.width - 32, height: 50)
        
        let textLabel = UILabel()
        textLabel.textAlignment = .left
        textLabel.font = UIFont.systemFont(ofSize: 20, weight: .regular)
        textLabel.textColor = .white
        textLabel.frame = CGRect(x: 0, y: 0, width: 300, height: 50)
        
        if unsignedPsbt == "" && signedRawTx == "" {
            textLabel.text = ""
        } else {
            switch section {
            case 0:
                textLabel.text = "Label"
                textLabel.frame = CGRect(x: 0, y: 0, width: 300, height: 50)
            
            case 1:
                textLabel.text = "Memo"
                textLabel.frame = CGRect(x: 0, y: 0, width: 300, height: 50)
                
            case 2:
                if !alreadyBroadcast {
                    textLabel.text = "Mempool accept"
                } else {
                    textLabel.text = "Confirmations"
                }
                textLabel.frame = CGRect(x: 0, y: 0, width: 300, height: 50)
                
            case 3:
                textLabel.text = "Transaction ID"
                let copyButton = UIButton()
                let copyImage = UIImage(systemName: "doc.on.doc")!
                copyButton.tintColor = .systemTeal
                copyButton.setImage(copyImage, for: .normal)
                copyButton.addTarget(self, action: #selector(copyTxid), for: .touchUpInside)
                copyButton.frame = CGRect(x: header.frame.maxX - 70, y: 0, width: 50, height: 50)
                copyButton.center.y = textLabel.center.y
                copyButton.showsTouchWhenHighlighted = true
                header.addSubview(copyButton)
                                
            case 4:
                textLabel.text = "Inputs"
                textLabel.frame = CGRect(x: 0, y: 0, width: 300, height: 50)
                                
            case 5:
                textLabel.text = "Outputs"
                textLabel.frame = CGRect(x: 0, y: 0, width: 300, height: 50)
                
            case 6:
                textLabel.text = "Mining fee"
                textLabel.frame = CGRect(x: 0, y: 0, width: 300, height: 50)
            
            case 7:
                textLabel.text = "Estimated time to confirm"
                textLabel.frame = CGRect(x: 0, y: 0, width: 300, height: 50)
                                
            default:
                break
            }
        }
        
        header.addSubview(textLabel)
        return header
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 50
    }
}

extension VerifyTransactionViewController: UITableViewDataSource {
    
}
