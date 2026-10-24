--[[
	CPlusCrowdFilter : three filters for crowded places, each turned on and off
	from its icon, and kept for each character.

	  - Damage numbers: when on, the damage taken by another whose name is
	    blue is not shown ( not overhead, nor in CLifeUI's damage list, chat or
	    file ). The player's own and the player's pets' and summons' are shown.
	  - Object handles: when on, only the handles of the creatures that can be
	    fought ( grey and red names ) and of the player's own pets and summons
	    are made. Other creatures, items and corpses get none.
	  - Spell words overhead: whose spell words are shown overhead, in four
	    states that a press steps through: everyone, the player and the party,
	    the player only, nobody. Talk that is not a spell is always shown, and
	    the chat window is left as it is.

	Besides, before each of the player's own lines goes overhead, the player's
	overhead window is taken off the player and put back on: Default puts it
	on once, at the first line, and a window that comes off a world object
	stays hidden.

	And a light blue arrow over the player's own character, turned on and off
	from its icon too, so that the player can find themselves in a crowd.

	Nothing of CLifeUI is changed or called. The filters are put round
	Default's functions from outside, in this module's initialize:
	DamageWindow.Init, ObjectHandleWindow.retrieveObjectsData and
	OverheadText.ShowOverheadText ( Default and CLifeUI call all three by
	their names ). CPlusCrowdFilter.mod depends on ClfDamageMod and
	ClfTextParse, which replace the first and the last, so that this module
	initializes after them and its wrappers are the outer ones.

	The words are in CPlusCrowdTexts.lua, the icons' drawings in
	CPlusCrowdIcons.xml, the arrow's window in CPlusCrowdSelfArrow.xml.
]]

LoadResources( "./UserInterface/" .. SystemData.Settings.Interface.customUiName .. "/ClfMods/CPlusCrowdFilter", "CPlusCrowdIcons.xml", "CPlusCrowdIcons.xml" )
LoadResources( "./UserInterface/" .. SystemData.Settings.Interface.customUiName .. "/ClfMods/CPlusCrowdFilter", "CPlusCrowdSelfArrow.xml", "CPlusCrowdSelfArrow.xml" )

CPlusCrowdFilter = {}

-- The saved settings, for each character.
local KEY_DAMAGE = "CPlusCrowdFilterDamage"
local KEY_HANDLES = "CPlusCrowdFilterHandles"
local KEY_SPELL_MODE = "CPlusCrowdFilterSpellMode"
local KEY_SELF_ARROW = "CPlusCrowdFilterSelfArrow"

-- The overhead hues of the other icons: on 1152, off 150, a warning 46.
local HUE_ON = 1152
local HUE_OFF = 150
local HUE_WARNING = 46

-- The states of the spell words overhead, in the order a press steps through.
local SPELL_OFF = 0       -- everyone's, as in Default
local SPELL_PARTY = 1     -- the player's and the party's
local SPELL_SELF = 2      -- the player's only
local SPELL_HIDE = 3      -- nobody's, the player's neither
local SPELL_COUNT = 4

-- The words said when a state is chosen ( CPlusCrowdTexts.lua ), by state + 1.
local TID_SPELL_MODE = { 1148, 1149, 1150, 1151 }
-- Added when Default's own option to hide spells overhead is on.
local TID_SPELL_DISABLED_BY_DEFAULT = 1152
local TID_DAMAGE = 1001
local TID_HANDLES = 1002

-- On or off, and the state of the spell words. loadSettings reads them.
CPlusCrowdFilter.Damage = false
CPlusCrowdFilter.Handles = false
CPlusCrowdFilter.SpellMode = SPELL_OFF
CPlusCrowdFilter.SelfArrow = false

-- The functions wrapped, kept to be called inside the wrappers.
CPlusCrowdFilter.DamageInit_org = nil
CPlusCrowdFilter.RetrieveObjectsData_org = nil
CPlusCrowdFilter.ShowOverheadText_org = nil
CPlusCrowdFilter.InitActionData_org = nil


