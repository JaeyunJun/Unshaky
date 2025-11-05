//
//  Counter.swift
//  Unshaky
//
//  Created by Xinhong LIU on 4/11/19.
//  Copyright © 2019 Nested Error. All rights reserved.
//

import Cocoa

class Counter: NSObject {
    static let shared = Counter()

    let defaults = UserDefaults.standard

    static let TOTAL_COUNT_KEY = "DISMISS_COUNT"
    static let INDIVIDUAL_COUNT_KEY = "DISMISS_COUNT_INDIVIDUAL"

    let nVirtualKey = Int(N_VIRTUAL_KEY)

    private var dismissCount = 0
    private var dismissCountIndividual: [Int] = [Int]()
    var statString: String {
        get {
            return String(format: NSLocalizedString("Overall Statistic", comment: ""), dismissCount)
        }
    }

    public struct KeyCounter {
        let keyCode: Int
        let count: Int

//        init(keyCode: Int, count: Int) {
//            self.keyCode = keyCode
//            self.count = count
//        }
    }

    private var _cachedKeyCounters: [KeyCounter]?
    private var _cacheInvalidated = true
    
    var keyCounters: [KeyCounter] {
        get {
            if _cacheInvalidated || _cachedKeyCounters == nil {
                var counters = [KeyCounter]()
                counters.reserveCapacity(nVirtualKey)
                
                for i in 0..<nVirtualKey {
                    let count = dismissCountIndividual[i]
                    if count > 0 { // Only include keys with actual counts
                        counters.append(KeyCounter(keyCode: i, count: count))
                    }
                }
                _cachedKeyCounters = counters.sorted(by: { $0.count > $1.count })
                _cacheInvalidated = false
            }
            return _cachedKeyCounters!
        }
    }

    override init() {
        super.init()

        dismissCount = defaults.integer(forKey: Counter.TOTAL_COUNT_KEY)
        dismissCountIndividual = defaults.array(forKey: Counter.INDIVIDUAL_COUNT_KEY) as? [Int] ?? Array(repeating: 0, count: nVirtualKey)
        notifyObservers()
    }

    private var saveTimer: Timer?
    private var needsSave = false
    
    func increment(keyCode: Int32) {
        dismissCount += 1
        dismissCountIndividual[Int(keyCode)] += 1
        needsSave = true
        
        // Batch notifications to reduce UI updates
        if saveTimer == nil {
            saveTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                self?.notifyObservers()
                self?.saveTimer = nil
            }
        }
        
        // Batch saves to reduce disk I/O
        scheduleSave()
    }
    
    private func scheduleSave() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            if self?.needsSave == true {
                self?.save()
                self?.needsSave = false
            }
        }
    }

    func reset() {
        dismissCount = 0
        dismissCountIndividual = Array(repeating: 0, count: nVirtualKey)
        notifyObservers()
    }

    func save() {
        defaults.set(dismissCount, forKey: Counter.TOTAL_COUNT_KEY)
        defaults.set(dismissCountIndividual, forKey: Counter.INDIVIDUAL_COUNT_KEY)
        defaults.synchronize()
    }

    func notifyObservers() {
        _cacheInvalidated = true
        NotificationCenter.default.post(name: .counterUpdate, object: nil)
    }
}

extension Notification.Name {
    static let counterUpdate = Notification.Name("counter-update")
}
