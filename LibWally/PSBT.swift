//
//  PSBT.swift
//  PSBT
//
//  Created by Sjors Provoost on 16/12/2019.
//  Copyright © 2019 Sjors Provoost. Distributed under the MIT software
//  license, see the accompanying file LICENSE.md

import Foundation
@_implementationOnly import CLibWally

public struct KeyOrigin : Equatable {
    let fingerprint: Data
    let path: String
}

func getOrigins (keypaths: wally_map, network: Network) -> [PubKey: KeyOrigin] {
    var origins: [PubKey: KeyOrigin] = [:]
    for i in 0..<keypaths.num_items {
        // TOOD: simplify after https://github.com/ElementsProject/libwally-core/issues/241
        let item: wally_map_item = keypaths.items[i]

        let pubKey = PubKey(Data(bytes: item.key, count: Int(EC_PUBLIC_KEY_LEN)), network)!
        // The value contains a 4 byte fingerprint followed by the path
        let fingerprint = Data(bytes: item.value, count: Int(BIP32_KEY_FINGERPRINT_LEN))
        let keyPath = Data(bytes: item.value + Int(BIP32_KEY_FINGERPRINT_LEN), count: Int(item.value_len) - Int(BIP32_KEY_FINGERPRINT_LEN))

        var components: [UInt32] = []
        // Each path component is stored as a little endian 32 bit unsigned integer
        for j in 0..<keyPath.count / 4 {
            let pathComponentBytes = keyPath.subdata(in: (j * 4)..<((j + 1) * 4))
            let pathComponent: UInt32 = pathComponentBytes.withUnsafeBytes{ $0.load(as: UInt32.self).littleEndian}
            components.append(pathComponent)
        }
        let path: String = "m/" + components.map { $0 < BIP32_INITIAL_HARDENED_CHILD ? String($0) : String($0 - BIP32_INITIAL_HARDENED_CHILD) + "'" }.joined(separator: "/")
        origins[pubKey] = KeyOrigin(fingerprint: fingerprint, path: path)
    }
    return origins
}

public struct PSBTInput {
    let wally_psbt_input: wally_psbt_input
    public let origins: [PubKey: KeyOrigin]?

    init(_ wally_psbt_input: wally_psbt_input, network: Network) {
        self.wally_psbt_input = wally_psbt_input
        if (wally_psbt_input.keypaths.num_items > 0) {
            self.origins = getOrigins(keypaths: wally_psbt_input.keypaths, network: network)
        } else {
            self.origins = nil
        }
    }

    // Can we provide at least one signature, assuming we have the private key?
    public func canSign(_ hdKey: HDKey) -> [PubKey: KeyOrigin]? {
        var result: [PubKey: KeyOrigin] = [:]
        if let origins = self.origins {
            for origin in origins {
                guard let masterKeyFingerprint = hdKey.masterKeyFingerprint else {
                    break
                }
                if masterKeyFingerprint == origin.value.fingerprint {
                    if let childKey = try? hdKey.derive(origin.value.path) {
                        if childKey.pubKey == origin.key {
                            result[origin.key] = origin.value
                        }
                    }
                }
            }
        }
        if result.count == 0 { return nil }
        return result
    }

    public func canSign(_ hdKey: HDKey) -> Bool {
        return canSign(hdKey) != nil
    }

    public var isSegWit: Bool {
        return self.wally_psbt_input.witness_utxo != nil
    }

    public var amount: Satoshi? {
        if let witness_utxo = self.wally_psbt_input.witness_utxo {
            return witness_utxo.pointee.satoshi
        }
        return nil
    }
}

public struct PSBTOutput : Identifiable {
    let wally_psbt_output: wally_psbt_output
    public let txOutput: TxOutput
    public let origins: [PubKey: KeyOrigin]?

    public var id: String {
        return self.txOutput.scriptPubKey.bytes.hexString + String(self.txOutput.amount)
    }

    init(_ wally_psbt_outputs: UnsafeMutablePointer<wally_psbt_output>, tx: wally_tx, index: Int, network: Network) {
        precondition(index >= 0 && index < tx.num_outputs)
        precondition(tx.num_outputs != 0 )
        self.wally_psbt_output = wally_psbt_outputs[index]
        if (wally_psbt_output.keypaths.num_items > 0) {
            self.origins = getOrigins(keypaths: wally_psbt_output.keypaths, network: network)
        } else {
            self.origins = nil
        }
        let output = tx.outputs![index]
        let scriptPubKey: ScriptPubKey
        if let scriptPubKeyBytes = self.wally_psbt_output.witness_script {
            scriptPubKey = ScriptPubKey(Data(bytes: scriptPubKeyBytes, count: self.wally_psbt_output.witness_script_len))
        } else {
            scriptPubKey = ScriptPubKey(Data(bytes: output.script, count: output.script_len))
        }

        self.txOutput = TxOutput(tx_output: output, scriptPubKey: scriptPubKey, network: network)
    }