----------------------------------------------------------------
-- Shared pieces
----------------------------------------------------------------

--[[
	The colours of names, as the game gives them ( Default ObjectHandle.lua
	keeps its colour table one up from these ).
]]
CPlusCrowdFilter.NOTORIETY = {
	NONE = 0,
	BLUE = 1,        -- innocent
	GREEN = 2,       -- a friend of the guild
	GREY = 3,        -- can be attacked
	CRIMINAL = 4,    -- grey, a criminal
	ORANGE = 5,      -- an enemy
	RED = 6,         -- a murderer
	YELLOW = 7,      -- invulnerable
}
local NOTORIETY = CPlusCrowdFilter.NOTORIETY

-- One of the player's own pets or summons. IsObjectIdPet is the game's, and is
-- true for the player's summons whatever the colour of their names.
local function isOwnPet( id )
	if ( IsObjectIdPet( id ) ) then
		return true
	end
	return false
end

-- The player, or one of the player's own pets or summons.
local function isSelfOrOwnPet( id )
	if ( id == WindowData.PlayerStatus.PlayerId ) then
		return true
	end
	return isOwnPet( id )
end

local function say( text )
	pcall( Debug.PrintToChat, text )
end

-- The keys whose last failure was said, so that a fault on every line or
-- every handle is said once, not every time.
local ReportedFails = {}

local function reportOnce( key, err )
	if ( ReportedFails[ key ] ) then
		return
	end
	ReportedFails[ key ] = true
	say( towstring( "CPlusCrowdFilter: " .. key .. " failed: " .. tostring( err ) ) )
end


----------------------------------------------------------------
-- The arrow over the player
----------------------------------------------------------------

--[[
	Default puts its own arrow ( MobileArrow ) over the creature under the
	mouse, but never over the player ( Interface.lua:1162-1168 destroys it when
	that creature is the player ). That window is Default's and is not touched
	here: the arrow has a window of its own, from a template of its own
	( CPlusCrowdSelfArrow.xml ).

	An arrow left on something that went out of range stays where it last was,
	and is not seen to come back by itself. So every ARROW_TICK_SECONDS while
	on, the look asks the game whether it knows the player ( IsValidObject,
	GetDistanceFromPlayer ) - known, the arrow is taken off, put on again and
	shown, in the order Default moves its own arrow in ( Interface.lua:1176-1193 );
	not known, it is taken off and hidden. That is what keeps it over the player
	after a warp or a change of area. After the UI is loaded again the window
	is made again at the first look.

	Keeping it light: while off, onUpdate returns at once - no look, nothing
	asked of the game. The window is made once, when first needed, and after
	that only shown, hidden, attached and taken off ( EC gives back next to no
	memory for a destroyed window ).
]]

local ARROW_TEMPLATE = "CPlusCrowdSelfArrowTemplate"
local ARROW = "CPlusCrowdSelfArrowWindow"

-- The size Default gives its own arrow ( Interface.lua:1173 ).
local ARROW_SCALE = 0.4
-- Light blue: told apart from the notoriety colours Default tints its own
-- arrow with ( Source/NameColor.lua:13-21 ).
local ARROW_TINT_R = 0
local ARROW_TINT_G = 220
local ARROW_TINT_B = 255

-- How often the arrow is put on again while on.
local ARROW_TICK_SECONDS = 2

-- Said when the arrow is turned on or off, and when it is turned on while the
-- player's position cannot be had ( CPlusCrowdTexts.lua ).
local TID_SELF_ARROW_ON = 1155
local TID_SELF_ARROW_OFF = 1156
local TID_SELF_ARROW_NO_POSITION = 1157

-- The id the arrow is on, or nil.
local ArrowOn = nil

-- Whether the last look found the player ( knownPlayerId gave an id ).
local ArrowKnown = false

-- Seconds until the next look.
local ArrowWait = 0

-- What has failed already, said once each until the arrow is turned on again:
-- the look runs every few seconds.
local ArrowFailed = {}


