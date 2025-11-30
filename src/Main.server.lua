local apiConsumer = require(script.Parent.APIConsumer)
local warnLogger = require(script.Parent.Slogger)
warnLogger.init{postInit = table.freeze, logFunc = warn}
local glut = require(script.Parent.GLUt)

type APIReference = apiConsumer.APIReference

local warn = warnLogger.new("ContinentController")
glut.configure{ warn = warn }

local hookName = nil

local ContinentController = {}

function ContinentController.OnAPILoaded(api: APIReference, wranglerState)
	hookName = hookName or api.GetRegistrantFactory("Sprix", "ContinentController")
	wranglerState[1] = api.AddHook("PreSerialize", hookName("PreSerialize"), ContinentController.OnPreSerialize)
end

function ContinentController.OnAPIUnloaded(api: APIReference, wranglerState)
	for _, token in ipairs(wranglerState) do
		api.RemoveHook(token)
	end
end

function ContinentController.OnPreSerialize(callbackState, invokeState, mission: Folder)
	local warn = warn.specialize("OnPreSerialize")
	
	local first = true
	repeat
		if not first then coroutine.yield() end
		local _, present = invokeState.Get("Sprix_PrefabSystem_PreSerialize_Present")
		local success, done = invokeState.Get("Sprix_PrefabSystem_PreSerialize", "Done")
		first = false
	until (not present) or (success and done)
	
	local continentConfig = mission:FindFirstChild("ContinentConfig")
	if not continentConfig then return end
	
	if not continentConfig:IsA("BoolValue") then
		warn("ContinentConfig is invalid", `BoolValue expected, got {continentConfig.ClassName}`, "Config will be ignored")
		continentConfig:Destroy()
		return
	end
	
	if continentConfig.Value == false then
		print("ContinentConfig.Value == false : ContinentConfig will be ignored")
		continentConfig:Destroy()
		return
	end
	
	local consts, evals = ContinentController.DeriveState(continentConfig)
	if glut.tbl_findsize(consts) == 0 then
		if glut.tbl_findsize(evals) > 0 then
			warn("ContinentConfig has no constants! At least one constant must be present to use this plugin!")
		end
		continentConfig:Destroy()
		return
	end
	
	for k, v in pairs(evals) do
		local warn = warn.specialize(`Evaluate ContinentConfig:{k}`)
		local targetPath = glut.str_split(k, '.')
		local target, failPart = ContinentController.DeepGet(mission, unpack(targetPath))
		if target == nil then
			warn(`Failed getting target element {failPart}`, "Config attribute will be skipped")			
			continue
		end
		
		if not glut.str_has_match(v, "^return%s+") then v = "return " .. v end
		local success, argCount, args = glut.str_runlua(v, consts, `ContinentConfig:{k}`)
		if not success then
			warn(`Failed running eval with {argCount}`, "Config attribute will be skipped")
			continue
		end
		
		if argCount == 0 then
			warn("Eval succeeded, but did not return anything!", "Config attribute will be skipped")
			continue
		end
		
		local isPresent = args[1]
		if type(isPresent) ~= "boolean" then
			warn(`Eval succeeded, but got {type(isPresent)} instead of boolean!`, "Config attribute will be skipped")
			continue
		end
		
		if argCount > 1 then
			warn("Eval succeeded, but resolved to more than 1 value", "Extra values will be ignored!")
		end
		
		if not isPresent then
			target:Destroy()
		end
	end
	
	print("ContinentController : Successfully applied ContinentConfig")
	continentConfig:Destroy()
end

function ContinentController.DeriveState(config)
	local warn = warn.specialize("DeriveState")
	
	local constants = {}
	local evaluants = {}
	for attrName, attrVal in pairs(config:GetAttributes()) do
		if type(attrVal) == "boolean" then
			constants[attrName] = attrVal
		elseif type(attrVal) == "string" then
			evaluants[attrName] = attrVal
		else
			warn(`ContinentConfig attribute \"{attrName}\" is of unsupported type {type(attrVal)}!`, "Attribute will be ignored")
		end
	end
	return constants, evaluants
end

function ContinentController.DeepGet(inst, ...)
	local inst = inst
	for i, k in glut.vararg_iter(...) do
		inst = inst:FindFirstChild(k)
		if inst == nil then return nil, k end
	end
	return inst
end

apiConsumer.DoAPILoop(plugin, "InfiltrationEngine-ContinentController", ContinentController.OnAPILoaded, ContinentController.OnAPIUnloaded)