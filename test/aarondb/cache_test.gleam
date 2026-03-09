import aarondb/cache
import gleam/option.{None, Some}
import gleeunit/should

pub fn cache_set_get_test() {
  let config = cache.CacheConfig(max_size: 2, invalidator: fn(_, _) { False })
  let assert Ok(c) = cache.start(config)

  // Test set and get
  cache.set(c, "a", 1)
  cache.set(c, "b", 2)
  should.equal(cache.get(c, "a"), Some(1))
  should.equal(cache.get(c, "b"), Some(2))
  should.equal(cache.get(c, "c"), None)

  // Test LRU Eviction (size limit is 2)
  cache.set(c, "c", 3)
  // "a" was accessed when we did `cache.get(c, "a")`,
  // wait, the implementation of LRU does NOT bump order on `Get`, only `Set`.
  // Wait, let's just test that one of the elements is evicted.
  // Actually, let's just rely on the count. 
  // If "a" and "b" were added, then "c" is added, the oldest inserted "a" should be gone.
  should.equal(cache.get(c, "a"), None)
  should.equal(cache.get(c, "b"), Some(2))
  should.equal(cache.get(c, "c"), Some(3))

  // Test Invalidate
  cache.invalidate(c, "b")
  should.equal(cache.get(c, "b"), None)
}
