--------------------------------------------------------------------------------
-- This file is part of the JX3 Plugin Project.
-- @desc     : 时间周期函数模块
-- @copyright: Copyright (c) 2009 Kingsoft Co., Ltd.
--------------------------------------------------------------------------------
---@class (partial) MY
local X = MY
--------------------------------------------------------------------------------
local MODULE_PATH = X.NSFormatString('{$NS}_!Base/lib/Interval')
--------------------------------------------------------------------------------
--[[#DEBUG BEGIN]]X.ReportModuleLoading(MODULE_PATH, 'START')--[[#DEBUG END]]
--------------------------------------------------------------------------------

---------------------------------------------------------------------
-- 时钟函数管理中心
---------------------------------------------------------------------
-- 函数        名称        用处         时间单位    最小时间精度(ms)
-- DelayCall   延迟调用   倒计时         毫秒       1 / GLOBAL.GAME_FPS
-- BreatheCall 呼吸调用   每帧调用       毫秒       1 / GLOBAL.GAME_FPS
-- FrameCall   按帧调用   每帧调用       呼吸帧     1 / GLOBAL.GAME_FPS
-- RenderCall  渲染调用   每次渲染调用   毫秒       1 / 每秒渲染次数
-- Debounce    调用防抖   延迟调用一次   毫秒       1 / GLOBAL.GAME_FPS
-- Throttle    调用节流   分段频率限制   毫秒       1 / GLOBAL.GAME_FPS
-- FinallyThrottle 确保延迟调用的节流    毫秒       1 / GLOBAL.GAME_FPS
---------------------------------------------------------------------
if DelayCall and BreatheCall and FrameCall and RenderCall then
	local NS_PREFIX = X.NSFormatString('{$NS}__')
	local function WrapIntervalCall(szIntervalName, IntervalCall)
		-- 游戏结束时清理注册防止异常
		local tRegKeys, bRegClosed = {}, false
		local function OnRegClose()
			for k, _ in pairs(tRegKeys) do
				IntervalCall(k, false)
			end
			tRegKeys, bRegClosed = nil, true
			UnRegisterEvent('GAME_EXIT', OnRegClose)
			UnRegisterEvent('PLAYER_EXIT_GAME', OnRegClose)
			UnRegisterEvent('RELOAD_UI_ADDON_BEGIN', OnRegClose)
		end
		RegisterEvent('GAME_EXIT', OnRegClose)
		RegisterEvent('PLAYER_EXIT_GAME', OnRegClose)
		RegisterEvent('RELOAD_UI_ADDON_BEGIN', OnRegClose)
		-- 注册函数
		return function(szKey, nInterval, fnAction, oArg)
			if bRegClosed then
				return
			end
			local bUnReg
			if type(szKey) == 'function' then
				-- DelayCall(fnAction[, oArg])
				szKey, nInterval, fnAction, oArg = nil, 0, szKey, nInterval
			elseif type(szKey) == 'number' then
				-- DelayCall(nInterval, fnAction[, oArg])
				szKey, nInterval, fnAction, oArg = nil, szKey, nInterval, fnAction
			elseif type(nInterval) == 'function' then
				-- DelayCall(szKey, fnAction[, oArg])
				nInterval, fnAction, oArg = 0, nInterval, fnAction
			elseif type(nInterval) == 'boolean' then
				-- DelayCall(szKey, false)
				nInterval, bUnReg = nil, true
			elseif nInterval and type(fnAction) ~= 'function' then
				-- DelayCall(szKey, nInterval)
				fnAction = nil
			end
			if fnAction then -- reg
				--[[#DEBUG BEGIN]]
				local f = fnAction
				local function GetXpCallReturnVal(res, ...)
					if res then
						return ...
					end
					local xpErrMsg, xpTraceback = ...
					local xpErrLog = szIntervalName .. ' failed: '
						.. tostring(xpErrMsg or '') .. '\n' .. tostring(xpTraceback or '')
					Log(xpErrLog)
					FireUIEvent('CALL_LUA_ERROR', xpErrLog .. '\n')
				end
				fnAction = function(...)
					return GetXpCallReturnVal(X.XpCall(f, ...))
				end
				--[[#DEBUG END]]
				if not szKey then -- 匿名调用
					szKey = GetTickCount()
					while IntervalCall(NS_PREFIX .. tostring(szKey)) do
						szKey = szKey + 0.1
					end
					szKey = tostring(szKey)
				end
			end
			if not X.IsString(szKey) then
				assert(false, 'IntervalCall Key MUST be string.')
			end
			local szNSKey = NS_PREFIX .. szKey
			if bUnReg then
				tRegKeys[szNSKey] = nil
			else
				tRegKeys[szNSKey] = true
			end
			local aRetVal = bUnReg
				and X.Pack(IntervalCall(szNSKey, false))
				or X.Pack(IntervalCall(szNSKey, nInterval, fnAction, oArg))
			if X.IsString(aRetVal[1]) then
				aRetVal[1] = szKey
			end
			return X.Unpack(aRetVal)
		end
	end
	X.DelayCall   = WrapIntervalCall('DelayCall'  , DelayCall  )
	X.BreatheCall = WrapIntervalCall('BreatheCall', BreatheCall)
	X.FrameCall   = WrapIntervalCall('FrameCall'  , FrameCall  )
	X.RenderCall  = WrapIntervalCall('RenderCall' , RenderCall )
else

local _time      -- current time
local _count = 0 -- the count of onactive
local _no_active

local function LuaActive_Enable(bEnable)
	_no_active = not bEnable
end

--================================= breathe call ================================================
-- DelayCall(szKey, nInterval, fnAction, oArg)
-- DelayCall('CASTING') -- 获取名称为CASTING的DelayCall的信息
-- DelayCall('CASTING', false) -- 注销名称为CASTING的DelayCall
-- DelayCall('CASTING', function() end, oArg) -- 注册名称为CASTING调用间隔为最小值的DelayCall
-- DelayCall('CASTING', 100, function() end, oArg) -- 注册名称为CASTING调用间隔为100的DelayCall
-- DelayCall('CASTING', 200) -- 把名称为CASTING的DelayCall调用时间改为200毫秒
--===============================================================================================
local _tDelayCall = {} -- bc表 键值对集合
local _delaycalls = {} -- a mirror table to avoid error: invalid key to 'next'
local _delaycall_t   -- 循环使用bc表 减少频繁注册反注册时新建表的开销

local function onDelayCall()
	_time = GetTime()
	-- create mirror
	for szKey, dc in pairs(_tDelayCall) do
		_delaycalls[szKey] = dc
	end
	-- traverse dc calls
	for szKey, dc in pairs(_delaycalls) do
		if dc.nNext <= _time then
			local res, err, trace = X.XpCall(dc.fnAction, dc.oArg)
			if not res then
				X.ErrorLog(err, 'onDelayCall: ' .. szKey, trace)
			end
			_count = _count - 1
			_delaycall_t = _tDelayCall[szKey]
			_tDelayCall[szKey] = nil
			if _count == 0 then
				LuaActive_Enable(false)
			end
		end
		_delaycalls[szKey] = nil
	end
end

function X.DelayCall(szKey, nInterval, fnAction, oArg)
	local bUnreg
	if type(szKey) == 'function' then
		-- DelayCall(fnAction[, oArg])
		szKey, nInterval, fnAction, oArg = nil, 0, szKey, nInterval
	elseif type(szKey) == 'number' then
		-- DelayCall(nInterval, fnAction[, oArg])
		szKey, nInterval, fnAction, oArg = nil, szKey, nInterval, fnAction
	elseif type(nInterval) == 'function' then
		-- DelayCall(szKey, fnAction[, oArg])
		nInterval, fnAction, oArg = 0, nInterval, fnAction
	elseif type(nInterval) == 'boolean' then
		-- DelayCall(szKey, false)
		nInterval, bUnreg = nil, true
	elseif nInterval and type(fnAction) ~= 'function' then
		-- DelayCall(szKey, nInterval)
		fnAction = nil
	end
	if fnAction then -- reg
		if not szKey then -- 匿名bc调用
			szKey = GetTickCount()
			while _tDelayCall[tostring(szKey)] do
				szKey = szKey + 0.1
			end
			szKey = tostring(szKey)
		end
		if not _tDelayCall[szKey] then
			_tDelayCall[szKey] = _delaycall_t or {}
			_delaycall_t = nil
			_count = _count + 1
			LuaActive_Enable(true)
		end
		local dc = _tDelayCall[szKey]
		dc.fnAction = fnAction
		dc.oArg = oArg
		dc.nNext = GetTime() + nInterval
		dc.nInterval = nInterval or 0
	elseif nInterval then -- modify
		local dc = _tDelayCall[szKey]
		if dc then
			dc.nInterval = nInterval
			dc.nNext = GetTime() + nInterval
		end
	elseif szKey and bUnreg then -- unreg
		if _tDelayCall[szKey] then
			_count = _count - 1
			_delaycall_t = _tDelayCall[szKey]
			_tDelayCall[szKey] = nil
			if _count == 0 then
				LuaActive_Enable(false)
			end
		end
	elseif szKey then -- get registered breathecall info
		local dc = _tDelayCall[szKey]
		if dc then
			return szKey, dc.nInterval, dc.nNext - GetTime()
		end
		return
	end
	return szKey
end

--================================= breathe call ================================================
-- BreatheCall(szKey, nInterval, fnAction, oArg)
-- BreatheCall('CASTING') -- 获取名称为CASTING的BreatheCall的信息
-- BreatheCall('CASTING', false) -- 注销名称为CASTING的BreatheCall
-- BreatheCall('CASTING', function() end, oArg) -- 注册名称为CASTING调用间隔为最小值的BreatheCall
-- BreatheCall('CASTING', 100, function() end, oArg) -- 注册名称为CASTING调用间隔为100的BreatheCall
-- BreatheCall('CASTING', 200) -- 把名称为CASTING的BreatheCall调用间隔改为200毫秒
-- BreatheCall('CASTING', 200, true) -- 把名称为CASTING的BreatheCall下次调用延迟改为200毫秒
-- 注：fnAction返回0表示从BreatheCall中移除自己
--===============================================================================================
local _tBreatheCall = {} -- bc表 键值对集合
local _breathecalls = {} -- a mirror table to avoid error: invalid key to 'next'
local _breathecall_t   -- 循环使用bc表 减少频繁注册反注册时新建表的开销

local function onBreatheCall()
	_time = GetTime()
	-- create mirror
	for szKey, bc in pairs(_tBreatheCall) do
		_breathecalls[szKey] = bc
	end
	-- traverse bc calls
	for szKey, bc in pairs(_breathecalls) do
		if bc.nNext <= _time then
			bc.nNext = _time + bc.nInterval
			local res, err, trace = X.XpCall(bc.fnAction, bc.oArg)
			if not res then
				X.ErrorLog(err, 'onBreatheCall: ' .. szKey, trace)
			elseif err == 0 then
				_count = _count - 1
				_breathecall_t = _tBreatheCall[szKey]
				_tBreatheCall[szKey] = nil
				if _count == 0 then
					LuaActive_Enable(false)
				end
			end
		end
		_breathecalls[szKey] = nil
	end
end

function X.BreatheCall(szKey, nInterval, fnAction, oArg)
	local bOnce, bUnreg
	if type(szKey) == 'function' then
		-- BreatheCall(fnAction[, oArg])
		szKey, nInterval, fnAction, oArg = nil, 0, szKey, nInterval
	elseif type(szKey) == 'number' then
		-- BreatheCall(nInterval, fnAction[, oArg])
		szKey, nInterval, fnAction, oArg = nil, szKey, nInterval, fnAction
	elseif type(nInterval) == 'function' then
		-- BreatheCall(szKey, fnAction[, oArg])
		nInterval, fnAction, oArg = 0, nInterval, fnAction
	elseif type(nInterval) == 'boolean' then
		-- BreatheCall(szKey, false)
		nInterval, bUnreg = nil, true
	elseif nInterval and type(fnAction) ~= 'function' then
		-- BreatheCall(szKey, nInterval, bOnce)
		fnAction, bOnce = nil, fnAction
	end
	if fnAction then -- reg
		if not szKey then -- 匿名bc调用
			szKey = GetTickCount()
			while _tBreatheCall[tostring(szKey)] do
				szKey = szKey + 0.1
			end
			szKey = tostring(szKey)
		end
		if not _tBreatheCall[szKey] then
			_tBreatheCall[szKey] = _breathecall_t or {}
			_breathecall_t = nil
			_count = _count + 1
			LuaActive_Enable(true)
		end
		local bc = _tBreatheCall[szKey]
		bc.fnAction = fnAction
		bc.oArg = oArg
		bc.nNext = GetTime()
		bc.nInterval = nInterval or 0
	elseif nInterval then -- modify
		local bc = _tBreatheCall[szKey]
		if bc then
			if not bOnce then
				bc.nInterval = nInterval
			end
			bc.nNext = GetTime() + nInterval
		end
	elseif szKey and bUnreg then -- unreg
		if _tBreatheCall[szKey] then
			_count = _count - 1
			_breathecall_t = _tBreatheCall[szKey]
			_tBreatheCall[szKey] = nil
			if _count == 0 then
				LuaActive_Enable(false)
			end
		end
	elseif szKey then -- get registered breathecall info
		local bc = _tBreatheCall[szKey]
		if bc then
			return szKey, bc.nInterval, bc.nNext - GetTime()
		end
		return
	end
	return szKey
end

--================================= frame call ==================================================
-- FrameCall(szKey, nInterval, fnAction, oArg)
-- FrameCall('CASTING') -- 获取名称为CASTING的FrameCall的信息
-- FrameCall('CASTING', false) -- 注销名称为CASTING的FrameCall
-- FrameCall('CASTING', function() end, oArg) -- 注册名称为CASTING调用间隔为最小值的FrameCall
-- FrameCall('CASTING', 10, function() end, oArg) -- 注册名称为CASTING调用间隔为100帧的FrameCall
-- FrameCall('CASTING', 20) -- 把名称为CASTING的FrameCall调用间隔改为20帧
-- FrameCall('CASTING', 20, true) -- 把名称为CASTING的FrameCall下次调用延迟改为20帧
-- 注：fnAction返回0表示从FrameCall中移除自己
--===============================================================================================
local _tFrameCall = {} -- fc表 键值对集合
local _framecalls = {} -- a mirror table to avoid error: invalid key to 'next'
local _framecount = 0  -- 帧计数器
local _framecall_t   -- 循环使用fc表 减少频繁注册反注册时新建表的开销

local function onFrameCall()
	_framecount = _framecount + 1
	-- create mirror
	for szKey, fc in pairs(_tFrameCall) do
		_framecalls[szKey] = fc
	end
	-- traverse fc calls
	for szKey, fc in pairs(_framecalls) do
		if fc.nNext <= _framecount then
			fc.nNext = _framecount + fc.nInterval
			local res, err, trace = X.XpCall(fc.fnAction, fc.oArg)
			if not res then
				X.ErrorLog(err, 'onFrameCall: ' .. szKey, trace)
			elseif err == 0 then
				_count = _count - 1
				_framecall_t = _tFrameCall[szKey]
				_tFrameCall[szKey] = nil
				if _count == 0 then
					LuaActive_Enable(false)
				end
			end
		end
		_framecalls[szKey] = nil
	end
end

function X.FrameCall(szKey, nInterval, fnAction, oArg)
	local bOnce, bUnreg
	if type(szKey) == 'function' then
		-- FrameCall(fnAction[, oArg])
		szKey, nInterval, fnAction, oArg = nil, 0, szKey, nInterval
	elseif type(szKey) == 'number' then
		-- FrameCall(nInterval, fnAction[, oArg])
		szKey, nInterval, fnAction, oArg = nil, szKey, nInterval, fnAction
	elseif type(nInterval) == 'function' then
		-- FrameCall(szKey, fnAction[, oArg])
		nInterval, fnAction, oArg = 0, nInterval, fnAction
	elseif type(nInterval) == 'boolean' then
		-- FrameCall(szKey, false)
		nInterval, bUnreg = nil, true
	elseif nInterval and type(fnAction) ~= 'function' then
		-- FrameCall(szKey, nInterval, bOnce)
		fnAction, bOnce = nil, fnAction
	end
	if fnAction then -- reg
		if not szKey then -- 匿名fc调用
			szKey = GetTickCount()
			while _tFrameCall[tostring(szKey)] do
				szKey = szKey + 0.1
			end
			szKey = tostring(szKey)
		end
		if not _tFrameCall[szKey] then
			_tFrameCall[szKey] = _framecall_t or {}
			_framecall_t = nil
			_count = _count + 1
			LuaActive_Enable(true)
		end
		local fc = _tFrameCall[szKey]
		fc.fnAction = fnAction
		fc.oArg = oArg
		fc.nNext = _framecount
		fc.nInterval = nInterval or 0
	elseif nInterval then -- modify
		local fc = _tFrameCall[szKey]
		if fc then
			if not bOnce then
				fc.nInterval = nInterval
			end
			fc.nNext = _framecount + nInterval
		end
	elseif szKey and bUnreg then -- unreg
		if _tFrameCall[szKey] then
			_count = _count - 1
			_framecall_t = _tFrameCall[szKey]
			_tFrameCall[szKey] = nil
			if _count == 0 then
				LuaActive_Enable(false)
			end
		end
	elseif szKey then -- get registered breathecall info
		local fc = _tFrameCall[szKey]
		if fc then
			return szKey, fc.nInterval, fc.nNext - _framecount
		end
		return
	end
	return szKey
end

--================================= render call ===============================================
-- RenderCall(szKey, nInterval, fnAction, oArg)
-- RenderCall('CASTING') -- 获取名称为CASTING的RenderCall的信息
-- RenderCall('CASTING', false) -- 注销名称为CASTING的RenderCall
-- RenderCall('CASTING', function() end, oArg) -- 注册名称为CASTING调用间隔为最小值的RenderCall
-- RenderCall('CASTING', 100, function() end, oArg) -- 注册名称为CASTING调用间隔为100的RenderCall
-- RenderCall('CASTING', 200) -- 把名称为CASTING的RenderCall调用间隔改为200毫秒
-- RenderCall('CASTING', 200, true) -- 把名称为CASTING的RenderCall下次调用延迟改为200毫秒
-- 注：fnAction返回0表示从RenderCall中移除自己
--=============================================================================================
local _tRenderCall = {} -- rc表 键值对集合
local _rendercalls = {} -- a mirror table to avoid error: invalid key to 'next'
local _rendercall_c = 0 -- the count of rendercalls
local _rendercall_t   -- 循环使用rc表 减少频繁注册反注册时新建表的开销
local _rendercall_ref -- 注册事件标记 用于没有rc调用时反注册事件

local function onRenderCall()
	_time = GetTime()
	-- create mirror
	for szKey, rc in pairs(_tRenderCall) do
		_rendercalls[szKey] = rc
	end
	-- traverse rc calls
	for szKey, rc in pairs(_rendercalls) do
		if rc.nNext <= _time then
			rc.nNext = _time + rc.nInterval
			local res, err, trace = X.XpCall(rc.fnAction, rc.oArg)
			if not res then
				X.ErrorLog(err, 'onRenderCall: ' .. szKey, trace)
			elseif err == 0 then
				_rendercall_c = _rendercall_c - 1
				_rendercall_t = _tRenderCall[szKey]
				_tRenderCall[szKey] = nil
				if _rendercall_c == 0 then
					UnRegisterEvent('RENDER_FRAME_UPDATE', _rendercall_ref)
					_rendercall_ref = nil
				end
			end
		end
		_rendercalls[szKey] = nil
	end
end

function X.RenderCall(szKey, nInterval, fnAction, oArg)
	local bOnce, bUnreg
	if type(szKey) == 'function' then
		-- RenderCall(fnAction[, oArg])
		szKey, nInterval, fnAction, oArg = nil, 0, szKey, nInterval
	elseif type(szKey) == 'number' then
		-- RenderCall(nInterval, fnAction[, oArg])
		szKey, nInterval, fnAction, oArg = nil, szKey, nInterval, fnAction
	elseif type(nInterval) == 'function' then
		-- RenderCall(szKey, fnAction[, oArg])
		nInterval, fnAction, oArg = 0, nInterval, fnAction
	elseif type(nInterval) == 'boolean' then
		-- RenderCall(szKey, false)
		nInterval, bUnreg = nil, true
	elseif nInterval and type(fnAction) ~= 'function' then
		-- RenderCall(szKey, nInterval, bOnce)
		fnAction, bOnce = nil, fnAction
	end
	if fnAction then -- reg
		if not szKey then -- 匿名rc调用
			szKey = GetTickCount()
			while _tRenderCall[tostring(szKey)] do
				szKey = szKey + 0.1
			end
			szKey = tostring(szKey)
		end
		if not _tRenderCall[szKey] then
			_tRenderCall[szKey] = _rendercall_t or {}
			_rendercall_t = nil
			_rendercall_c = _rendercall_c + 1
		end
		local rc = _tRenderCall[szKey]
		rc.fnAction = fnAction
		rc.oArg = oArg
		rc.nNext = GetTime()
		rc.nInterval = nInterval or 0
		if not _rendercall_ref then
			_rendercall_ref = X.RegisterEvent('RENDER_FRAME_UPDATE', onRenderCall)
		end
	elseif nInterval then -- modify
		local rc = _tRenderCall[szKey]
		if rc then
			if not bOnce then
				rc.nInterval = nInterval
			end
			rc.nNext = GetTime() + nInterval
		end
	elseif szKey and bUnreg then -- unreg
		if _tRenderCall[szKey] then
			_rendercall_c = _rendercall_c - 1
			_rendercall_t = _tRenderCall[szKey]
			_tRenderCall[szKey] = nil
			if _rendercall_c == 0 then
				UnRegisterEvent('RENDER_FRAME_UPDATE', _rendercall_ref)
				_rendercall_ref = nil
			end
		end
	elseif szKey then -- get registered rendercall info
		local rc = _tRenderCall[szKey]
		if rc then
			return szKey, rc.nInterval, rc.nNext - GetTime()
		end
		return
	end
	return szKey
end

--================================= onactive ===============================================
-- 时钟函数
--==========================================================================================
local function __OnActive()
	if _no_active then
		return
	end
	onDelayCall()
	onFrameCall()
	onBreatheCall()
end

local frame = Wnd.OpenWindow(X.PACKET_INFO.UI_COMPONENT_ROOT .. 'WndFrameEmpty.ini', X.NSFormatString('{$NS}#Interval'))
frame.OnFrameBreathe = __OnActive
frame:Hide()

LuaActive_Enable(false)

end

--=================================== debounce ================================================
-- Debounce(szKey, nTime, fnAction, oArg)
-- Debounce('CASTING') -- 获取名称为CASTING的Debounce的信息
-- Debounce('CASTING', false) -- 注销名称为CASTING的Debounce
-- Debounce('CASTING', 100, function() end, oArg) -- 注册名称为CASTING防抖时间为100的Debounce
-- Debounce('CASTING', 200) -- 把名称为CASTING的Debounce防抖时间改为200毫秒
--=============================================================================================
do
local _tDebounce = {}
function X.Debounce(szKey, nTime, fnAction, oArg)
	local bUnreg
	if type(szKey) == 'number' then
		-- Debounce(nTime, fnAction[, oArg])
		szKey, nTime, fnAction, oArg = nil, szKey, nTime, fnAction
	elseif type(nTime) == 'boolean' then
		-- Debounce(szKey, false)
		nTime, bUnreg = nil, true
	end
	if fnAction then -- reg
		if not szKey then -- 匿名rc调用
			szKey = GetTickCount()
			while _tDebounce[tostring(szKey)] do
				szKey = szKey + 0.1
			end
			szKey = tostring(szKey)
		end
		_tDebounce[szKey] = {
			nTime = nTime,
			nNext = GetTime() + nTime,
			fnAction = fnAction,
			oArg = oArg,
		}
	elseif nTime then -- modify
		if _tDebounce[szKey] then
			_tDebounce[szKey].nTime = nTime
			_tDebounce[szKey].nNext = GetTime() + nTime
		end
	elseif szKey and bUnreg then -- unreg
		_tDebounce[szKey] = nil
	elseif szKey then -- get registered rendercall info
		local d = _tDebounce[szKey]
		if d then
			return szKey, d.nTime, d.nNext - GetTime()
		end
		return
	end
	return szKey
end
X.BreatheCall(X.NSFormatString('{$NS}#Debounce'), function()
	local nTime = GetTime()
	for szKey, d in pairs(_tDebounce) do
		if nTime >= d.nNext then
			local res, err, trace = X.XpCall(d.fnAction, d.oArg)
			if not res then
				X.ErrorLog(err, 'onDebounce: ' .. szKey, trace)
			end
			_tDebounce[szKey] = nil
		end
	end
end)
end

--=================================== throttle ================================================
-- Throttle(szKey, nTime, fnAction, oArg)
-- Throttle('CASTING') -- 获取名称为CASTING的Throttle的信息
-- Throttle('CASTING', false) -- 注销名称为CASTING的Throttle
-- Throttle('CASTING', 100, function() end, oArg) -- 注册名称为CASTING防抖时间为100的Throttle
-- Throttle('CASTING', 200) -- 把名称为CASTING的Throttle防抖时间改为200毫秒
--=============================================================================================
do
local _tThrottle = {}
function X.Throttle(szKey, nTime, fnAction, oArg)
	local bUnreg, bThrottle
	if type(szKey) == 'number' then
		-- Throttle(nTime, fnAction[, oArg])
		szKey, nTime, fnAction, oArg = nil, szKey, nTime, fnAction
	elseif type(nTime) == 'boolean' then
		-- Throttle(szKey, false)
		nTime, bUnreg = nil, true
	end
	if fnAction then -- reg
		if not szKey then -- 匿名rc调用
			szKey = GetTickCount()
			while _tThrottle[tostring(szKey)] do
				szKey = szKey + 0.1
			end
			szKey = tostring(szKey)
		end
		if _tThrottle[szKey] and _tThrottle[szKey].nNext > GetTime() then
			bThrottle = true
		else
			_tThrottle[szKey] = {
				nTime = nTime,
				nNext = GetTime() + nTime,
				fnAction = fnAction,
				oArg = oArg,
			}
			local res, err, trace = X.XpCall(fnAction, oArg)
			if not res then
				X.ErrorLog(err, 'onThrottle: ' .. szKey, trace)
			end
		end
	elseif nTime then -- modify
		if _tThrottle[szKey] then
			_tThrottle[szKey].nTime = nTime
			_tThrottle[szKey].nNext = GetTime() + nTime
		end
	elseif szKey and bUnreg then -- unreg
		_tThrottle[szKey] = nil
	elseif szKey then -- get registered rendercall info
		local d = _tThrottle[szKey]
		if d then
			return szKey, d.nTime, d.nNext - GetTime()
		end
		return
	end
	return szKey, bThrottle
end
X.BreatheCall(X.NSFormatString('{$NS}#Throttle'), function()
	local nTime = GetTime()
	for szKey, d in pairs(_tThrottle) do
		if nTime >= d.nNext then
			_tThrottle[szKey] = nil
		end
	end
end)
end

function X.FinallyThrottle(...)
	local _, bThrottle = X.Throttle(...)
	if bThrottle then
		X.Debounce(...)
	end
end

--[[#DEBUG BEGIN]]X.ReportModuleLoading(MODULE_PATH, 'FINISH')--[[#DEBUG END]]
