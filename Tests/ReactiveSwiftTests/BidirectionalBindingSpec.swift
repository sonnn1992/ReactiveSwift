import Quick
import Nimble
@testable import ReactiveSwift
import Result

let globalQueue: DispatchQueue = {
	if #available(macOS 10.10, *) {
		return DispatchQueue.global(qos: .userInteractive)
	} else {
		return DispatchQueue.global(priority: .high)
	}
}()

func makeScheduler(name: String) -> QueueScheduler {
	if #available(macOS 10.10, *) {
		return QueueScheduler(qos: .userInteractive, name: name)
	} else {
		return QueueScheduler(queue: DispatchQueue(label: name))
	}
}


class BidirectionalBindingSpec: QuickSpec {
	override func spec() {
		describe("asynchronous conflict resolution") {
			let iterations = 1000
			precondition(iterations < 1000000)

			it("should overwrite the upstream with the `overwriteUpstream` merge policy") {
				let upstreamScheduler = makeScheduler(name: "org.reactivecocoa.ReactiveSwift.BidirectionalBindingSpec.upstream")
				let upstream = Upstream(MutableProperty(-1), on: upstreamScheduler, mergePolicy: .overwriteUpstream)

				let downstreamScheduler = makeScheduler(name: "org.reactivecocoa.ReactiveSwift.BidirectionalBindingSpec.downstream")
				let downstream = Downstream(MutableProperty(-2), on: downstreamScheduler)

				upstream <<~> downstream
				expect(upstream.value).toEventually(equal(-1))
				expect(downstream.value).toEventually(equal(-1))

				let semaphore = DispatchSemaphore(value: 0)

				downstream.scheduler.schedule {
					downstream.value = Int.max
					semaphore.signal()
				}

				semaphore.wait()

				globalQueue.async {
					for i in 0 ..< iterations {
						upstream.scheduler.schedule {
							upstream.value = i
						}
					}
				}

				globalQueue.async {
					for i in 0 ..< iterations {
						downstream.scheduler.schedule {
							downstream.value = i + 1000000
						}
					}

					downstream.scheduler.schedule {
						upstream.scheduler.schedule {
							expect(upstream.value) == 999999 + iterations
							semaphore.signal()
						}
					}
				}

				semaphore.wait()
			}

			it("should overwrite the upstream with the `overwriteUpstream` merge policy") {
				let upstreamScheduler = makeScheduler(name: "org.reactivecocoa.ReactiveSwift.BidirectionalBindingSpec.upstream")
				let upstream = Upstream(MutableProperty(-1), on: upstreamScheduler, mergePolicy: .overwriteUpstream)

				let downstreamScheduler = makeScheduler(name: "org.reactivecocoa.ReactiveSwift.BidirectionalBindingSpec.downstream")
				let downstream = Downstream(MutableProperty(-2), on: downstreamScheduler)

				upstream <<~> downstream
				expect(upstream.value).toEventually(equal(-1))
				expect(downstream.value).toEventually(equal(-1))

				let semaphore = DispatchSemaphore(value: 0)

				downstream.scheduler.schedule {
					downstream.value = Int.max
					semaphore.signal()
				}

				semaphore.wait()

				globalQueue.async {
					upstream.scheduler.schedule {
						for i in 0 ..< iterations {
							upstream.value = i
						}
					}
				}

				globalQueue.async {
					downstream.scheduler.schedule {
						for i in 0 ..< iterations {
							downstream.value = i + 1000000
						}
					}

					downstream.scheduler.schedule {
						upstream.scheduler.schedule {
							expect(upstream.value) == 999999 + iterations
							semaphore.signal()
						}
					}
				}

				semaphore.wait()
			}
		}
	}
}
