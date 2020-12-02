//
//  AddressParser.swift
//  BitSense
//
//  Created by Peter on 01/05/19.
//  Copyright © 2019 Fontaine. All rights reserved.
//

import Foundation

// bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?amount=50&label=Luke-Jr&message=Donation%20for%20project%20xyz
// bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?amount=20.3&label=Luke-Jr

class AddressParser {
        
    class func parse(url: String) -> (address: String?, amount: Double?, label: String?, message: String?) {
        var addressToReturn:String?
        var amountToReturn:Double?
        var labelToReturn:String?
        var message:String?
        var processedUrl = url
        
        processedUrl = processedUrl.replacingOccurrences(of: "bitcoin:", with: "")
        
        guard processedUrl.contains("?") || processedUrl.contains("=") else {
            return (address: processedAddress(processedUrl), amount: amountToReturn, label: labelToReturn, message: message)
        }
        
        if processedUrl.hasPrefix(" ") {
            processedUrl = processedUrl.replacingOccurrences(of: " ", with: "")
        }
                
        guard processedUrl.contains("?") else {
            return (address: processedAddress(processedUrl), amount: amountToReturn, label: labelToReturn, message: message)
        }
        
        let split = processedUrl.split(separator: "?")
        
        guard split.count > 0 else {
             return (address: processedAddress(processedUrl), amount: amountToReturn, label: labelToReturn, message: message)
        }
        
        let urlParts = split[1].split(separator: "&")
        
        addressToReturn = processedAddress("\(split[0])".replacingOccurrences(of: "bitcoin:", with: ""))
        
        guard urlParts.count > 0 else {
            return (address: addressToReturn, amount: amountToReturn, label: labelToReturn, message: message)
        }
                
        for item in urlParts {
            let string = "\(item)"
            switch string {
            case _ where string.contains("amount"):
                if string.contains("&") {
                    let array = string.split(separator: "&")
                    let amount = array[0].replacingOccurrences(of: "amount=", with: "")
                    amountToReturn = amount.doubleValue
                    
                } else {
                    let amount = string.replacingOccurrences(of: "amount=", with: "")
                    amountToReturn = amount.doubleValue
                    
                }
                
            case _ where string.contains("label="):
                labelToReturn = (string.replacingOccurrences(of: "label=", with: "")).replacingOccurrences(of: "%20", with: " ")
                
            case _ where string.contains("message="):
                message = (string.replacingOccurrences(of: "message=", with: "")).replacingOccurrences(of: "%20", with: " ")
                
            default:
                break
            }
        }
                
        return (address: addressToReturn, amount: amountToReturn, label: labelToReturn, message: message)
    }
    
    private class func processedAddress(_ processed: String) -> String? {
        let address = processed.lowercased().replacingOccurrences(of: "bitcoin:", with: "")
        switch address {
        case _ where address.hasPrefix("1"),
             _ where address.hasPrefix("3"),
             _ where address.hasPrefix("tb1"),
             _ where address.hasPrefix("bc1"),
             _ where address.hasPrefix("2"),
             _ where address.hasPrefix("bcrt"),
             _ where address.hasPrefix("m"),
             _ where address.hasPrefix("n"),
             _ where address.hasPrefix("lntb"):
            return address
        default:
            return nil
        }
    }
    
}
