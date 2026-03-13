-- EventBus
-- Minimal pub/sub. Only cross-system coupling point.

local EventBus = {}
EventBus._listeners = {}

function EventBus.subscribe(event_type, handler)
    if not EventBus._listeners[event_type] then
        EventBus._listeners[event_type] = {}
    end
    table.insert(EventBus._listeners[event_type], handler)
end

function EventBus.fire(event_type, data)
    local listeners = EventBus._listeners[event_type]
    if not listeners then return end
    for _, handler in ipairs(listeners) do
        handler(data or {})
    end
end

function EventBus.reset()
    EventBus._listeners = {}
end

return EventBus