local function sayArrowFailed( what, err )
	if ( ArrowFailed[ what ] ) then
		return
	end
	ArrowFailed[ what ] = true
	local errText = "<" .. type( err ) .. ">"
	if ( type( err ) == "string" ) then
		errText = err
	end
	pcall( Debug.PrintToChat, towstring( "CPlusCrowdFilter: " .. what .. " failed: " .. errText ) )
end


-- The arrow window, made the first time it is needed ( and again after the UI
-- is loaded again ) - hidden until it is on the player. Returns whether it is
-- there.
local function ensureArrow()
	if ( DoesWindowExist( ARROW ) ) then
		return true
	end
	ArrowOn = nil
	local ok, err = pcall( CreateWindowFromTemplate, ARROW, ARROW_TEMPLATE, "Root" )
	if ( not ok or not DoesWindowExist( ARROW ) ) then
		if ( ok ) then
			err = "no window"
		end
		sayArrowFailed( "CreateWindowFromTemplate", err )
		return false
	end
	pcall( WindowSetScale, ARROW, ARROW_SCALE )
	pcall( WindowSetTintColor, ARROW, ARROW_TINT_R, ARROW_TINT_G, ARROW_TINT_B )
	pcall( AnimatedImageStartAnimation, ARROW .. "Anim", 1, true, false, 0.0 )
	pcall( WindowSetShowing, ARROW, false )
	return true
end


local function detachArrow()
	if ( ArrowOn ~= nil and DoesWindowExist( ARROW ) ) then
		pcall( DetachWindowFromWorldObject, ArrowOn, ARROW )
	end
	ArrowOn = nil
end


local function hideArrow()
	detachArrow()
	if ( DoesWindowExist( ARROW ) ) then
		pcall( WindowSetShowing, ARROW, false )
	end
end


-- Taken off what it is on, put on the id, then shown. When putting it on
-- fails, it is hidden.
local function attachArrow( id )
	if ( not ensureArrow() ) then
		return
	end
	detachArrow()
	local ok, err = pcall( AttachWindowToWorldObject, id, ARROW )
	if ( not ok ) then
		pcall( WindowSetShowing, ARROW, false )
		sayArrowFailed( "AttachWindowToWorldObject", err )
		return
	end
	ArrowOn = id
	pcall( WindowSetShowing, ARROW, true )
end


--[[
	The player's id when the game knows the player - IsValidObject, and a
	distance of 0 or more - or nil. nil as well before the player is in the
	world ( an id of 0 ), and when asking fails ( said in chat, once ).
]]
local function knownPlayerId()
	local status = WindowData.PlayerStatus
	local id = status and status.PlayerId
	if ( type( id ) ~= "number" or id == 0 ) then
		return nil
	end
	local okValid, valid = pcall( IsValidObject, id )
	if ( not okValid ) then
		sayArrowFailed( "IsValidObject", valid )
		return nil
	end
	if ( not valid ) then
		return nil
	end
	local okDist, dist = pcall( GetDistanceFromPlayer, id )
	if ( not okDist ) then
		sayArrowFailed( "GetDistanceFromPlayer", dist )
		return nil
	end
	if ( type( dist ) ~= "number" ) then
		sayArrowFailed( "GetDistanceFromPlayer", "not a number: " .. type( dist ) )
		return nil
	end
	if ( dist ~= dist ) then
		sayArrowFailed( "GetDistanceFromPlayer", "NaN" )
		return nil
	end
	if ( dist < 0 ) then
		return nil
	end
	return id
end


-- One look: known, the arrow is put on the player again and shown; not
-- known, it is taken off and hidden.
local function lookArrow()
	ArrowKnown = false
	local id = knownPlayerId()
	ArrowKnown = id ~= nil
	if ( id ~= nil ) then
		attachArrow( id )
	else
		hideArrow()
	end
end