    static func commonOriginChecks(origin: KeyOrigin, rootPathLength: Int, pubKey: PubKey, signer: HDKey, cosigners: [HDKey]) ->  Bool {
        // Check that origin ends with /0/* or /1/*
        if origin.path.range(of: #"\/[01]\/\d+$"#, options: .regularExpression) == nil { return false }

        // Find matching HDKey
        var hdKey: HDKey? = nil
        guard let signerMasterKeyFingerprint = signer.masterKeyFingerprint else {
            return false
        }
        if (signerMasterKeyFingerprint == origin.fingerprint) {
            hdKey = signer
        } else {
            for cosigner in cosigners {
                guard let cosignerMasterKeyFingerprint = cosigner.masterKeyFingerprint else {
                    return false
                }
                if (cosignerMasterKeyFingerprint == origin.fingerprint) {
                    hdKey = cosigner
                }
            }
        }

        guard hdKey != nil else {
            return false
        }

        // Check that origin pubkey is correct
        guard let childKey = try? hdKey!.derive(origin.path) else {
            return false
        }

        if childKey.pubKey != pubKey {
            return false
        }

        return true
    }

    public func isChange(signer: HDKey, inputs:[PSBTInput], cosigners: [HDKey], threshold: UInt) -> Bool {
        // Transaction must have at least one input
        if inputs.count < 1 {
            return false
        }

        // All inputs must have origin info
        for input in inputs {
            if input.origins == nil {
                return false
            }
        }

        // Skip key deriviation root
        let keyPath = inputs[0].origins!.first!.value.path.split(separator: "/")
        if (keyPath.count < 2) {
            return false
        }
        let keyPathRootLength = keyPath.count - 2

        for input in inputs {
            // Check that we can sign all inputs (TODO: relax assumption for e.g. coinjoin)
            if !input.canSign(signer) {
                return false
            }
            guard let origins = input.origins else {
                return false
            }

            for origin in origins {
                if !(PSBTOutput.commonOriginChecks(origin: origin.value, rootPathLength:keyPathRootLength, pubKey: origin.key, signer: signer, cosigners: cosigners)) {
                    return false
                }
            }
        }

        // Check outputs
        guard let origins = self.origins else {
            return false
        }

        var changeIndex: UInt32? = nil
        for origin in origins {
            if !(PSBTOutput.commonOriginChecks(origin: origin.value, rootPathLength:keyPathRootLength, pubKey: origin.key, signer: signer, cosigners: cosigners)) {
                return false
            }
            // Check that the output index is reasonable
            // When combined with the above constraints, change "hijacked" to an extreme index can
            // be covered by importing keys using Bitcoin Core's maximum range [0,999999].
            // This needs less than 1 GB of RAM, but is fairly slow.
            let i = UInt32(origin.value.path.split(separator: "/").last!)
            guard i != nil else { return false }
            if i! > 999999 {
                return false
            }
            // Change index must be the same for all origins
            if changeIndex != nil && i != changeIndex! {
                return false
            } else {
                changeIndex = i
            }
        }

        // Check scriptPubKey
        switch self.txOutput.scriptPubKey.type {
        case .multiSig:


            let expectedScriptPubKey = ScriptPubKey(multisig: Array(origins.keys), threshold: threshold)
            if self.txOutput.scriptPubKey != expectedScriptPubKey {
                return false
            }
        default:
            return false
        }
        return true
    }
}

public struct PSBT : Equatable {
    public static func == (lhs: PSBT, rhs: PSBT) -> Bool {
        lhs.network == rhs.network && lhs.data == rhs.data
    }


    enum ParseError: Error {
        case tooShort
        case invalidBase64
        case invalid
    }

    public let network: Network
    public let inputs: [PSBTInput]
    public let outputs: [PSBTOutput]

    let wally_psbt: wally_psbt

