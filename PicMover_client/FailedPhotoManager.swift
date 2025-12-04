//
//  FailedPhotoManager.swift
//  PicMover_client
//
//  Created by sunjnn on 2025/12/2.
//

import Foundation

class FailedPhotoManager {
    static let shared = FailedPhotoManager()
    
    private let _key = "FailedPhotoLocalIdentifiers"
    private var _identifiers: Set<String> = []
    
    private init() {
        load()
    }
    
    func load() {
        let defaults = UserDefaults.standard
        if let array = defaults.array(forKey: _key) as? [String] {
            _identifiers = Set(array)
        }
        else {
            _identifiers = []
        }
    }
    
    func save() {
        let defaults = UserDefaults.standard
        defaults.set(Array(_identifiers), forKey: _key)
    }
    
    func add(localIdentifier: String) {
        _identifiers.insert(localIdentifier)
    }
    
    func remove(localIdentifier: String) {
        _identifiers.remove(localIdentifier)
    }
    
    func getAllIdentifiers() -> [String] {
        return Array(_identifiers)
    }
    
    func count() -> Int {
        return _identifiers.count
    }
}
