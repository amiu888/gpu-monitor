import Foundation

struct CircularBuffer<T> {
    private var storage: [T]
    private var head: Int = 0
    private(set) var count: Int = 0
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        self.storage = []
        self.storage.reserveCapacity(capacity)
    }

    mutating func append(_ value: T) {
        if count < capacity {
            storage.append(value)
            count += 1
        } else {
            storage[head] = value
        }
        head = (head + 1) % capacity
    }

    // Returns elements ordered oldest → newest
    func toArray() -> [T] {
        if count < capacity {
            return Array(storage)
        }
        let tail = head
        return Array(storage[tail...] + storage[..<tail])
    }
}