    public init (_ psbt: Data, _ network: Network) throws {
        self.network = network
        let psbt_bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: psbt.count)
        let psbt_bytes_len = psbt.count
        psbt.copyBytes(to: psbt_bytes, count: psbt_bytes_len)
        var output: UnsafeMutablePointer<wally_psbt>?
        defer {
            if let wally_psbt = output {
                wally_psbt.deallocate()
            }
        }
        guard wally_psbt_from_bytes(psbt_bytes, psbt_bytes_len, &output) == WALLY_OK else {
            // libwally-core returns WALLY_EINVAL regardless of why parsing fails
            throw ParseError.invalid
        }
        precondition(output != nil)
        precondition(output!.pointee.tx != nil)
        self.wally_psbt = output!.pointee
        var inputs: [PSBTInput] = []
        for i in 0..<self.wally_psbt.inputs_allocation_len {
            inputs.append(PSBTInput(self.wally_psbt.inputs![i], network: network))
        }
        self.inputs = inputs
        var outputs: [PSBTOutput] = []
        for i in 0..<self.wally_psbt.outputs_allocation_len {
            outputs.append(PSBTOutput(self.wally_psbt.outputs, tx: self.wally_psbt.tx!.pointee, index: i, network: network))
        }
        self.outputs = outputs
    }

    public init (_ psbt: String, _ network: Network) throws {
        guard psbt.count != 0 else {
            throw ParseError.tooShort
        }

        guard let psbtData = Data(base64Encoded:psbt) else {
            throw ParseError.invalidBase64
        }

        try self.init(psbtData, network)
    }

    public var data: Data {
        let psbt = UnsafeMutablePointer<wally_psbt>.allocate(capacity: 1)
        psbt.initialize(to: self.wally_psbt)
        let len = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        precondition(wally_psbt_get_length(psbt, 0, len) == WALLY_OK)
        let bytes_out = UnsafeMutablePointer<UInt8>.allocate(capacity: len.pointee)
        let written = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        defer {
            psbt.deallocate()
            bytes_out.deallocate()
            written.deallocate()
        }
        precondition(wally_psbt_to_bytes(psbt, 0, bytes_out, len.pointee, written) == WALLY_OK)
        return Data(bytes: bytes_out, count: written.pointee)
    }

    public var description: String {
        return data.base64EncodedString()
    }

    public var complete: Bool {
        // TODO: add function to libwally-core to check this directly
        return self.transactionFinal != nil
    }

    public var transaction: Transaction {
        precondition(self.wally_psbt.tx != nil)
        return Transaction(self.wally_psbt.tx!.pointee)
    }

    public var fee: Satoshi? {
        if let valueOut = self.transaction.totalOut {
            var tally: Satoshi = 0
            for input in self.inputs {
                guard input.isSegWit else {
                    return nil
                }
                guard let amount = input.amount else {
                    return nil
                }
                tally += amount
            }
            precondition(tally >= valueOut)
            return tally - valueOut
        }
        return nil
    }

    public var transactionFinal: Transaction? {
        let psbt = UnsafeMutablePointer<wally_psbt>.allocate(capacity: 1)
        psbt.initialize(to: self.wally_psbt)
        var output: UnsafeMutablePointer<wally_tx>?
        defer {
            psbt.deallocate()
            if let wally_tx = output {
                wally_tx.deallocate()
            }
        }
        guard wally_psbt_extract(psbt, &output) == WALLY_OK else {
            return nil
        }
        precondition(output != nil)
        return Transaction(output!.pointee)
    }

    public mutating func sign(_ privKey: Key) {
        let psbt = UnsafeMutablePointer<wally_psbt>.allocate(capacity: 1)
        psbt.initialize(to: self.wally_psbt)
        let key_bytes = UnsafeMutablePointer<UInt8>.allocate(capacity:Int(EC_PRIVATE_KEY_LEN))
        privKey.data.copyBytes(to: key_bytes, count: Int(EC_PRIVATE_KEY_LEN))
        defer {
           psbt.deallocate()
        }
        // TODO: sanity key for network
        precondition(wally_psbt_sign(psbt, key_bytes, Int(EC_PRIVATE_KEY_LEN), UInt32(EC_FLAG_GRIND_R)) == WALLY_OK)
    }

    public mutating func sign(_ hdKey: HDKey) {
        for input in self.inputs {
            if let origins: [PubKey : KeyOrigin] = input.canSign(hdKey) {
                for origin in origins {
                    if let childKey = try? hdKey.derive(origin.value.path) {
                        if let privKey = childKey.privKey {
                            precondition(privKey.pubKey == origin.key)
                            self.sign(privKey)
                        }
                    }
                }
            }
        }
    }

    public mutating func finalize() -> Bool {
        let psbt = UnsafeMutablePointer<wally_psbt>.allocate(capacity: 1)
        psbt.initialize(to: self.wally_psbt)
        defer {
            psbt.deallocate()
        }
        guard wally_psbt_finalize(psbt) == WALLY_OK else {
            return false
        }
        return true
    }

}
