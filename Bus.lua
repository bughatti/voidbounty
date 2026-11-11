----------------------------------------------------------------------
-- VoidBounty: the message bus (no transport here: Net.lua plugs in the Forever whisper network,
-- the tests plug in a fake one).
--
-- A message is "T~field~field..." (<= 250 bytes). Everyone's client applies the same rules, and
-- the one thing that can't be forged is the SENDER: the game names who whispered. So a writ,
-- an accept, a claim, a tribute pick, a payment only counts when it comes from the player it
-- is about (Writs.lua checks that). Inbound is untrusted: strict field checks, a per-sender
-- rate limit, names cleaned.
----------------------------------------------------------------------
local ADDON, ns = ...
if (select(4, GetBuildInfo()) or 0) >= 100000 then return end

local B = { handlers = {}, sent = 0, heard = 0, people = {} }
ns.Bus = B

local SEP = "~"
local MAX_LEN = 250
local PER_MIN = 40            -- messages accepted per sender per minute

-- Network names: "First Surname" (letters, apostrophe, space, hyphen), max 40 bytes.
function B.CleanName(s)
    -- refused, not cleaned: no real name has a control char, "|" (an escape code) or "~"
    if type(s) ~= "string" or s:find("[%c|~]") then return nil end
    if s == "" or #s > 40 or s:find("[^%w%s'%-\128-\255]") then return nil end
    return s
end

function B.IsGUID(s) return type(s) == "string" and s:match("^Player%-%d+%-%x+$") ~= nil end

function B.On(kind, fn) B.handlers[kind] = fn end

function B.Pack(...)
    local t = { ... }
    for i = 1, #t do
        local v = t[i]
        if v == nil then v = "" end
        v = tostring(v):gsub("[~|%c]", "")
        t[i] = v
    end
    local msg = table.concat(t, SEP)
    if #msg > MAX_LEN then return nil end
    return msg
end

-- Send to one player (to = name) or spread to the network (to = nil). Returns false when
-- there's no network (alone, retail, blocked).
-- the writ messages: off while writs are "coming soon" (Core.lua ns.WRITS)
local WRIT_KINDS = { W = true, w = true, A = true, C = true, T = true, P = true, R = true, X = true, Q = true }
B.WRIT_KINDS = WRIT_KINDS

function B.Send(msg, to)
    if not msg or not B.transport or ns.demoDB then return false end   -- the demo board never sends
    if not ns.WRITS and WRIT_KINDS[msg:match("^([^~]*)")] then return false end
    B.sent = B.sent + 1
    return B.transport(msg, to)
end

local rate = {}   -- [sender] = { minute, count }
function B.Receive(msg, sender, me)
    if type(msg) ~= "string" or #msg > MAX_LEN + 5 then return end
    sender = B.CleanName(sender)
    if not sender or sender == me then return end
    local m = math.floor(time() / 60)
    local r = rate[sender]
    if not r or r[1] ~= m then r = { m, 0 }; rate[sender] = r end
    r[2] = r[2] + 1
    if r[2] > PER_MIN then return end
    local f = {}
    for part in (msg .. SEP):gmatch("(.-)" .. SEP) do f[#f + 1] = part end
    local fn = B.handlers[f[1]]
    if not fn then return end
    if not ns.WRITS and WRIT_KINDS[f[1]] then return end
    B.heard = B.heard + 1
    B.people[sender] = (B.people[sender] or 0) + 1
    local ok, err = pcall(fn, f, sender)
    if not ok and ns.debug then ns.say("bad message from " .. sender .. ": " .. tostring(err)) end
end
