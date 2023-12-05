--- Enables a "Lite" version of the HUD along with AR
--- Aims for showing vital information while using less system resources
--- Press Alt + 3 to toggle between Lite and default HUDs
--- Note: This replaces the mode where the HUD is hidden!
local enableLiteHud = true

--- Enables smooth mode for AR
--- Thanks to EasternGamer for helping with this!
local enableSmoothMode = true

--- Uses the same positioning of altitude/speed as ArchHUD
local useSameAltitudeSpeedPositioning = true

--- Controls HUD scale (how large things are)
local hudScale = 1.6

--- Enables FPS counter
local showFramesPerSecond = true

userBase = (function()
  --[[
    Embed our libraries for template rendering
  ]]

  local SmartTemplateLibrary = (function ()
    --[[
      Wolfe Labs Smart Template Library (STL)
      A simple, Twig-like templating language for Lua
      Syntax:
        {{ variable }} prints the contents of "variable"
        {% some_lua_code %} executes the Lua code, useful for creating blocks like {% if %} and {% else %}, make sure you add {% end %} too :)
      (C) 2022 - Wolfe Labs
    ]]
  
    --- Helper function that generates a clean print statement of a certain string
    ---@param str string The string we need to show
    ---@return string
    local function mkPrint(str)
      return 'print(\'' .. str:gsub('\'', '\\\''):gsub('\n', '\\n') .. '\')'
    end
  
    --- Helper function that merges tables
    ---@vararg table
    ---@return table
    local function tMerge(...)
      local tables = {...}
      local result = {}
      for _, t in pairs(tables) do
        for k, v in pairs(t) do
          result[k] = v
        end
      end
      return result
    end
  
    ---@class Template
    local Template = {
      --- Globals available for every template by default
      globals = {
        math = math,
        table = table,
        string = string,
        ipairs = ipairs,
        pairs = pairs,
      }
    }
  
    -- Makes our template directly callable
    function Template.__call(self, ...)
      return Template.render(self, ({...})[1])
    end
  
    --- Renders our template
    ---@param vars table The variables to be used when rendering the template
    ---@return string
    function Template:render(vars)
      -- Safety check, vars MUST be a table or nil
      if type(vars or {}) ~= 'table' then
        error('Template parameters must be a table, got ' .. type(vars))
      end
      
      --- This is our return buffer
      local _ = {}
  
      -- Creates our environment
      local env = tMerge(Template.globals, self.globals or {}, vars or {}, {
        print = function (str) table.insert(_, tostring(str or '')) end,
      })
  
      -- Invokes our template
      self.callable(env)
  
      -- General trimming
      local result = table.concat(_, ''):gsub('%s+', ' ')
  
      -- Trims result
      result = result:sub(result:find('[^%s]') or 1):gsub('%s*$', '')
  
      -- Done
      return result
    end
  
    --- Creates a new template
    ---@param source string The code for your template
    ---@param globals table Global variables to be used on on the template
    ---@param buildErrorHandler function A function to handle build errors, if none is found throws an error
    ---@return Template
    function Template.new(source, globals, buildErrorHandler)
      -- Creates our instance
      local self = {
        source = source,
        globals = globals,
      }
  
      -- Yield function (mostly for games who limit executions per frame)
      local yield = (coroutine and coroutine.isyieldable() and coroutine.yield) or function () end
  
      -- Parses direct printing of variables, we'll convert a {{var}} into {% print(var) %}
      source = source:gsub('{{(.-)}}', '{%% print(%1) %%}')
  
      -- Ensures {% if %} ... {% else %} ... {% end %} stays on same line
      source = source:gsub('\n%s*{%%', '{%%')
      source = source:gsub('%%}\n', '%%}')
  
      --- This variable stores all our Lua "pieces"
      local tPieces = {}
  
      -- Parses actual Lua inside {% lua %} tags
      while #source > 0 do
        --- The start index of Lua tag
        local iLuaStart = source:find('{%%')
  
        --- The end index of Lua tag
        local iLuaEnd = source:find('%%}')
  
        -- Checks if we have a match
        if iLuaStart then
          -- Errors when not closing a tag
          if not iLuaEnd then
            error('Template error, missing Lua closing tag near: ' .. source:sub(0, 16))
          end
  
          --- The current text before Lua tag
          local currentText = source:sub(1, iLuaStart - 1)
          if #currentText then
            table.insert(tPieces, mkPrint(currentText))
          end
  
          --- Our Lua tag content
          local luaTagContent = source:sub(iLuaStart, iLuaEnd + 1):match('{%%(.-)%%}') or ''
          table.insert(tPieces, luaTagContent)
  
          -- Removes parsed content
          source = source:sub(iLuaEnd + 2)
        else
          -- Adds remaining Lua as a single print statement
          table.insert(tPieces, mkPrint(source))
  
          -- Marks content as parsed
          source = ''
        end
  
        -- Yields loading
        yield()
      end
  
      -- Builds the Lua function
      self.code = table.concat(tPieces, '\n')
  
      -- Builds our function and caches it, this is our template now
      local _, err = load(string.format([[return function (_) _ENV = _; _ = _ENV[_]; %s; end]], self.code), nil, 't', {})
      if _ and not err then
        _ = _()
      end
  
      -- Checks for any errors
      if err then
        if buildErrorHandler then
          buildErrorHandler(self, err)
        else
          error('Failed compiling template: ' .. err)
        end
  
        -- Retuns an invalid instance
        return nil
      else
        -- If everything passed, assigns our callable to our compiled function
        self.callable = _
      end
  
      -- Initializes our instance
      return setmetatable(self, Template)
    end
  
    -- By default, returns the constructor of our class
    return Template.new
  end)()
  
  local function SmartTemplate(code, globals)
    return SmartTemplateLibrary(code, globals, function(template, err)
      DUSystem.print(' [ERROR] Failed compiling template: ' .. err)
      DUSystem.print('[SOURCE] ' .. code)
      error()
    end)
  end

  --[[
    Initialize any important constants and globals
  ]]

  local json = require('json')
  
  local core, unit, system, library, construct = nil, nil, DUSystem, DULibrary, DUConstruct

  --- A list of all linked elements by their name
  local links = {}

  hasInitialized, result = pcall(function()
    -- Initializes our atlas as a map of body ID to body info
    local atlas = {}
    for systemId, celestialBodies in pairs(require('atlas') or {}) do
      for celestialBodyId, celestialBody in pairs(celestialBodies) do
        -- Patches for Sinnen Moon 1
        -- Source: Wolfe Labs Atlas <https://dual.wolfe.science/tools/calculators/>
        if celestialBodyId == 70 then
          celestialBody.radius = 17000
          celestialBody.GM = 367273401.388
          celestialBody.gravity = 1.271
        end

        atlas[celestialBodyId] = celestialBody
      end
    end

    --- Distance to "infinity", used when projecting AR directions, set to 100su
    local infinityDistance = 100 * 200000

    --- This is our "reference" gravity value, it will be calculated below
    ---@type number
    local referenceGravity1g = nil

    --- This is our last update time, we'll use to count FPS
    local currentFps = 0
    local tLastFrame = system.getUtcTime()

    --[[
      General Helpers
    ]]

    --- Gets the appropriate HUD color
    ---@param forcePvPZone boolean
    ---@return table<number,number>
    local function getHudColor(forcePvPZone)
      local isPvPZone = construct.isInPvPZone()
      if type(forceSafeZone) ~= 'nil' then
        isPvPZone = forcePvPZone
      end
      if isPvPZone then
        return { PvPR, PvPG, PvPB }
      else
        return { SafeR, SafeG, SafeB }
      end
    end

    --- Gets the appropriate HUD color in RGB notation
    ---@param alpha number
    ---@param forcePvPZone boolean
    ---@return string
    local function getHudColorRgb(alpha, forcePvPZone)
      local color = getHudColor(forcePvPZone)
      color[4] = alpha or 1
      return ('rgba(%s, %s, %s, %s)'):format(color[1], color[2], color[3], color[4])
    end

    --- Converts a coordinate from local to world space
    ---@param coordinate vec3
    ---@return vec3
    local function convertLocalToWorldCoordinates(coordinate)
      return vec3(construct.getWorldPosition())
      + coordinate.x * vec3(construct.getWorldOrientationRight())
      + coordinate.y * vec3(construct.getWorldOrientationForward())
      + coordinate.z * vec3(construct.getWorldOrientationUp())
    end

    --- Gets the current IPH/AP destination
    ---@return table
    local function getCurrentDestination()
      local position = nil
      if customLocation and not Autopilot then
        position = vec3(CustomTarget.position)
      elseif AutopilotTargetCoords then
        position = vec3(AutopilotTargetCoords)
      end

      if position and AutopilotTargetName ~= 'None' then
        return {
          name = AutopilotTargetName or 'Unknown Location',
          position = position,
        }
      end
      return nil
    end

    --- Converts fuel tank raw data into meaningful table
    ---@return table
    local function getFuelTankInfo(tank, tankType)
      local result = {}

      -- Loads hard-coded properties
      local properties = { 'id', 'name', 'volumeMax', 'massEmpty', 'massLast', 'timeLast', 'linkedElementIndex' }
      for index, property in pairs(properties) do
        result[property] = tank[index] or nil
      end

      -- Adds extra info
      result.isDataPrecise = false
      result.mass = core.getElementMassById(result.id)
      result.volumeMass = result.mass - result.massEmpty

      -- Adds linked element (if any)
      if result.slotIndex ~= 0 and tankType then
        result.linkedElement = unit[tankType .. '_' .. result.linkedElementIndex]

        -- Reads accurate data from linked element
        if result.linkedElement then
          local linkedData = json.decode(result.linkedElement.getWidgetData())
          if linkedData then
            result.isDataPrecise = true
            result.level = (linkedData.percentage or 0) / 100
            result.timeLeft = tonumber(linkedData.timeLeft) or nil
          end
        end
      end

      return result
    end

    --- Updates fuel level cache
    local cachedFuelTanks = nil
    local function updateFuelLevels()
      local now = system.getUtcTime()

      local allFuelTanks = {
        lastReading = now,
        perId = {},
        atmo = {},
        space = {},
        rockets = {},
      }
      for _, fuelTankType in pairs({ 'atmo', 'space', 'rocket' }) do
        local tanks = {}
        local tankType = nil
        local density = 0
        
        -- Selects right fuel type
        if 'atmo' == fuelTankType then
          tanks = atmoTanks
          tankType = 'atmofueltank'
          density = 4
        elseif 'space' == fuelTankType then
          tanks = spaceTanks
          tankType = 'spacefueltank'
          density = 6
        elseif 'rocket' == fuelTankType then
          tanks = rocketTanks
          tankType = 'rocketfueltank'
          density = 0.8
        end

        -- Processes our fuel tanks
        local fuelTanks = {}
        local fuelTimes = {
          min = nil,
          max = nil,
        }
        local hasRegisteredChange = true
        for _, _tank in pairs(tanks) do
          local tank = getFuelTankInfo(_tank, tankType)

          -- Compares with previous reading
          local fuelReadingDelta, fuelMassUsed, lastTimeLeft = nil, nil, nil
          local previousReading = cachedFuelTanks and cachedFuelTanks.perId[tank.id]
          if previousReading then
            fuelMassUsed = math.max(0, previousReading.volumeMass - tank.volumeMass)
            fuelReadingDelta = now - cachedFuelTanks[fuelTankType].lastReading
            lastTimeLeft = previousReading.timeLeft

            -- Stops counting if we're not spending fuel
            if tank.volumeMass == previousReading.volumeMass then
              hasRegisteredChange = false
            end
          end

          -- Let's use the widget data if we have it available
          local data = nil
          if tank.isDataPrecise then
            data = {
              level = tank.level,
              timeLeft = tank.timeLeft,
            }
          else
            -- When no data is available, compute it on the fly with whatever we have
            local timeLeft = lastTimeLeft
            if fuelMassUsed and fuelReadingDelta and fuelMassUsed > 0 then
              timeLeft = tank.volumeMass / (fuelMassUsed / fuelReadingDelta)
            end

            data = {
              level = tank.volumeMass / tank.volumeMax,
              timeLeft = timeLeft,
            }
          end

          -- Calculates minimum and maximum burn times
          if data.timeLeft then
            if fuelTimes.min and fuelTimes.max then
              fuelTimes.min = math.min(data.timeLeft, fuelTimes.min)
              fuelTimes.max = math.max(data.timeLeft, fuelTimes.max)
            else
              fuelTimes.min = data.timeLeft
              fuelTimes.max = data.timeLeft
            end
          end

          -- Updates previous reading
          allFuelTanks.perId[tank.id] = {
            volumeMass = tank.volumeMass,
            timeLeft = data.timeLeft,
          }

          table.insert(fuelTanks, data)
        end

        -- Handles cases where we stopped using fuel, triggering the UI to disappear
        if cachedFuelTanks and now - cachedFuelTanks[fuelTankType].lastReading > 6 then
          fuelTimes = {
            min = 2 ^ 31,
            max = 2 ^ 31,
          }
        end

        allFuelTanks[fuelTankType] = {
          lastReading = (hasRegisteredChange and now) or (cachedFuelTanks[fuelTankType].lastReading or now),
          tanks = fuelTanks,
          times = fuelTimes,
        }
      end

      cachedFuelTanks = allFuelTanks
    end

    --- Gets the fuel tank levels per type
    ---@return table
    local function getFuelLevels(fuelTankType)
      if not cachedFuelTanks then
        updateFuelLevels()
      end

      return cachedFuelTanks[fuelTankType].tanks, cachedFuelTanks[fuelTankType].times
    end

    --- Gets the current forward direction in world space
    ---@return vec3
    local function getCurrentPointedAt()
      return convertLocalToWorldCoordinates(vec3(0, infinityDistance, 0))
    end

    --- Gets the current motion direction in world space
    ---@return vec3
    local function getCurrentMotion()
      local worldVelocity = vec3(construct.getWorldAbsoluteVelocity())
      if worldVelocity:len() < 1 then
        return nil
      end
      return worldVelocity:normalize_inplace() * infinityDistance + vec3(construct.getWorldPosition())
    end

    --- Converts a distance amount into meters, kilometers or su
    ---@param distance number
    ---@return string
    local function getDistanceAsString(distance)
      if distance > 100000 then
        return ('%.1f su'):format(distance / 200000)
      elseif distance > 1000 then
        return ('%.1f km'):format(distance / 1000)
      end
      return ('%.1f m'):format(distance)
    end

    --- Converts a number of seconds into a string
    ---@param seconds number
    ---@return string
    local function getTimeAsString(seconds, longFormat)
      local days = math.floor(seconds / 86400)
      seconds = seconds - days * 86400

      local hours = math.floor(seconds / 3600)
      seconds = seconds - hours * 3600

      local minutes = math.floor(seconds / 60)
      seconds = seconds - minutes * 60

      -- Long format (X hours, Y minutes, Z seconds)
      if longFormat then
        local result = {}
        if days > 0 then table.insert(result, days .. 'd') end
        if hours > 0 then table.insert(result, hours .. 'h') end
        if minutes > 0 then table.insert(result, minutes .. 'm') end
        if hours == 0 then
          table.insert(result, math.floor(seconds) .. 's')
        end

        return table.concat(result, ' ')
      end

      -- Short format (X:YY:ZZ)
      local result = {}
      if hours > 0 then
        table.insert(result, hours + 24 * days)
      end
      table.insert(result, ('%02d'):format(math.floor(minutes)))
      table.insert(result, ('%02d'):format(math.floor(seconds)))
      return table.concat(result, ':')
    end

    --- Converts a m/s value into a string (optionally converts to km/h too)
    ---@param value number
    ---@param convertToKmph boolean
    ---@return string
    local function getMetersPerSecondAsString(value, convertToKmph)
      if convertToKmph then
        return ('%.1f km/h'):format(value * 3.6)
      end
      return ('%.1f m/s'):format(value)
    end

    --- Rounds a value to desired precision
    ---@param value number
    ---@param precision number
    ---@return string
    local function getRoundedValue(value, precision)
      return ('%.' .. (precision or 0) .. 'f'):format(value)
    end
    
    --- Gets closest celestial body to world position (in m/s²)
    ---@param altitude number
    ---@param celestialBody table
    local function getGravitationalForceAtAltitude(altitude, celestialBody)
      return celestialBody.GM / (celestialBody.radius + altitude) ^ 2
    end
    
    --- Gets closest celestial body to world position (in Gs)
    ---@param altitude number
    ---@param celestialBody table
    local function getGravitationalForceAtAltitudeInGs(altitude, celestialBody)
      return getGravitationalForceAtAltitude(altitude, celestialBody) / referenceGravity1g
    end
    
    --- Gets the altitude where a celestial body has certain gravitational force (in m/s²)
    ---@param intensity number
    ---@param celestialBody table
    local function getAltitudeAtGravitationalForce(intensity, celestialBody)
      return math.sqrt(celestialBody.GM / intensity) - celestialBody.radius
    end
    
    --- Gets the altitude where a celestial body has certain gravitational force (in Gs)
    ---@param intensity number
    ---@param celestialBody number
    local function getAltitudeAtGravitationalForceInGs(intensity, celestialBody)
      return getAltitudeAtGravitationalForce(intensity * referenceGravity1g, celestialBody)
    end
    
    --- Gets closest celestial body to world position
    ---@param position vec3
    ---@param maxRange number
    local function getClosestCelestialBody(position, allowInfiniteRange)
      local closestBody = nil
      local closestBodyDistance = nil

      for _, celestialBody in pairs(atlas) do
        local celestialBodyPosition = vec3(celestialBody.center)
        local celestialBodyDistance = (position - celestialBodyPosition):len()
        local celestialBodyAltitude = celestialBodyDistance - (celestialBody.radius or 0)

        if (not closestBodyDistance or closestBodyDistance > celestialBodyAltitude) and (allowInfiniteRange or celestialBodyDistance <= 400000) then
          closestBody = celestialBody
          closestBodyDistance = celestialBodyAltitude
        end
      end

      return closestBody, closestBodyDistance
    end

    --- Gets a celestial body relative position from a world position
    ---@param position vec3
    ---@param celestialBody table
    ---@return table
    local function getCelestialBodyPosition(position, celestialBody)
      return position - vec3(celestialBody.center.x, celestialBody.center.y, celestialBody.center.z)
    end

    --- Gets a lat, lon, alt position from a world position
    ---@param position vec3
    ---@param celestialBody table
    ---@return table
    local function getLatLonAltFromWorldPosition(position, celestialBody)
      -- We need to extract the "local" coordinate (offset from planet center) here and then normalize it to do math with it
      local offset = getCelestialBodyPosition(position, celestialBody)
      local offsetNormalized = offset:normalize()

      return {
        lat = 90 - (math.acos(offsetNormalized.z) * 180 / math.pi),
        lon = math.atan(offsetNormalized.y, offsetNormalized.x) / math.pi * 180,
        alt = offset:len() - celestialBody.radius,
      }
    end

    --- Gets the distance to a certain point in space
    ---@param point vec3
    ---@return number
    local function getDistanceToPoint(point)
      return (vec3(construct.getWorldPosition()) - point):len()
    end

    --- Gets the distance to a certain point in space
    --- Code adapted from: https://community.esri.com/t5/coordinate-reference-systems-blog/distance-on-a-sphere-the-haversine-formula/ba-p/902128
    ---@param point vec3
    ---@param celestialBody table
    ---@return number
    local function getDistanceAroundCelestialBody(point, celestialBody)
      local currentCoordinates = getLatLonAltFromWorldPosition(vec3(construct.getWorldPosition()), celestialBody)
      local targetCoordinates = getLatLonAltFromWorldPosition(point, celestialBody)
      local flyingAltitude = math.max(currentCoordinates.alt, celestialBody.maxStaticAltitude or 1000)

      -- Helper function to convert degrees to radians
      local function rad(deg)
        return deg * math.pi / 180
      end

      local phi1, phi2 = rad(currentCoordinates.lat), rad(targetCoordinates.lat)
      local deltaPhi, deltaLambda = rad(currentCoordinates.lat - targetCoordinates.lat), rad(currentCoordinates.lon - targetCoordinates.lon)

      local a = math.sin(deltaPhi / 2) ^ 2 + math.cos(phi2) * math.cos(phi2) * math.sin(deltaLambda / 2) ^ 2
      local c = 2 * math.atan(math.sqrt(a), math.sqrt(1 - a))

      return (celestialBody.radius + flyingAltitude) * c
    end

    --[[
      AR Helpers
    ]]

    --- Gets the x, y, depth screen coordinates (in 0-1 space) from a world position
    ---@param coordinate vec3
    ---@return vec3
    local function getARPointFromCoordinate(coordinate)
      local result = vec3(library.getPointOnScreen({ coordinate:unpack() }))
      if result:len() == 0 then
        return nil
      end
      return result
    end

    --[[
      Render-related stuff, this mostly generates a self-contained render function that updates the UI for us, based on input parameters
    ]]

    local previousBuffer = ''
    local render = (function()
      local UI = {}
      local Shapes = {}
      local renderGlobals = {
        UI = UI,
        Shapes = Shapes,
        WorldCoordinate = getARPointFromCoordinate,
        Time = getTimeAsString,
        Round = getRoundedValue,
        Exists = function(value) return 'nil' ~= type(value) end,
        Percentage = function(value, precision) return getRoundedValue(100 * value, precision) .. '%' end,
        Metric = getDistanceAsString,
        MetersPerSecond = getMetersPerSecondAsString,
        KilometersPerHour = function(value) return ('%.0f km/h'):format(value) end,
        TimeToDistance = function(distance, speed) return ((speed > 0) and getTimeAsString(distance / speed, true)) or nil end,
        DistanceTo = getDistanceToPoint,
        DistanceAroundCelestialBody = getDistanceAroundCelestialBody,
        GravityAt = getGravitationalForceAtAltitude,
        GravityAtInGs = getGravitationalForceAtAltitudeInGs,
        Colors = {
          Main = '#09D4EB',
          Accent = '#5FFF77',
          Shadow = 'rgba(0, 0, 0, 0.75)',
          ShadowLight = 'rgba(0, 0, 0, 0.375)',
        },
        GetHudColor = getHudColorRgb,
        UseArchHudPositioning = useSameAltitudeSpeedPositioning,
        HudScale = hudScale,
      }

      --- Draws text as SVG
      renderGlobals.TextSvg = SmartTemplate([[
        <svg>
          <text x="0" y="{{ size or 20 }}" font-size="{{ size or 20 }}" style="font-family: {{ font or 'Play' }}; font-weight: {{ weight or 'normal' }}; fill: transparent; stroke: {{ stroke or 'transparent' }}; stroke-width: 4px;">{{ text }}</text>
          <text x="0" y="{{ size or 20 }}" font-size="{{ size or 20 }}" style="font-family: {{ font or 'Play' }}; font-weight: {{ weight or 'normal' }}; fill: {{ color or GetHudColor() }};">{{ text }}</text>
        </svg>
      ]], renderGlobals)

      --- Draws text
      renderGlobals.Label = SmartTemplate([[
        <span style="font-size: {{ size or 1 }}em; font-family: {{ font or 'Play' }}; font-weight: {{ weight or 'normal' }}; color: {{ color or GetHudColor() }}; text-shadow: 0px 0px 0.125em {{ stroke or Colors.Shadow }}, 0px 0px 0.250em #000, 0px 0px 0.500em #000;">
          {{ text }}
        </span>
      ]], renderGlobals)

      --- Draws the hexagon, showing the current destiantion point in space
      Shapes.Hexagon = SmartTemplate([[
        <svg style="width: {{ size or 1 }}em; height: {{ size or 1 }}em;" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M24.25 1.56699L24 1.42265L23.75 1.56699L4.69745 12.567L4.44745 12.7113V13V35V35.2887L4.69745 35.433L23.75 46.433L24 46.5774L24.25 46.433L43.3026 35.433L43.5526 35.2887V35V13V12.7113L43.3026 12.567L24.25 1.56699ZM9.44745 32.4019V15.5981L24 7.19615L38.5526 15.5981V32.4019L24 40.8038L9.44745 32.4019Z" fill="{{ color }}" stroke="{{ stroke }}"/>
        </svg>
      ]])

      --- Draws the crosshair, showing current forward direction
      Shapes.Crosshair = SmartTemplate([[
        <svg style="width: {{ size or 1 }}em; height: {{ size or 1 }}em;" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M23.6465 37.8683L24.0001 38.2218L24.3536 37.8683L26.3536 35.8684L26.5 35.7219V35.5148V26.5H35.5148H35.7219L35.8684 26.3536L37.8684 24.3536L38.2219 24L37.8684 23.6465L35.8684 21.6465L35.7219 21.5H35.5148H26.5V12.4852V12.2781L26.3536 12.1317L24.3536 10.1317L24.0001 9.77818L23.6465 10.1317L21.6465 12.1318L21.5 12.2782V12.4854V21.5H12.4854H12.2782L12.1318 21.6465L10.1318 23.6465L9.77824 24L10.1318 24.3536L12.1318 26.3536L12.2782 26.5H12.4854H21.5V35.5147V35.7218L21.6465 35.8682L23.6465 37.8683Z" fill="{{ color }}" stroke="{{ stroke }}"/>
        </svg>
      ]])

      --- Draws the crosshair, showing current forward direction
      Shapes.Galaxy = SmartTemplate([[
        <svg style="width: {{ size or 1 }}em; height: {{ size or 1 }}em;" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M19.7518 24C19.7518 21.6538 21.6538 19.7519 24 19.7519C26.3462 19.7519 28.2481 21.6538 28.2481 24C28.2481 26.3462 26.3462 28.2482 24 28.2482C21.6538 28.2482 19.7518 26.3462 19.7518 24ZM24 15.5864C19.3533 15.5864 15.5864 19.3533 15.5864 24C15.5864 28.6467 19.3533 32.4136 24 32.4136C28.6467 32.4136 32.4135 28.6467 32.4135 24C32.4135 19.3533 28.6467 15.5864 24 15.5864ZM23.2569 9.8038C26.0417 7.019 29.8658 6.09465 33.4484 7.02345C34.5618 7.31212 35.6984 6.64351 35.9871 5.53007C36.2758 4.41663 35.6072 3.28 34.4937 2.99133C29.5298 1.70437 24.1742 2.99566 20.3115 6.85839C18.2946 8.87533 16.9853 11.2898 16.424 13.909C16.183 15.0337 16.8994 16.1409 18.0241 16.3819C19.1488 16.6229 20.256 15.9065 20.497 14.7818C20.8854 12.9694 21.7919 11.2688 23.2569 9.8038ZM18.7186 5.38198C19.7121 4.8024 20.0477 3.52712 19.4681 2.53355C18.8886 1.53999 17.6133 1.20439 16.6197 1.78397C12.2262 4.34689 9.25558 8.96438 9.25558 14.5037C9.25558 17.2279 9.97871 20.0175 11.5046 22.3064C12.1427 23.2635 13.4358 23.5221 14.3928 22.884C15.3499 22.246 15.6085 20.9529 14.9705 19.9958C13.964 18.4861 13.421 16.5275 13.421 14.5037C13.421 10.5464 15.5154 7.25048 18.7186 5.38198ZM7.02358 14.5516C7.31225 13.4382 6.64365 12.3015 5.53021 12.0128C4.41677 11.7242 3.28014 12.3928 2.99147 13.5062C1.70452 18.4702 2.9958 23.8258 6.85852 27.6885C8.87545 29.7055 11.29 31.0148 13.9091 31.576C15.0338 31.817 16.141 31.1006 16.382 29.9759C16.623 28.8512 15.9066 27.7441 14.7819 27.503C12.9695 27.1147 11.2689 26.2081 9.80392 24.7431C7.01913 21.9583 6.09478 18.1341 7.02358 14.5516ZM5.38197 29.2814C4.80239 28.2879 3.52711 27.9523 2.53355 28.5319C1.53999 29.1114 1.20439 30.3867 1.78397 31.3803C4.34688 35.7739 8.96435 38.7444 14.5037 38.7444C17.2279 38.7444 20.0175 38.0213 22.3063 36.4954C23.2634 35.8573 23.522 34.5643 22.884 33.6072C22.2459 32.6501 20.9528 32.3915 19.9958 33.0295C18.4861 34.036 16.5275 34.579 14.5037 34.579C10.5464 34.579 7.25047 32.4846 5.38197 29.2814ZM31.5759 34.091C31.8169 32.9663 31.1005 31.8591 29.9758 31.6181C28.8511 31.3771 27.7439 32.0935 27.5029 33.2182C27.1145 35.0306 26.208 36.7312 24.743 38.1962C21.9579 40.9813 17.9823 41.9001 14.5703 40.9815C13.4596 40.6825 12.3168 41.3405 12.0177 42.4512C11.7187 43.5619 12.3767 44.7047 13.4874 45.0037C18.3054 46.3009 23.826 45.004 27.6884 41.1416C29.7053 39.1247 31.0146 36.7102 31.5759 34.091ZM36.4953 25.6936C35.8573 24.7365 34.5642 24.4779 33.6071 25.1159C32.6501 25.754 32.3914 27.0471 33.0295 28.0042C34.036 29.5139 34.579 31.4725 34.579 33.4963C34.579 37.4536 32.4845 40.7495 29.2814 42.618C28.2878 43.1976 27.9522 44.4729 28.5318 45.4664C29.1114 46.46 30.3867 46.7956 31.3802 46.216C35.7738 43.6531 38.7444 39.0356 38.7444 33.4963C38.7444 30.7721 38.0212 27.9825 36.4953 25.6936ZM34.0909 16.424C32.9662 16.183 31.859 16.8994 31.618 18.0241C31.377 19.1488 32.0934 20.256 33.2181 20.497C35.0305 20.8854 36.7311 21.7919 38.1961 23.2569C40.9812 26.042 41.9 30.0177 40.9814 33.4297C40.6823 34.5404 41.3403 35.6832 42.451 35.9822C43.5617 36.2812 44.7045 35.6233 45.0036 34.5126C46.3007 29.6946 45.0039 24.1739 41.1415 20.3115C39.1245 18.2946 36.71 16.9853 34.0909 16.424ZM28.0042 14.9705C29.5139 13.964 31.4725 13.421 33.4963 13.421C37.4536 13.421 40.7495 15.5154 42.618 18.7186C43.1976 19.7121 44.4729 20.0477 45.4664 19.4681C46.46 18.8886 46.7956 17.6133 46.216 16.6197C43.6531 12.2261 39.0356 9.25556 33.4963 9.25556C30.7721 9.25556 27.9825 9.97869 25.6937 11.5046C24.7366 12.1427 24.478 13.4357 25.116 14.3928C25.7541 15.3499 27.0472 15.6085 28.0042 14.9705Z" fill="{{ color }}" stroke="{{ stroke }}" stroke-miterlimit="10" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
      ]])
      
      --- Draws the diamond, showing current motion vector
      Shapes.Diamond = SmartTemplate([[
        <svg style="width: {{ size or 1 }}em; height: {{ size or 1 }}em;" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M24.3536 1.64645L24 1.29289L23.6465 1.64645L1.64645 23.6465L1.29289 24L1.64645 24.3536L23.6465 46.3536L24 46.7071L24.3536 46.3536L46.3536 24.3536L46.7071 24L46.3536 23.6465L24.3536 1.64645ZM24 39.636L8.36396 24L24 8.36396L39.636 24L24 39.636Z" fill="{{ color }}" stroke="{{ stroke }}"/>
        </svg>
      ]])

      --- Creates an element that is always centered at a certain coordinate
      UI.PositionCenteredAt = SmartTemplate(
        'position: absolute; top: {{ Percentage(y, 6) }}; left: {{ Percentage(x, 6) }}; margin-top: -{{ (height or 1) / 2 }}em; margin-left: -{{ (width or 1) / 2 }}em;'
      , renderGlobals)

      --- Renders a full destination marker (hexagon + info)
      UI.DestinationMarker = SmartTemplate([[
      {%
        local screen = WorldCoordinate(position)
        local distance = DistanceTo(position)

        -- When on same celestial body, we need to take into account going around it
        -- We use math.max here so we can also take the vertical displacement into account
        if Exists(currentCelestialBody) and Exists(destinationCelestialBody) and currentCelestialBody.info.id == destinationCelestialBody.info.id then
          distance = math.max(distance, DistanceAroundCelestialBody(position, destinationCelestialBody.info))
        end

        -- Calculates the ETA at current speed
        local eta = nil
        if speed and speed > 1 then
          eta = TimeToDistance(distance, speed)
        end
      %}
      {% if screen then %}
        <div style="{{ UI.PositionCenteredAt({ x = screen.x, y = screen.y, width = 2, height = 2 }) }}">
          <div style="postion: relative;">
            {{ Shapes.Hexagon({ color = GetHudColor(), stroke = Colors.Shadow, size = 2 }) }}
          {% if title or distance then %}
            <div style="font-size: 0.8em; position: absolute; top: 1em; left: 2.5em; white-space: nowrap; padding: 0px 0.5em;">
              <hr style="border: 0px none; height: 2px; background: {{ GetHudColor() }}; width: 5em; margin: 0px -0.5em 0.5em; padding: 0px;" />
            {% if title then %}
              <div>{{ Label({ text = title, size = 1.2, weight = 'bold' }) }}</div>
            {% end %}
            {% if distance then %}
              <div>{{ Label({ text = Metric(distance) }) }}</div>
            {% end %}
            {% if eta then %}
              <div style="font-size: 0.8em;">{{ Label({ text = 'ETA: ' .. eta }) }}</div>
            {% end %}
            </div>
          {% end %}
          </div>
        </div>
      {% end %}
      ]], renderGlobals)

      --- Renders a full destination marker (hexagon + info)
      UI.WarpMarker = SmartTemplate([[
      {%
        local screen = WorldCoordinate(position)
        local distance = DistanceTo(position)
      %}
      {% if screen then %}
        <div style="{{ UI.PositionCenteredAt({ x = screen.x, y = screen.y, width = 2, height = 2 }) }}">
          <div style="postion: relative;">
            {{ Shapes.Galaxy({ color = GetHudColor(), stroke = Colors.Shadow, size = 2 }) }}
          {% if title or distance then %}
            <div style="font-size: 0.8em; position: absolute; top: 1em; left: 2.5em; white-space: nowrap; padding: 0px 0.5em;">
              <hr style="border: 0px none; height: 2px; background: {{ GetHudColor() }}; width: 5em; margin: 0px -0.5em 0.5em; padding: 0px;" />
              <div>{{ Label({ text = 'Warp Point', weight = 'bold' }) }}</div>
            {% if distance then %}
              <div>{{ Label({ text = Metric(distance) }) }}</div>
            {% end %}
            </div>
          {% end %}
          </div>
        </div>
      {% end %}
      ]], renderGlobals)

      --- Renders a crosshair shape
      UI.Crosshair = SmartTemplate([[
        <div style="{{ UI.PositionCenteredAt({ x = x, y = y, width = 1.5, height = 1.5 }) }}">
          {{ Shapes.Crosshair({ color = GetHudColor(), stroke = Colors.Shadow, size = 1.5 }) }}
        </div>
      ]], renderGlobals)

      --- Renders a diamond shape
      UI.Diamond = SmartTemplate([[
        <div style="{{ UI.PositionCenteredAt({ x = x, y = y, width = 1.5, height = 1.5 }) }}">
          {{ Shapes.Diamond({ color = GetHudColor(), stroke = Colors.Shadow, size = 1.5 }) }}
        </div>
      ]], renderGlobals)

      --- Renders a horizontal progress bar
      UI.ProgressHorizontal = SmartTemplate([[
        <div style="width: {{ width or 2 }}em; height: {{ height or 1 }}em; border: 0.1em solid {{ stroke or GetHudColor() }};">
          <div style="width: {{ 100 * (progress or 0) }}%; height: 100%; background: {{ color or GetHudColor() }};"></div>
        </div>
      ]], renderGlobals)

      --- Renders a horizontal progress bar
      UI.ProgressVertical = SmartTemplate([[
        <div style="position: relative; width: {{ width or 1 }}em; height: {{ height or 2 }}em; border: 0.1em solid {{ stroke or GetHudColor() }};">
          <div style="position: absolute; bottom: 0px; left: 0px; width: 100%; height: {{ 100 * (progress or 0) }}%; background: {{ color or GetHudColor() }};"></div>
        </div>
      ]], renderGlobals)

      --- Renders a horizontal progress bar
      UI.DataRow = SmartTemplate([[
        <tr class="data-row">
          <td class="data-row-label">
            {{ Label({ text = label, weight = 'bold' }) }}
          </td>
          <td class="data-row-value">
            {{ Label({ text = value }) }}
          </td>
        </tr>
      ]], renderGlobals)

      --- This function renders anything AR-related, it has support for smooth mode, so it renders both latest and previous frame data
      local renderAR = SmartTemplate([[
        <div class="wlhud-ar-elements">
          {%
            if currentPointingAt then
              currentPointingAtOnScreen = WorldCoordinate(currentPointingAt)
            end
            if currentMotion then
              currentMotionOnScreen = WorldCoordinate(currentMotion)
            end
          %}

          {% if Exists(currentDestination) then %}
            {{ UI.DestinationMarker({ title = currentDestination.name, position = currentDestination.position, currentCelestialBody = currentCelestialBody, destinationCelestialBody = destinationCelestialBody, speed = currentDestinationApproachSpeed }) }}
          {% end %}

          {% if Exists(warp) then %}
            {{ UI.WarpMarker({ position = warp.closestPoint }) }}
          {% end %}

          {% if Exists(currentPointingAtOnScreen) then %}
            {{ UI.Crosshair(currentPointingAtOnScreen) }}
          {% end %}

          {% if Exists(currentMotionOnScreen) then %}
            {{ UI.Diamond(currentMotionOnScreen) }}
          {% end %}
        </div>
      ]], renderGlobals)
      
      --- This function renders all other static elements, it doesn't have support for smooth mode and will only render the latest data
      local renderUI = SmartTemplate([[
      {% if Exists(info) then %}
      {%
        local burnTimes = info.burnTimes
      %}
        <style>
        .wlhud-main {
          font-size: {{ HudScale }}em;
        }

        .wlhud-fps {
          position: absolute;
          top: 1rem;
          left: 1rem;

          font-size: 0.5em;
        }

        .wlhud-info {
          position: absolute;
          bottom: 5%;
          left: 50%;
          transform: translateX(-50%);

          display: flex;
          flex-direction: column;
          align-items: center;
          
          font-size: 0.8em;
        }
        
        .wlhud-info-speed,
        .wlhud-info-altitude {
          position: absolute;
          top: 50%;
          margin-top: -1.6em;

          display: flex;
          flex-direction: column;

          font-size: 0.64em;
        }

        .wlhud-info-speed {
        {% if UseArchHudPositioning then %}
          left: 70%;
          align-items: flex-start;
        {% else %}
          right: 70%;
          align-items: flex-end;
        {% end %}
        }

        .wlhud-info-altitude {
        {% if UseArchHudPositioning then %}
          right: 70%;
          align-items: flex-end;
        {% else %}
          left: 70%;
          align-items: flex-start;
        {% end %}
        }

        .data-row-label {
          text-align: right;
        }
        .data-row-value {
          padding-left: 0.5em;
        }

        .wlhud-fuel {
          display: flex;
          flex-direction: row;
          align-items: flex-end;
        }
        .wlhud-fuel-type {
          display: flex;
          flex-direction: column;
          align-items: center;
        }
        .wlhud-fuel-type > div {
          margin: 0px 0.4em;
        }
        .wlhud-fuel-type-tanks {
          display: flex;
          flex-direction: row;
        }
        .wlhud-fuel-type-tanks > div {
          margin: 0px 0.1em;

          background: {{ Colors.ShadowLight }};
          box-shadow: 0px 0px 0.125em {{ Colors.Shadow }}, 0px 0px 0.250em #000;
        }
        .wlhud-fuel-type + .wlhud-fuel-type { margin-top: 1em; }
        </style>

        <div class="wlhud-main">
        {% if currentFps then %}
          <div class="wlhud-fps">
            {{ Label({ text = 'FPS: ' .. Round(currentFps, 0), weight = 'bold' }) }}
          </div>
        {% end %}

          <div class="wlhud-info-speed">
            {{ Label({ text = MetersPerSecond(currentSpeed, true), size = 2 }) }}
          {% if info.isThrottleMode then %}
            {{ Label({ text = 'THROTTLE: ' .. Percentage(info.throttleValue), weight = 'bold' }) }}
          {% elseif info.isCruiseMode then %}
            {{ Label({ text = 'CRUISE: ' .. KilometersPerHour(info.throttleValue), weight = 'bold' }) }}
          {% end %}
            {{ Label({ text = 'ACCEL: ' .. Round(info.accelerationInGs, 1) .. 'g' .. ' — ' .. Round(info.accelerationInMs2, 1) .. 'm/s²', weight = 'bold' }) }}
          </div>

        {% if currentCelestialBody then %}
          <div class="wlhud-info-altitude">
            {{ Label({ text = currentCelestialBody.info.name or 'Unknown Location', weight = 'bold' }) }}
          {% if currentCelestialBody.coordinates.alt >= 100000 then %}
            {{ Label({ text = Round(currentCelestialBody.coordinates.alt / 1000, 2) .. 'km', size = 2 }) }}
          {% else %}
            {{ Label({ text = Round(currentCelestialBody.coordinates.alt) .. 'm', size = 2 }) }}
          {% end %}
            {{ Label({ text = 'VSPD: ' .. MetersPerSecond(currentSpeedVertical), weight = 'bold' }) }}
          </div>
        {% end %}

          <div class="wlhud-info">
            <table>
            {% if Exists(burnTimes) and burnTimes.min and burnTimes.max and burnTimes.min < 86400 then %}
              {% if burnTimes.min == burnTimes.max then %}
                {{ UI.DataRow({ label = 'Burn Time:', value = Time(burnTimes.min, true) }) }}
              {% else %}
                {{ UI.DataRow({ label = 'Burn Time Min.:', value = Time(burnTimes.min, true) }) }}
                {{ UI.DataRow({ label = 'Burn Time Max.:', value = Time(burnTimes.max, true) }) }}
              {% end %}
            {% end %}
            </table>

            <div class="wlhud-fuel">
            {% for _, fuelType in pairs(info.fuel) do %}
              {% local tankTypeColor = GetHudColor() %}
              {% if #fuelType.tanks > 0 then %}
                <div class="wlhud-fuel-type">
                  <div class="wlhud-fuel-type-tanks">
                  {% for _, tank in pairs(fuelType.tanks) do %}
                    {% if tank.level < 0.2 or (tank.timeLeft and tank.timeLeft < 60) then %}
                      {% tankTypeColor = '#F70' %}
                      {{ UI.ProgressVertical({ height = 4, width = 0.5, progress = tank.level, stroke = tankTypeColor, color = tankTypeColor }) }}
                    {% else %}
                      {{ UI.ProgressVertical({ height = 4, width = 0.5, progress = tank.level }) }}
                    {% end %}
                  {% end %}
                  </div>
                  <div>{{ Label({ text = fuelType.label, size = 0.8, color = tankTypeColor })}}</div>
                </div>
              {% end %}
            {% end %}
            </div>
          </div>
        </div>
      {% end %}
      ]], renderGlobals)

      --- This is what actually renders to the screen
      return function(data)
        local smoothModeTickRate = hudTickRate / 2

        -- Renders our UI
        local renderedAR = renderAR(data or {})
        local renderedUI = renderUI(data or {})

        -- Composes our AR stuff for smooth mode
        local composedAR = renderedAR
        if enableSmoothMode then
          composedAR = table.concat({
            ([[
              <style>
                .ui-frame-1 .wlhud-static-elements {
                  visibility: hidden;
                }
                .ui-frame-1 .wlhud-ar-elements {
                  animation: f1 0s linear %.4fs 1 normal forwards;
                }
                .ui-frame-2 .wlhud-ar-elements {
                  animation: f2 0s linear %.4fs 1 normal forwards;
                  visibility: hidden;
                }
                
                @keyframes f1 {
                  from {
                    visibility: visible;
                  }
                  to {
                    visibility: hidden;
                  }
                }
                @keyframes f2 {
                  from {
                    visibility: hidden;
                  }
                  to {
                    visibility: visible;
                  }
                }
              </style>
            ]]):format(smoothModeTickRate, smoothModeTickRate),
            ('<div class="ui-frame-1">%s</div>'):format(previousBuffer),
            ('<div class="ui-frame-2">%s</div>'):format(renderedAR),
          })
          previousBuffer = renderedAR
        end

        userScreen = composedAR .. renderedUI
      end
    end)()

    --[[
      Event bindings
    ]]

    -- This is our main render function
    local function onRenderFrame()
      -- This is our current AP/IPH destination
      local currentPosition = vec3(construct.getWorldPosition())

      -- This is our current AP/IPH destination
      local currentDestination = getCurrentDestination()

      -- Pre-calculates some vectors
      local worldVertical = vec3(core.getWorldVertical())
      local worldVelocity = vec3(construct.getWorldVelocity())
      local worldAcceleration = vec3(construct.getWorldAcceleration())
      local atmoDensity = unit.getAtmosphereDensity()

      -- This is our current celestial body and coordinates
      local currentCelestialBody, currentCelestialBodyCoordinates = getClosestCelestialBody(currentPosition), nil
      if currentCelestialBody then
        currentCelestialBodyCoordinates = getLatLonAltFromWorldPosition(currentPosition, currentCelestialBody)
      end

      -- This is our current AP/IPH destination in lat/lon/alt space, along with what celestial body it is
      local currentDestinationCelestialBody, currentDestinationCelestialBodyCoordinates = nil, nil
      if currentDestination then
        currentDestinationCelestialBody = getClosestCelestialBody(currentDestination.position)
        if currentDestinationCelestialBody then
          currentDestinationCelestialBodyCoordinates = getLatLonAltFromWorldPosition(currentDestination.position, currentDestinationCelestialBody)
        end
      end

      -- Prepares data for our current and destination celestial body
      local currentCelestialBodyInfo, destinationCelestialBodyInfo = nil, nil
      if currentCelestialBody and currentCelestialBodyCoordinates then
        currentCelestialBodyInfo = {
          info = currentCelestialBody,
          coordinates = currentCelestialBodyCoordinates,
        }
      end
      if currentDestinationCelestialBody and currentDestinationCelestialBodyCoordinates then
        destinationCelestialBodyInfo = {
          info = currentDestinationCelestialBody,
          coordinates = currentDestinationCelestialBodyCoordinates,
        }
      end

      -- Is destination on same celestial body
      local isDestinationOnSameCelestialBody = false
      if currentCelestialBody and currentDestinationCelestialBody and currentCelestialBody.id == currentDestinationCelestialBody.id then
        isDestinationOnSameCelestialBody = true
      end

      -- This is our current direction forward
      local currentPointingAt = getCurrentPointedAt()

      -- This is our current motion vector
      local currentMotion = getCurrentMotion()

      -- Let's calculate whether we're getting closer to our destination or not
      local currentDestinationApproachSpeed = nil
      if isDestinationOnSameCelestialBody then
        currentDestinationApproachSpeed = worldVelocity:len()
      elseif currentDestination then
        local destinationVector = (currentDestination.position - currentPosition):normalize()
        currentDestinationApproachSpeed = destinationVector:dot(worldVelocity)
      end

      -- Warp information when leaving a planet, not necessary for space
      local warpInfo = nil
      if links.warpdrive and links.warpdrive.getDestination() and links.warpdrive.getDestination() ~= 0 and currentCelestialBody then
        -- Calculate closest warp point
        local minWarpDistance = 2 * currentCelestialBody.radius
        local celestialBodyPosition = vec3(currentCelestialBody.center)
        local celestialBodyOffset = currentPosition - celestialBodyPosition

        -- This is only really necessary if we're closer than the warp point, otherwise we don't need to render it on-screen
        if celestialBodyOffset:len() < minWarpDistance then
          local closestWarpPoint = celestialBodyPosition + celestialBodyOffset:normalize() * minWarpDistance

          warpInfo = {
            destination = links.warpdrive.getDestinationName(),
            closestPoint = closestWarpPoint,
          }
        end
      end

      -- Lite HUD
      local extraHudInfo = nil
      if enableLiteHud and not showHud then
        local atmo, burnTimeAtmo = getFuelLevels('atmo')
        local space, burnTimeSpace = getFuelLevels('space')
        local rocket, burnTimeRocket = getFuelLevels('rocket')

        local function getMinAndMaxFromMultipleSources(...)
          local sources = {...}
          local min, max = nil, nil

          for _, source in pairs(sources) do
            -- Min value
            if min and source.min then
              min = math.min(min, source.min)
            elseif source.min then
              min = source.min
            end

            -- Max value
            if max and source.max then
              max = math.min(max, source.max)
            elseif source.max then
              max = source.max
            end
          end

          return { min = min, max = max }
        end

        -- Gets min/max burn times
        local burnTimes = nil
        if atmoDensity > 0.10 then
          -- We're in atmo
          burnTimes = getMinAndMaxFromMultipleSources(burnTimeAtmo, burnTimeRocket)
        elseif atmoDensity <= 0.10 and atmoDensity > 0 then
          -- We're in atmo-space transition
          burnTimes = getMinAndMaxFromMultipleSources(burnTimeAtmo, burnTimeSpace, burnTimeRocket)
        else
          -- We're in space
          burnTimes = getMinAndMaxFromMultipleSources(burnTimeSpace, burnTimeRocket)
        end

        -- Pushes the HUD info to template
        extraHudInfo = {
          throttleValue = unit.getAxisCommandValue(0),
          isThrottleMode = unit.getControlMode() == 0,
          isCruiseMode = unit.getControlMode() == 1,
          acceleration = worldAcceleration:len(),
          accelerationInGs = worldAcceleration:len() / core.getGravityIntensity(),
          accelerationInMs2 = worldAcceleration:len(),
          burnTimes = burnTimes,
          fuel = {
            { tanks = atmo, burnTimes = burnTimeAtmo, label = 'Atmo' },
            { tanks = space, burnTimes = burnTimeSpace, label = 'Space' },
            { tanks = rocket, burnTimes = burnTimeRocket, label = 'Rocket' },
          }
        }
      end

      -- This will print all data with our template
      render({
        info = extraHudInfo,
        currentDestination = currentDestination,
        currentDestinationApproachSpeed = currentDestinationApproachSpeed,
        currentPointingAt = currentPointingAt,
        currentMotion = currentMotion,
        currentSpeed = worldVelocity:len(),
        currentSpeedVertical = -worldVertical:dot(worldVelocity),
        warp = warpInfo,

        -- Routing utilities
        currentCelestialBody = currentCelestialBodyInfo,
        destinationCelestialBody = destinationCelestialBodyInfo,

        -- Shows current FPS
        currentFps = (showFramesPerSecond and currentFps) or nil,
      })
    end
    
    -- Overrides our render functions
    local function onStart()
      for global, value in pairs(_G) do
        if global:find('Unit') then
          -- Is this the Control Unit (or "unit" global, which for some reason is not present on global environment)
          if 'table' == type(value) then
            if 'function' == type(value.exit) and 'function' == type(value.setTimer) then
              unit = value

              -- Detects all linked elements
              for key, value in pairs(unit) do
                if 'table' == type(value) and 'function' == type(value.getElementClass) then
                  links[key] = value

                  -- Detects Core Unit
                  if 'function' == type(value.getElementIdList) then
                    core = value
                  end
                end
              end

              -- Stops processing
              break
            end
          end
        end
      end

      -- Pre-calculate Alioth's gravity at 0m (our 1g reference)
      referenceGravity1g = getGravitationalForceAtAltitude(0, atlas[2])

      -- This will allow or not hooks
      local isHookingPossible = true

      if not unit then
        system.print('WARNING: Control Unit was not found! AR will not be installed.')
        isHookingPossible = false
      end

      if not core then
        system.print('WARNING: Core Unit was not found! AR will not be installed.')
        isHookingPossible = false
      end

      if not HUD then
        system.print('WARNING: Base HUD was not found! AR will not be installed.')
        isHookingPossible = false
      end

      if isHookingPossible then
        local parentTick = HUD.hudtick
        HUD.hudtick = function()
          onRenderFrame()
          parentTick()
        end
      end
    end

    -- Stubs otherwise the main HUD will crash
    local function onStop() end
    local function onUpdate()
      local tNow = system.getUtcTime()
      currentFps = 1 / (tNow - tLastFrame)
      tLastFrame = tNow

      if not cachedFuelTanks or (tNow - cachedFuelTanks.lastReading) > 1.0 then
        updateFuelLevels()
      end
    end
    local function onFlush() end

    -- This is our use API
    return {
      ExtraOnStart = onStart,
      ExtraOnStop = onStop,
      ExtraOnUpdate = onUpdate,
      ExtraOnFlush = onFlush,
    }
  end)

  if hasInitialized then
    return result
  else
    system.print('Failed to initialize AR HUD!')
    system.print('ERROR: ' .. result)
  end
end)()