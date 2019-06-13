//
//  BIP32Tests.swift
//  BIP32Tests 
//
//  Created by Sjors on 29/05/2019.
//  Copyright © 2019 Blockchain. Distributed under the MIT software
//  license, see the accompanying file LICENSE.md

import XCTest
@testable import LibWally

class BIP32Tests: XCTestCase {
    let seed = BIP39Seed("c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04")!
 
    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testSeedToHDKey() {
        let hdKey = HDKey(seed)
        XCTAssertEqual(hdKey!.description, "xprv9s21ZrQH143K3h3fDYiay8mocZ3afhfULfb5GX8kCBdno77K4HiA15Tg23wpbeF1pLfs1c5SPmYHrEpTuuRhxMwvKDwqdKiGJS9XFKzUsAF")
    }
    
    func testBase58ToHDKey() {
        let xpriv = "xprv9s21ZrQH143K3h3fDYiay8mocZ3afhfULfb5GX8kCBdno77K4HiA15Tg23wpbeF1pLfs1c5SPmYHrEpTuuRhxMwvKDwqdKiGJS9XFKzUsAF"
        let hdKey = HDKey(xpriv)
        XCTAssertEqual(hdKey!.description, xpriv)
        
        XCTAssertNil(HDKey("invalid"))
    }
    
    func testXpriv() {
        let xpriv = "xprv9s21ZrQH143K3h3fDYiay8mocZ3afhfULfb5GX8kCBdno77K4HiA15Tg23wpbeF1pLfs1c5SPmYHrEpTuuRhxMwvKDwqdKiGJS9XFKzUsAF"
        let hdKey = HDKey(xpriv)!
        
        XCTAssertEqual(hdKey.xpriv, xpriv)
    }
    
    func testXpub() {
        let xpriv = "xprv9s21ZrQH143K3h3fDYiay8mocZ3afhfULfb5GX8kCBdno77K4HiA15Tg23wpbeF1pLfs1c5SPmYHrEpTuuRhxMwvKDwqdKiGJS9XFKzUsAF"
        let xpub = "xpub661MyMwAqRbcGB88KaFbLGiYAat55APKhtWg4uYMkXAmfuSTbq2QYsn9sKJCj1YqZPafsboef4h4YbXXhNhPwMbkHTpkf3zLhx7HvFw1NDy"
        let hdKey = HDKey(xpriv)!
        
        XCTAssertEqual(hdKey.xpub, xpub)
    }
    
    func testParseXpub() {
        let xpub = "xpub661MyMwAqRbcGB88KaFbLGiYAat55APKhtWg4uYMkXAmfuSTbq2QYsn9sKJCj1YqZPafsboef4h4YbXXhNhPwMbkHTpkf3zLhx7HvFw1NDy"
        let hdKey = HDKey(xpub)
        XCTAssertNotNil(hdKey)
        XCTAssertEqual(hdKey!.description, xpub)
        XCTAssertEqual(hdKey!.xpub, xpub)
        XCTAssertNil(hdKey!.xpriv)

    }
    
    func testBIP32PathFromString() {
        let path = BIP32Path("m/0'/0") // 0' and 0h are treated the same
        XCTAssertNotNil(path)
        XCTAssertEqual(path!.components, [.hardened(0), .normal(0)])
        XCTAssertEqual(path!.description, "m/0h/0") // description always uses h instead of '
    }
    
    func testBIP32PathFromInt() {
        var path: BIP32Path
        XCTAssertNoThrow(try BIP32Path(0))
        path = try! BIP32Path(0)
        XCTAssertEqual(path.components, [.normal(0)])
        
        XCTAssertThrowsError(try BIP32Path(Int(UINT32_MAX))) { error in
            XCTAssertEqual(error as! BIP32Error, BIP32Error.invalidIndex)
        }
    }
    
    func testDerive() {
        let xpriv = "xprv9s21ZrQH143K3h3fDYiay8mocZ3afhfULfb5GX8kCBdno77K4HiA15Tg23wpbeF1pLfs1c5SPmYHrEpTuuRhxMwvKDwqdKiGJS9XFKzUsAF"
        let hdKey = HDKey(xpriv)!
        
        let derivation = try! BIP32Path(0)
        let childKey = try! hdKey.derive(derivation)

        XCTAssertNotNil(childKey.xpriv)
        XCTAssertEqual(childKey.xpriv!, "xprv9vEG8CuCbvqnJXhr1ZTHZYJcYqGMZ8dkphAUT2CDZsfqewNpq42oSiFgBXXYwDWAHXVbHew4uBfiHNAahRGJ8kUWwqwTGSXUb4wrbWz9eqo")
    }
    
    func testDeriveHardened() {
        let xpriv = "xprv9s21ZrQH143K3h3fDYiay8mocZ3afhfULfb5GX8kCBdno77K4HiA15Tg23wpbeF1pLfs1c5SPmYHrEpTuuRhxMwvKDwqdKiGJS9XFKzUsAF"
        let hdKey = HDKey(xpriv)!
        
        let derivation = try! BIP32Path(.hardened(0))
        let childKey = try! hdKey.derive(derivation)

        XCTAssertNotNil(childKey.xpriv)
        XCTAssertEqual(childKey.xpriv!, "xprv9vEG8CuLwbNkVNhb56dXckENNiU1SZEgwEAokv1yLodVwsHMRbAFyUMoMd5uyKEgPDgEPBwNfa42v5HYvCvT1ymQo1LQv9h5LtkBMvQD55b")
    }
    
    func testDerivePath() {
        let xpriv = "xprv9s21ZrQH143K3h3fDYiay8mocZ3afhfULfb5GX8kCBdno77K4HiA15Tg23wpbeF1pLfs1c5SPmYHrEpTuuRhxMwvKDwqdKiGJS9XFKzUsAF"
        let hdKey = HDKey(xpriv)!

        let path = BIP32Path("m/0'/0")!

        let childKey = try! hdKey.derive(path)
        
        XCTAssertNotNil(childKey.xpriv)
        XCTAssertEqual(childKey.xpriv!, "xprv9xcgxEx7PAbqP2YSijYjX38Vo6dV4i7g9ApmPRAkofDzQ6Hf4c3nBNRfW4EKSm2uhk4FBbjNFGjhZrATqLVKM2JjhsxSrUsDdJYK4UKhyQt")
    }
    
    func testDeriveFromXpub() {
        let xpub = "xpub661MyMwAqRbcGB88KaFbLGiYAat55APKhtWg4uYMkXAmfuSTbq2QYsn9sKJCj1YqZPafsboef4h4YbXXhNhPwMbkHTpkf3zLhx7HvFw1NDy"
        let hdKey = HDKey(xpub)!
        
        let path = BIP32Path("m/0")!
        let childKey = try! hdKey.derive(path)
        
        XCTAssertNotNil(childKey.xpub)
        XCTAssertEqual(childKey.xpub, "xpub69DcXiS6SJQ5X1nK7azHvgFM6s6qxbMcBv65FQbq8DCpXjhyNbM3zWaA2p4L7Na2siUqFvyuK9W11J6GjqQhtPeJkeadtSpFcf6XLdKsZLZ")
        XCTAssertNil(childKey.xpriv)
        
        let hardenedPath = BIP32Path("m/0'")!

        XCTAssertThrowsError(try hdKey.derive(hardenedPath))
    }
}
