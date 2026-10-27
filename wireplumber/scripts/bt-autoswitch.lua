-- bt-autoswitch.lua - make a Bluetooth audio sink the default output as soon
-- as it appears. Without this, wireplumber keeps the last configured default
-- (the laptop speakers) and apps never move to the headphones.

SimpleEventHook {
  name = "custom/bt-autoswitch",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-added" },
      Constraint { "media.class", "=", "Audio/Sink" },
      Constraint { "device.api", "=", "bluez5" },
    },
  },
  execute = function (event)
    local node = event:get_subject ()
    local om = event:get_source ():call ("get-object-manager", "metadata")
    local metadata = om:lookup { Constraint { "metadata.name", "=", "default" } }
    if not metadata then
      return
    end
    local name = node.properties ["node.name"]
    metadata:set (0, "default.configured.audio.sink", "Spa:String:JSON",
        Json.Object { name = name }:to_string ())
    Log.info ("bt-autoswitch: default sink -> " .. name)
  end
}:register ()