-- A look whose fault goes no further: said in chat once, as the arrow's other
-- failures are, and the next look comes all the same.
local function lookArrowGuarded()
	local ok, err = pcall( lookArrow )
	if ( not ok ) then
		sayArrowFailed( "look", err )
	end
end


-- After the setting is read ( loadSettings ): on, the first frame looks - the
-- player may not be in the world yet, and then the next look puts it on; off,
-- the arrow is taken off and hidden.
local function startSelfArrow()
	ArrowFailed = {}
	ArrowWait = 0
	if ( not CPlusCrowdFilter.SelfArrow ) then
		hideArrow()
	end
end


local function setSelfArrow( enable )
	CPlusCrowdFilter.SelfArrow = enable
	Interface.SaveBoolean( KEY_SELF_ARROW, enable )

	local tid = TID_SELF_ARROW_OFF
	local hue = HUE_OFF
	if ( enable ) then
		tid = TID_SELF_ARROW_ON
		hue = HUE_ON
		ArrowFailed = {}
		ArrowWait = ARROW_TICK_SECONDS
		lookArrowGuarded()
	else
		hideArrow()
	end
	pcall( WindowUtils.SendOverheadText, CPlusCrowdTxt.getString( tid ), hue, true )
	--[[
		Turned on while the game does not give the player's position, the arrow
		is not there and would say nothing about it: that is said in chat, once,
		on the press. It stays on, and appears at a later look once the position
		can be had.
	]]
	if ( enable and not ArrowKnown ) then
		pcall( Debug.PrintToChat, CPlusCrowdTxt.getString( TID_SELF_ARROW_NO_POSITION ) )
	end
end


-- The arrow icon: turns it on or off and saves it.
function CPlusCrowdFilter.toggleSelfArrow()
	setSelfArrow( not CPlusCrowdFilter.SelfArrow )
end


