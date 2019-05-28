//
//  LibWallyTests.swift
//  LibWallyTests
//
//  Created by Sjors on 27/05/2019.
//  Copyright © 2019 Blockchain. Distributed under the MIT software
//  license, see the accompanying file LICENSE.md.
//

import XCTest
@testable import LibWally

class LibWallyTests: XCTestCase {
    let validMnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testGetBIP39WordList() {
        // Check length
        XCTAssertEqual(BIP39Words.count, 2048)
        
        // Check first word
        XCTAssertEqual(BIP39Words.first, "abandon")
    }
    
    func testMnemonicIsValid() {
        XCTAssertTrue(BIP39Mnemonic.isValid(validMnemonic))
        XCTAssertFalse(BIP39Mnemonic.isValid("notavalidword"))
        XCTAssertFalse(BIP39Mnemonic.isValid("abandon"))
        XCTAssertFalse(BIP39Mnemonic.isValid(["abandon", "abandon"]))
    }
    
    func testInitializeMnemonic() {
        let mnemonic = BIP39Mnemonic(validMnemonic)
        XCTAssertNotNil(mnemonic)
        if (mnemonic != nil) {
            XCTAssertEqual(mnemonic!.words, validMnemonic.components(separatedBy: " "))
        }
    }
    
    func testInitializeInvalidMnemonic() {
        let mnemonic = BIP39Mnemonic(["notavalidword"])
        XCTAssertNil(mnemonic)
    }
    
    func testMnemonicLosslessStringConvertible() {
        let mnemonic = BIP39Mnemonic(validMnemonic)
        XCTAssertEqual(mnemonic!.description, validMnemonic)
    }
    
    func testMnemonicToEntropy() {
        let mnemonic = BIP39Mnemonic(validMnemonic)
        XCTAssertEqual(mnemonic!.entropy.description, "00000000000000000000000000000000")
        let mnemonic2 = BIP39Mnemonic("legal winner thank year wave sausage worth useful legal winner thank yellow")
        XCTAssertEqual(mnemonic2!.entropy.description, "7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f")
    }
    
    func testEntropyToMnemonic() {
        let expectedMnemonic = BIP39Mnemonic("legal winner thank year wave sausage worth useful legal winner thank yellow")
        let entropy = BIP39Entropy("7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f")
        let mnemonic = BIP39Mnemonic(entropy!)
        XCTAssertEqual(mnemonic, expectedMnemonic)
    }
    
    
    func testEntropyLosslessStringConvertible() {
        let entropy = BIP39Entropy("7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f")
        XCTAssertEqual(entropy!.description, "7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f")
    }
    
    func testMnemonicToSeedHexString() {
        let mnemonic = BIP39Mnemonic(validMnemonic)
        XCTAssertEqual(mnemonic!.seedHex("TREZOR").description, "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04")
        XCTAssertEqual(mnemonic!.seedHex().description, "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4")
        XCTAssertEqual(mnemonic!.seedHex("").description, "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4")
    }
    
    func testBIP39SeedLosslessStringConvertible() {
        let mnemonic = BIP39Mnemonic(validMnemonic)
        let expectedBIP39Seed = mnemonic!.seedHex("TREZOR")
        let parsedBIP39Seed = BIP39Seed("c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04")
        XCTAssertEqual(parsedBIP39Seed, expectedBIP39Seed)
    }


}
