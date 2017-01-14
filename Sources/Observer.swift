//
//  Observer.swift
//  ReactiveSwift
//
//  Created by Andy Matuschak on 10/2/15.
//  Copyright © 2015 GitHub. All rights reserved.
//

/// A protocol for type-constrained extensions of `Observer`.
public protocol ObserverProtocol {
	associatedtype Value
	associatedtype Error: Swift.Error

	/// Puts a `value` event into `self`.
	func send(value: Value)

	/// Puts a failed event into `self`.
	func send(error: Error)

	/// Puts a `completed` event into `self`.
	func sendCompleted()

	/// Puts an `interrupted` event into `self`.
	func sendInterrupted()
}

/// An Observer is a simple wrapper around a function which can receive Events
/// (typically from a Signal).
public final class Observer<Value, Error: Swift.Error> {
	public typealias Action = (Event<Value, Error>) -> Void

	/// An action that will be performed upon arrival of the event.
	public let action: Action

	/// An initializer that accepts a closure accepting an event for the 
	/// observer.
	///
	/// - parameters:
	///   - action: A closure to lift over received event.
	public init(_ action: @escaping Action) {
		self.action = action
	}

	/// An initializer that accepts closures for different event types.
	///
	/// - parameters:
	///   - value: An optional closure that handles `value` events.
	///   - failed: An optional closure that handles a `failed` event.
	///   - completed: An optional closure that handles a `completed` event.
	///   - interruped: An optional closure that handles an `interrupted` event.
	///   - terminated: An optional closure that is invoked whenever a terminal
	///                 event is received.
	public convenience init(
		value: ((Value) -> Void)? = nil,
		failed: ((Error) -> Void)? = nil,
		completed: (() -> Void)? = nil,
		interrupted: (() -> Void)? = nil,
		terminated: (() -> Void)? = nil
	) {
		self.init { event in
			switch event {
			case let .value(v):
				value?(v)

			case let .failed(error):
				failed?(error)
				terminated?()

			case .completed:
				completed?()
				terminated?()

			case .interrupted:
				interrupted?()
				terminated?()
			}
		}
	}
}

extension Observer: ObserverProtocol {
	/// Puts a `value` event into `self`.
	///
	/// - parameters:
	///   - value: A value sent with the `value` event.
	public func send(value: Value) {
		action(.value(value))
	}

	/// Puts a failed event into `self`.
	///
	/// - parameters:
	///   - error: An error object sent with failed event.
	public func send(error: Error) {
		action(.failed(error))
	}

	/// Puts a `completed` event into `self`.
	public func sendCompleted() {
		action(.completed)
	}

	/// Puts an `interrupted` event into `self`.
	public func sendInterrupted() {
		action(.interrupted)
	}
}
