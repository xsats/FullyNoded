//
//  ImportWallet.swift
//  BitSense
//
//  Created by Peter on 16/07/20.
//  Copyright © 2020 Fontaine. All rights reserved.
//

import Foundation

class ImportWallet {
        
    class func accountMap(_ accountMap: [String:Any], completion: @escaping ((success: Bool, errorDescription: String?)) -> Void) {
        var wallet = [String:Any]()
        var keypool = Bool()
        let descriptorParser = DescriptorParser()
        var primDescriptor = accountMap["descriptor"] as! String
        let blockheight = accountMap["blockheight"] as! Int
        let label = accountMap["label"] as! String
        wallet["label"] = label
        wallet["id"] = UUID()
        wallet["blockheight"] = Int64(blockheight)
        wallet["maxIndex"] = 2500
        wallet["index"] = 0
        let descStruct = descriptorParser.descriptor(primDescriptor)
        if descStruct.isMulti {
            wallet["type"] = "Multi-Sig"
            keypool = false
        } else {
            wallet["type"] = "Single-Sig"
            keypool = true
        }
        primDescriptor = primDescriptor.replacingOccurrences(of: "'", with: "h")
        let arr = primDescriptor.split(separator: "#")
        primDescriptor = "\(arr[0])"
        
        func getDescriptorInfo(desc: String, completion: @escaping ((desc: String?, errorMessage: String?)) -> Void) {
            Reducer.makeCommand(command: .getdescriptorinfo, param: "\"\(desc)\"") { (response, errorMessage) in
                if let dict = response as? NSDictionary {
                    if let updatedDescriptor = dict["descriptor"] as? String {
                        completion((updatedDescriptor, nil))
                    }
                } else {
                    completion((nil, errorMessage ?? "error getting descriptor info"))
                }
            }
        }
        
        func importMulti(params: String, completion: @escaping ((success: Bool, errorMessage: String?)) -> Void) {
            Reducer.makeCommand(command: .importmulti, param: params) { (response, errorDescription) in
                if let result = response as? NSArray {
                    if result.count > 0 {
                        if let dict = result[0] as? NSDictionary {
                            if let success = dict["success"] as? Bool {
                                completion((success, nil))
                            } else {
                                completion((false, errorDescription ?? "unknown error importing your keys"))
                            }
                        }
                    } else {
                        completion((false, errorDescription ?? "unknown error importing your keys"))
                    }
                } else {
                    completion((false, errorDescription ?? "unknown error importing your keys"))
                }
            }
        }
        
        func saveLocally() {
            CoreDataService.saveEntity(dict: wallet, entityName: .wallets) { (success) in
                if success {
                    completion((true, nil))
                } else {
                    completion((false, "error saving wallet locally"))
                }
            }
        }
        
        func rescan() {
            Reducer.makeCommand(command: .getblockchaininfo, param: "") { (response, errorMessage) in
                if let dict = response as? NSDictionary {
                    if let pruned = dict["pruned"] as? Bool {
                        if pruned {
                            if let pruneHeight = dict["pruneheight"] as? Int {
                                Reducer.makeCommand(command: .rescanblockchain, param: "\(pruneHeight)") { (response, errorMessage) in
                                    saveLocally()
                                }
                            } else {
                                completion((false, errorMessage ?? "error getting prune height"))
                            }
                        } else {
                            Reducer.makeCommand(command: .rescanblockchain, param: "") { (response, errorMessage) in
                                saveLocally()
                            }
                        }
                    } else {
                        completion((false, errorMessage ?? "error getting prune info"))
                    }
                } else {
                     completion((false, errorMessage ?? "error getting blockchain info"))
                }
            }
        }
        
        func createWallet(_ recDesc: String, _ changeDesc: String) {
            let walletName = "FullyNoded-Import-\(randomString(length: 10))"
            let param = "\"\(walletName)\", true, true, \"\", true"
            Reducer.makeCommand(command: .createwallet, param: param) { (response, errorMessage) in
                if let dict = response as? NSDictionary {
                    if let name = dict["name"] as? String {
                        wallet["name"] = name
                        UserDefaults.standard.set(name, forKey: "walletName")
                        let recParams = "[{ \"desc\": \"\(recDesc)\", \"timestamp\": \"now\", \"range\": [0,2500], \"watchonly\": true, \"label\": \"\(label)\", \"keypool\": \(keypool), \"internal\": false }], {\"rescan\": false}"
                        importMulti(params: recParams) { (success, errorMessage) in
                            if success {
                                let changeParams = "[{ \"desc\": \"\(changeDesc)\", \"timestamp\": \"now\", \"range\": [0,2500], \"watchonly\": true, \"keypool\": \(keypool), \"internal\": true }], {\"rescan\": false}"
                                importMulti(params: changeParams) { (changeImported, errorMessage) in
                                    if success {
                                        rescan()
                                    } else {
                                        completion((false, errorMessage ?? "error importing change keys"))
                                    }
                                }
                            } else {
                                completion((false, errorMessage ?? "error importing keys"))
                            }
                        }
                    } else {
                        completion((false, errorMessage ?? "error getting wallet name"))
                    }
                } else {
                   completion((false, errorMessage ?? "error creating wallet"))
                }
            }
        }
        
        getDescriptorInfo(desc: primDescriptor) { (recDesc, errorMessage) in
            if recDesc != nil {
                wallet["receiveDescriptor"] = recDesc!
                getDescriptorInfo(desc: primDescriptor.replacingOccurrences(of: "/0/*", with: "/1/*")) { (changeDesc, errorMessage) in
                    if changeDesc != nil {
                        wallet["changeDescriptor"] = changeDesc!
                        createWallet(recDesc!, changeDesc!)
                    } else {
                        completion((false, errorMessage ?? "error getting change descriptor info"))
                    }
                }
            } else {
                completion((false, errorMessage ?? "error getting descriptor info"))
            }
        }
        
    }
    
}