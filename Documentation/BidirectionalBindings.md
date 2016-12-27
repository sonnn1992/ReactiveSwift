# Bidirectional Bindings
## The basics
A bidirectional binding is formed between an **upstream** and one or more **downstream** clients.

A bidirectional binding would unconditionally propagate values from the upstream to the downstream, until the downstream emits its first value.

An upstream or a downstream may specify a `Scheduler` that contains them. By default, the **immediate mode** is used — all writes to both ends would be processed and propagated synchronously.

On the other hand, if a upstream or a downstream specifies a `Scheduler` other than the default `ImmediateScheduler`, the **scheduler containing mode** would be used. In this mode, all writes would be serialised by the upstream `Scheduler`. In other words, changes propagation would be asynchronous between the two ends, so as conflict resolution for the downstream clients.

### Thread Safety
Immediate mode does not guarantee thread safety. It would depend on the conforming type being used. For example, a bidirectional binding between two `MutableProperty`s would be inherently thread safe. However, if either of the two ends is replaced with ReactiveCocoa's` DynamicProperty`, it would no longer be thread safe.

Scheduler Containing mode guarantees thread safety, provided that any external uses of the scheduler contained instances adheres to the promised containment.

## Consistency
| Upstream | Downstream | Possibility of Conflicts |
| -------- | ---------- | ------------------------ |
| Immediate | Immediate | NO |
| Immediate | Scheduler Containing | YES |
| Scheduler Containing | Immediate | YES |
| Scheduler Containing | Scheduler Containing | YES |

As shown in the table above, whenever a scheduler containing entity is involved, there is a possibility of conflicting updates. The bidirectional binding model mitigates conflicts by requiring the upstream to specify a merge policy. Two merge policies are available:

1. `overwriteUpstream`: The value of the downstream is preferred whenever there is a conflict. 
1. `custom`: A new value would be computed from the values of both ends, and subsequently overwrite both ends.

### Consistency Guarantees
If both ends are in immediate mode, the bidirectional binding has a sequential consistency in values between both ends. That is:

1. Both end always sees the same latest value;
1. All downstream clients see the same latest value; and
1. Merge conflict never happens.

If at least one of the two ends is scheduler contained, the bidirectional binding has an eventual consistency in values between both ends. That is:

1. Both ends __eventually__ sees the same latest value according to the merge policy defined by the upstream;
2. All downstream clients __eventually__ see the same latest value according to the merge policy by the upstream;
3. There is no total order in conflict resolution among the downstream clients.

On top of the eventual consistency, the bidirectional binding model guarantees **read-your-writes** consistency for the downstream clients:

1. If a downstream `Scheduler` enqueues to a upstream `Scheduler` a unit of work that reads the latest value, the work running on the upstream `Scheduler` would always see a conflict-resolved value that happens after all writes on the downstream `Scheduler` preceding the enqueue of the work. 
2. Even if the upstream has been written a value between the writes and the unit of work as mentioned in (1), the value being seen is guaranteed to be conflict resolved.

### Consistency in practice

