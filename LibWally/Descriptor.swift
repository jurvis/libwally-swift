//
//  Descriptor.swift
//  Descriptor
//
//  Created by Sjors Provoost on 24/01/2022.
//  Copyright © 2022 Sjors Provoost. Distributed under the MIT software
//  license, see the accompanying file LICENSE.md

import Foundation
import CLibWally

public enum DescriptorError: Error {
    case invalid
    case noAddress // There is no address representation, e.g. pk()
    case missingChecksum
    case notRanged // No index should be used for getAddress() when called on a non-ranged descriptor
    case ranged // Index must be used for getAddress() when called on a ranged descriptor
}


public struct Descriptor {
    // The descriptor string we were initialized with. Not normalized and not fully validated.
    var raw_descriptor: String
    public var network: Network
    public var canonical: String
    
    // The descriptor is not fully validated.
    public init(_ descriptor: String, _ network: Network) throws {
        self.raw_descriptor = descriptor
        self.network = network
        
        // Insist on a checksum (we assume any inappropriate use of # is caught in wally_descriptor_canonicalize)
        if descriptor.firstIndex(of: "#") == nil {
            throw DescriptorError.missingChecksum
        }
        
        // Canonicalize the descriptor, which also partially validates the input.
        var output: UnsafeMutablePointer<Int8>?
        defer {
            wally_free_string(output)
        }
        if (wally_descriptor_canonicalize(descriptor, nil, 0, &output) != WALLY_OK) {
            throw DescriptorError.invalid
        } else {
            precondition(output != nil)
            self.canonical = String(cString: output!)
        }
    }
    
    // May throw if something is wrong with the descriptor.
    // Will throw if descriptor can't be expressed as an address, e.g. pk().
    public func getAddress(_ index: UInt32) throws -> Address {
        if index != 0 && self.raw_descriptor.firstIndex(of: "*") == nil {
            throw DescriptorError.notRanged
        }
        
        var output: UnsafeMutablePointer<Int8>?
        defer {
            wally_free_string(output)
        }

        let result = wally_descriptor_to_address(self.raw_descriptor, nil, index, UInt32(network == .mainnet ? WALLY_NETWORK_BITCOIN_MAINNET : WALLY_NETWORK_BITCOIN_TESTNET), 0, &output)
        
        if result != WALLY_OK {
            throw DescriptorError.invalid
        }

        precondition(output != nil)
        if let address = Address(String(cString: output!)) {
            return address
        } else {
            // This code is not reached for pk() descriptors, because wally_descriptor_to_address will fail
            // TODO: catch descriptors that can't be expressed as an address earlier and explictly
            throw DescriptorError.noAddress
        }
    }
    
    public func getAddress() throws -> Address {
        if self.raw_descriptor.firstIndex(of: "*") != nil {
            throw DescriptorError.ranged
        }
        return try getAddress(0)
    }

}