-- Every frame ( the .mod's OnUpdate ). Off, it returns at once.
function CPlusCrowdFilter.onUpdate( timePassed )
	if ( not CPlusCrowdFilter.SelfArrow ) then
		return
	end
	if ( type( timePassed ) == "number" ) then
		ArrowWait = ArrowWait - timePassed
	end
	if ( ArrowWait > 0 ) then
		return
	end
	ArrowWait = ARROW_TICK_SECONDS
	lookArrowGuarded()
end


-- The .mod's OnShutdown: the arrow is taken off the player and hidden.
function CPlusCrowdFilter.shutdown()
	hideArrow()
end


----------------------------------------------------------------
-- Settings
----------------------------------------------------------------

--[[
	Reads the saved settings. Called from initialize; called again, it reads
	them anew and puts the module in step with them.
	A saved state of the spell words that is not one of the four is taken as
	OFF and said in the chat; a state other than OFF is said by its name.
	The arrow read on starts to be put on at the next frame; read off, it is
	taken off and hidden.
]]
function CPlusCrowdFilter.loadSettings()
	CPlusCrowdFilter.Damage = ( Interface.LoadBoolean( KEY_DAMAGE, false ) == true )
	CPlusCrowdFilter.Handles = ( Interface.LoadBoolean( KEY_HANDLES, false ) == true )
	CPlusCrowdFilter.SelfArrow = ( Interface.LoadBoolean( KEY_SELF_ARROW, false ) == true )
	startSelfArrow()

	local mode = Interface.LoadNumber( KEY_SPELL_MODE, SPELL_OFF )
	if (
			type( mode ) ~= "number"
			or mode < SPELL_OFF
			or mode >= SPELL_COUNT
			or mode ~= math.floor( mode )
		) then
		say( L"Overhead Spell Mode: unreadable saved value (" .. towstring( tostring( mode ) ) .. L"), OFF" )
		mode = SPELL_OFF
	end
	CPlusCrowdFilter.SpellMode = mode
	if ( mode ~= SPELL_OFF ) then
		say( CPlusCrowdTxt.getString( TID_SPELL_MODE[ mode + 1 ] ) )
	end
end

-- Says a switch's words with ON or OFF: overhead and in the chat, or in the chat only when silent.
local function sayOnOff( tid, enable, silent )
	local text = CPlusCrowdTxt.getString( tid )
	local hue = HUE_OFF
	if ( enable ) then
		text = text .. L"ON"
		hue = HUE_ON
	else
		text = text .. L"OFF"
	end
	if ( not silent ) then
		WindowUtils.SendOverheadText( text, hue, true )
	else
		Debug.PrintToChat( text )
	end
end


----------------------------------------------------------------
-- Damage numbers
----------------------------------------------------------------

--[[
	Whether the damage now handed over ( Damage.mobileId ) is one not to show:
	another's, whose name is blue. The colour is read from what the client has
	of the name, then of the status; nothing is registered for it. Without a
	colour it is shown.
]]
local function hidesDamage()
	local mobileId = Damage and Damage.mobileId
	if ( mobileId == nil or isSelfOrOwnPet( mobileId ) ) then
		return false
	end
	local notoriety = nil
	local name = WindowData.MobileName[ mobileId ]
	if ( name and name.Notoriety ) then
		notoriety = name.Notoriety
	end
	if ( notoriety == nil ) then
		local status = WindowData.MobileStatus[ mobileId ]
		if ( status and status.Notoriety ) then
			notoriety = status.Notoriety
		end
	end
	return notoriety == NOTORIETY.BLUE
end

--[[
	Wraps DamageWindow.Init. When the filter is on and the damage is one not to
	show, the wrapped function is not called, so the number goes nowhere.
	When deciding fails, the damage is shown.
]]
function CPlusCrowdFilter.onDamageInit()
	if ( CPlusCrowdFilter.Damage ) then
		local ok, hide = pcall( hidesDamage )
		if ( not ok ) then
			reportOnce( "damage filter", hide )
		elseif ( hide ) then
			return
		end
	end
	CPlusCrowdFilter.DamageInit_org()
end

-- The damage icon: turns the filter on or off and saves it.
function CPlusCrowdFilter.toggleDamage( silent )
	local enable = not CPlusCrowdFilter.Damage
	CPlusCrowdFilter.Damage = enable
	Interface.SaveBoolean( KEY_DAMAGE, enable )
	sayOnOff( TID_DAMAGE, enable, silent )
end


----------------------------------------------------------------
-- Object handles
----------------------------------------------------------------

-- The six lists of the handles, with one entry for each object, in step.
local HANDLE_LISTS = { "Names", "ObjectId", "XPos", "YPos", "IsMobile", "Notoriety" }

-- Whether the handle at i is kept: a creature that is the player's own pet or
-- summon, or is named grey or red. Grey is 3 and 4: one attacking you is 4.
local function keepsHandle( objectsData, i )
	if ( not objectsData.IsMobile[ i ] ) then
		return false
	end
	if ( isOwnPet( objectsData.ObjectId[ i ] ) ) then
		return true
	end
	local notoriety = objectsData.Notoriety[ i ]
	return notoriety == NOTORIETY.GREY or notoriety == NOTORIETY.CRIMINAL or notoriety == NOTORIETY.RED
end

--[[
	Puts into objectsData new lists that hold only the handles kept, the six
	still in step. The lists of WindowData.ObjectHandle that objectsData was
	handed are not written to. A list that is not there stays not there.
]]
local function narrowHandles( objectsData )
	if (
			type( objectsData.ObjectId ) ~= "table"
			or type( objectsData.IsMobile ) ~= "table"
			or type( objectsData.Notoriety ) ~= "table"
		) then
		error( "the lists of the handles are not there" )
	end
	local kept = {}
	for k = 1, #HANDLE_LISTS do
		if ( objectsData[ HANDLE_LISTS[ k ] ] ~= nil ) then
			kept[ HANDLE_LISTS[ k ] ] = {}
		end
	end
	local count = 0
	for i = 1, #objectsData.ObjectId do
		if ( keepsHandle( objectsData, i ) ) then
			count = count + 1
			for listName, list in pairs( kept ) do
				list[ count ] = objectsData[ listName ][ i ]
			end
		end
	end
	for listName, list in pairs( kept ) do
		objectsData[ listName ] = list
	end
end

--[[
	Wraps ObjectHandleWindow.retrieveObjectsData, from which the handles are
	made ( Default's own making and CLifeUI's both take the list from it ).
	When the filter is on and the list was got, it is narrowed. What the
	wrapped function answers is answered unchanged. When narrowing fails,
	every handle is made.
]]
function CPlusCrowdFilter.onRetrieveObjectsData( objectsData )
	local got = CPlusCrowdFilter.RetrieveObjectsData_org( objectsData )
	if ( got == true and CPlusCrowdFilter.Handles and type( objectsData ) == "table" ) then
		local ok, err = pcall( narrowHandles, objectsData )
		if ( not ok ) then
			reportOnce( "object handle filter", err )
		end
	end
	return got
end

-- The handles icon: turns the filter on or off, saves it, and makes the
-- handles shown now again.
function CPlusCrowdFilter.toggleHandles( silent )
	local enable = not CPlusCrowdFilter.Handles
	CPlusCrowdFilter.Handles = enable
	Interface.SaveBoolean( KEY_HANDLES, enable )
	sayOnOff( TID_HANDLES, enable, silent )

	if ( ObjectHandleWindow and ObjectHandleWindow.Active ) then
		ObjectHandleWindow.DestroyObjectHandles()
		ObjectHandleWindow.CreateObjectHandles()
	end
end


----------------------------------------------------------------
-- Spell words overhead
----------------------------------------------------------------

--[[
	Whether the line now handed over ( SystemData ) is spell words not to show
	overhead: spell words, by the same table Default's
	OverheadText.ShowOverheadText looks them up in, said by one outside the
	state's range. Other players, murderers, monsters and pets are not told
	apart.
]]
local function isHiddenSpell( mobileId )
	local mode = CPlusCrowdFilter.SpellMode
	if ( mode == SPELL_OFF ) then
		return false
	end
	if ( SpellsInfo.SpellsData[ WStringToString( SystemData.Text ) ] == nil ) then
		return false
	end
	if ( mode == SPELL_HIDE ) then
		return true
	end
	if ( mobileId ~= nil and mobileId == WindowData.PlayerStatus.PlayerId ) then
		return false
	end
	if ( mode == SPELL_PARTY and mobileId ~= nil and IsPartyMember( mobileId ) ) then
		return false
	end
	return true
end

--[[
	Takes the player's overhead window off the player and puts it back on,
	every time, without looking whether it came off. With no window yet there
	is nothing to do: the wrapped function makes it and puts it on. Another's
	window is not touched.
]]
local function reattachOwnOverhead( mobileId )
	if ( mobileId == nil or mobileId ~= WindowData.PlayerStatus.PlayerId ) then
		return
	end
	local windowName = "OverheadTextWindow_" .. mobileId
	if ( not DoesWindowExist( windowName ) ) then
		return
	end
	DetachWindowFromWorldObject( mobileId, windowName )
	AttachWindowToWorldObject( mobileId, windowName )
end

--[[
	Wraps OverheadText.ShowOverheadText. Spell words outside the state's range
	return without the wrapped function, and without putting the window back
	on. Every other line puts the player's window back on and goes to the
	wrapped function. SystemData is not written to, so the chat window and
	whatever else reads the line read it as it came. When deciding or putting
	back on fails, the line is shown all the same.
]]
function CPlusCrowdFilter.onShowOverheadText()
	local mobileId = SystemData.TextSourceID

	if ( CPlusCrowdFilter.SpellMode ~= SPELL_OFF ) then
		local ok, hide = pcall( isHiddenSpell, mobileId )
		if ( not ok ) then
			reportOnce( "overhead spell filter", hide )
		elseif ( hide ) then
			return
		end
	end

	local reattached, err = pcall( reattachOwnOverhead, mobileId )
	if ( not reattached ) then
		reportOnce( "own overhead reattach", err )
	end

	CPlusCrowdFilter.ShowOverheadText_org()
end

--[[
	The spell words icon: steps to the next state ( OFF, the player and the
	party, the player only, nobody, OFF ), says it overhead and saves it.
	Default's own option to hide spells overhead is only read: when it is on,
	every spell is hidden whatever the state, and a line says so.
]]
function CPlusCrowdFilter.cycleSpells()
	local mode = ( CPlusCrowdFilter.SpellMode + 1 ) % SPELL_COUNT
	CPlusCrowdFilter.SpellMode = mode
	Interface.SaveNumber( KEY_SPELL_MODE, mode )

	local hue = HUE_ON
	if ( mode == SPELL_OFF ) then
		hue = HUE_OFF
	end
	WindowUtils.SendOverheadText( CPlusCrowdTxt.getString( TID_SPELL_MODE[ mode + 1 ] ), hue, true )

	if ( Interface.DisableSpells ) then
		WindowUtils.SendOverheadText( CPlusCrowdTxt.getString( TID_SPELL_DISABLED_BY_DEFAULT ), HUE_WARNING, true )
	end
end


----------------------------------------------------------------
-- The actions window
----------------------------------------------------------------

--[[
	The icons: { action id, icon id ( CPlusCrowdIcons.xml ), name, what it
	does ( CPlusCrowdTexts.lua ), the macro }. A hotbar slot keeps three things
	of the icon put on it: the action id, the icon id and the macro text, and
	nothing writes the text again at login. None of the three is to change
	without putting the slots right as well.
]]
local ACTIONS = {
	{ 6015, 876015, 3008, 4008, L"script CPlusCrowdFilter.toggleDamage()" },
	{ 6016, 876016, 3009, 4009, L"script CPlusCrowdFilter.toggleHandles()" },
	{ 6033, 876033, 3026, 4026, L"script CPlusCrowdFilter.cycleSpells()" },
	{ 6034, 876034, 3027, 4027, L"script CPlusCrowdFilter.toggleSelfArrow()" },
}

--[[
	The category the icons go in. Every CPlus module looks for it by this name
	and adds to it, and the first to come makes it, at the end of the list:
	Default counts its categories from 1 up, so none is given a number of its
	own.
]]
local ACTION_GROUP = L"CPlus"

-- This module's rows in ActionData, and their numbers in the category CPlus.
-- A number the category already holds is not added again.
local function addActions()
	local data = ActionsWindow.ActionData
	local groups = ActionsWindow.Groups
	local group = nil
	for i = 1, #groups do
		if ( groups[ i ].nameString == ACTION_GROUP ) then
			group = groups[ i ]
			break
		end
	end
	if ( group == nil ) then
		group = { nameString = ACTION_GROUP, index = {} }
		groups[ #groups + 1 ] = group
	end

	local index = group.index
	for i = 1, #ACTIONS do
		local action = ACTIONS[ i ]
		data[ action[ 1 ] ] = {
			type            = SystemData.UserAction.TYPE_SPEECH_USER_COMMAND,
			iconId          = action[ 2 ],
			nameString      = CPlusCrowdTxt.getString( action[ 3 ] ),
			detailString    = CPlusCrowdTxt.getString( action[ 4 ] ),
			callback        = action[ 5 ],
			inActionWindow  = true,
		}
		local listed = false
		for j = 1, #index do
			if ( index[ j ] == action[ 1 ] ) then
				listed = true
				break
			end
		end
		if ( not listed ) then
			index[ #index + 1 ] = action[ 1 ]
		end
	end
end

--[[
	Wraps ActionsWindow.InitActionData, which Default calls every time the
	actions window is made, and which makes ActionData and the categories anew
	each time. The wrapped function runs first.
]]
function CPlusCrowdFilter.onInitActionData()
	CPlusCrowdFilter.InitActionData_org()
	local ok, err = pcall( addActions )
	if ( not ok ) then
		reportOnce( "actions window", err )
	end
end

--[[
	An icon of this module on a hotbar is given its drawing again: an icon a
	module adds is not shown on the hotbar just after logging in.
]]
local function refreshHotbarIcons()
	local data = ActionsWindow.ActionData
	local SPEECH_USER_CMD = SystemData.UserAction.TYPE_SPEECH_USER_COMMAND
	for window, actionId in pairs( HotbarSystem.RegisteredSpellIcons ) do
		local mine = false
		for i = 1, #ACTIONS do
			if ( ACTIONS[ i ][ 1 ] == actionId ) then
				mine = true
				break
			end
		end
		local action = mine and data[ actionId ] or nil
		if ( action and DoesWindowExist( window ) ) then
			local slot = WindowGetId( window )
			local hotbarId = WindowGetId( WindowGetParent( window ) )
			if ( UserActionGetType( hotbarId, slot, 0 ) == SPEECH_USER_CMD ) then
				HotbarSystem.SetHotbarIcon( window, action.iconId )
			end
		end
	end
end

--[[
	Puts the icons into the actions window: wraps ActionsWindow.InitActionData
	once, makes the actions window again if it is there already, so that they
	are in it, and gives the icons on the hotbars their drawings.
]]
local function installActions()
	if ( CPlusCrowdFilter.InitActionData_org ) then
		return
	end
	if ( ActionsWindow == nil or type( ActionsWindow.InitActionData ) ~= "function" ) then
		say( L"CPlusCrowdFilter : hook missing (ActionsWindow.InitActionData)" )
		return
	end
	CPlusCrowdFilter.InitActionData_org = ActionsWindow.InitActionData
	ActionsWindow.InitActionData = CPlusCrowdFilter.onInitActionData

	if ( DoesWindowExist( "ActionsWindow" ) ) then
		local showing = WindowGetShowing( "ActionsWindow" )
		DestroyWindow( "ActionsWindow" )
		CreateWindow( "ActionsWindow", showing )
	end

	local ok, err = pcall( refreshHotbarIcons )
	if ( not ok ) then
		reportOnce( "hotbar icons", err )
	end
end


----------------------------------------------------------------
-- Initialize
----------------------------------------------------------------

--[[
	Reads the settings and puts the three wrappers round Default's functions,
	each once however often this runs. A function that is not there is not
	wrapped, and a line in the chat says which.
]]
function CPlusCrowdFilter.initialize()
	CPlusCrowdFilter.loadSettings()

	if ( CPlusCrowdFilter.DamageInit_org == nil ) then
		if ( DamageWindow ~= nil and type( DamageWindow.Init ) == "function" ) then
			CPlusCrowdFilter.DamageInit_org = DamageWindow.Init
			DamageWindow.Init = CPlusCrowdFilter.onDamageInit
		else
			say( L"CPlusCrowdFilter : hook missing (DamageWindow.Init)" )
		end
	end

	if ( CPlusCrowdFilter.RetrieveObjectsData_org == nil ) then
		if ( ObjectHandleWindow ~= nil and type( ObjectHandleWindow.retrieveObjectsData ) == "function" ) then
			CPlusCrowdFilter.RetrieveObjectsData_org = ObjectHandleWindow.retrieveObjectsData
			ObjectHandleWindow.retrieveObjectsData = CPlusCrowdFilter.onRetrieveObjectsData
		else
			say( L"CPlusCrowdFilter : hook missing (ObjectHandleWindow.retrieveObjectsData)" )
		end
	end

	if ( CPlusCrowdFilter.ShowOverheadText_org == nil ) then
		if ( OverheadText ~= nil and type( OverheadText.ShowOverheadText ) == "function" ) then
			CPlusCrowdFilter.ShowOverheadText_org = OverheadText.ShowOverheadText
			OverheadText.ShowOverheadText = CPlusCrowdFilter.onShowOverheadText
		else
			say( L"CPlusCrowdFilter : hook missing (OverheadText.ShowOverheadText)" )
		end
	end

	installActions()
end
