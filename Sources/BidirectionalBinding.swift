import Result

infix operator <<~> : BindingPrecedence

public protocol BidirectionalBindingDownstream: MutablePropertyProtocol {
	var scheduler: SchedulerProtocol { get }
}

extension BidirectionalBindingDownstream {
	public var scheduler: SchedulerProtocol {
		return ImmediateScheduler.shared
	}
}

public final class Downstream<P: MutablePropertyProtocol>: BidirectionalBindingDownstream {
	public let inner: P
	public let scheduler: SchedulerProtocol

	public var value: P.Value {
		get { return inner.value }
		set { inner.value = newValue }
	}

	public var producer: SignalProducer<P.Value, NoError> {
		return inner.producer.start(on: scheduler)
	}

	public var signal: Signal<P.Value, NoError> {
		return inner.signal
	}

	public var lifetime: Lifetime {
		return inner.lifetime
	}

	public init(_ inner: P, on scheduler: SchedulerProtocol = ImmediateScheduler.shared) {
		self.inner = inner
		self.scheduler = scheduler
	}
}

/// A protocol that defines the requirement of a type qualifying for being an
/// upstream in a bidirectional binding.
///
/// `MutablePropertyProtocol.value` of conforming types must support recursive
/// writes.
public protocol BidirectionalBindingUpstream: ComposableMutablePropertyProtocol {
	var mergePolicy: BidirectionalMergePolicy<Value> { get }
	var scheduler: SchedulerProtocol { get }
}

extension BidirectionalBindingUpstream {
	public var mergePolicy: BidirectionalMergePolicy<Value> {
		return .default
	}

	public var scheduler: SchedulerProtocol {
		return ImmediateScheduler.shared
	}
}

public final class Upstream<P: ComposableMutablePropertyProtocol>: BidirectionalBindingUpstream {
	public let inner: P
	public let mergePolicy: BidirectionalMergePolicy<P.Value>
	public let scheduler: SchedulerProtocol

	public var value: P.Value {
		get { return inner.value }
		set { inner.value = newValue }
	}

	public var producer: SignalProducer<P.Value, NoError> {
		return inner.producer
	}

	public var signal: Signal<P.Value, NoError> {
		return inner.signal
	}

	public var lifetime: Lifetime {
		return inner.lifetime
	}

	public init(_ inner: P, on scheduler: SchedulerProtocol = ImmediateScheduler.shared, mergePolicy: BidirectionalMergePolicy<P.Value>) {
		self.inner = inner
		self.mergePolicy = mergePolicy
		self.scheduler = scheduler
	}

	public func withValue<Result>(action: (P.Value) throws -> Result) rethrows -> Result {
		return try inner.withValue(action: action)
	}

	public func modify<Result>(_ action: (inout P.Value) throws -> Result) rethrows -> Result {
		return try inner.modify(action)
	}
}

extension BidirectionalBindingUpstream {
	@discardableResult
	public static func <<~> <Downstream: BidirectionalBindingDownstream>(
		upstream: Self,
		downstream: Downstream
	) -> Disposable where Downstream.Value == Value {
		weak var weakUpstream = upstream
		weak var weakDownstream = downstream

		let upstreamScheduler = BindingScheduler(upstream.scheduler)
		let downstreamScheduler = BindingScheduler(downstream.scheduler)

		let disposable = CompositeDisposable()
		let mergePolicy = upstream.mergePolicy

		var mutesDownstream = false
		var mutesUpstream = false

		var isDownstreamActive = false
		var resolvedValue: Value!

		let lock = NSLock()

		func merge(_ value: BindingMergeRequest<Value>) {
			guard let upstream = weakUpstream, let downstream = weakDownstream else {
				return
			}

			func updateDownstream(_ value: Value) {
				downstreamScheduler.schedule {
					mutesDownstream = true
					downstream.value = value
				}
			}

			func updateUpstream(_ value: Value) {
				mutesUpstream = true
				upstream.value = value
			}

			switch value {
			case let .upstream(proposedValue):
				lock.lock()

				if !isDownstreamActive {
					resolvedValue = proposedValue
					updateDownstream(proposedValue)
				} else {
					switch mergePolicy {
					case .overwriteUpstream:

						updateUpstream(resolvedValue)

					case let .custom(merge):
						resolvedValue = merge(proposedValue, resolvedValue)
						updateUpstream(resolvedValue)
						updateDownstream(resolvedValue)
					}
				}

				lock.unlock()

			case let .downstream(proposedValue):
				lock.lock()

				if !isDownstreamActive {
					isDownstreamActive = true
				}

				switch mergePolicy {
				case .overwriteUpstream:
					resolvedValue = proposedValue
					updateUpstream(proposedValue)

				case let .custom(merge):
					resolvedValue = merge(resolvedValue, proposedValue)
					updateUpstream(resolvedValue)
					updateDownstream(resolvedValue)
				}

				lock.unlock()
			}
		}

		disposable += upstream.producer
			.startWithValues { value in
				guard !mutesUpstream else {
					mutesUpstream = false
					return
				}

				merge(.upstream(proposedValue: value))
			}

		disposable += downstream.signal
			.observeValues { value in
				guard !mutesDownstream else {
					mutesDownstream = false
					return
				}

				upstreamScheduler.schedule {
					merge(.downstream(proposedValue: value))
				}
			}

		disposable += upstream.lifetime.ended.observeCompleted(disposable.dispose)
		disposable += downstream.lifetime.ended.observeCompleted(disposable.dispose)

		return AnyDisposable(disposable)
	}
}

private enum BindingScheduler: SchedulerProtocol {
	case immediate
	case async(SchedulerProtocol)

	init(_ scheduler: SchedulerProtocol) {
		if scheduler is ImmediateScheduler {
			self = .immediate
		} else {
			self = .async(scheduler)
		}
	}

	@discardableResult
	func schedule(_ action: @escaping () -> Void) -> Disposable? {
		switch self {
		case .immediate:
			action()
			return nil

		case let .async(scheduler):
			return scheduler.schedule(action)
		}
	}
}

private enum BindingMergeRequest<Value> {
	case upstream(proposedValue: Value)
	case downstream(proposedValue: Value)
}

/// The merge policy to be used when a bidirectional binding causes a conflict
/// when writing to `TransactionalProperty`.
public enum BidirectionalMergePolicy<Value> {
	public static var `default`: BidirectionalMergePolicy<Value> {
		return .overwriteUpstream
	}

	case overwriteUpstream
	case custom((_ upstream: Value, _ downstream: Value) -> Value)
}
