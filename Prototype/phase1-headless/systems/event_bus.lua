-- SimulationEventBus
-- The ONLY cross-system coupling point. Systems subscribe to event types
-- and fire events here. No direct references between subsystems.

local EventBus = {}
EventBus._listeners = {}

-- Subscribe to an event type
-- handler: function(data) called when event fires
function EventBus.subscribe(event_type, handler)
    if not EventBus._listeners[event_type] then
        EventBus._listeners[event_type] = {}
    end
    table.insert(EventBus._listeners[event_type], handler)
end

-- Fire an event with optional data payload
function EventBus.fire(event_type, data)
    local listeners = EventBus._listeners[event_type]
    if not listeners then return end
    for _, handler in ipairs(listeners) do
        handler(data or {})
    end
end

-- Clear all listeners (useful for testing)
function EventBus.reset()
    EventBus._listeners = {}
end

--[[
Event types used in Phase 1:

  SEASON_CHANGED      { season, year, day }
  DAILY_TICK          { day, season, year }
  WEEKLY_TICK         { week, season, year }
  MONTHLY_TICK        { month, year }
  WEATHER_EVENT       { event_type, severity, biome_filter }
  RESOURCE_DEPLETED   { resource, settlement_id }
  FAMINE_STARTED      { settlement_id }
  REVOLT_STARTED      { settlement_id }
  REVOLT_SPREAD       { from_id, to_id }
]]

return EventBus
