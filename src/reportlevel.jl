@enum RL ThrowError ShowMessage SkipInitCheck

@kwdef mutable struct ModuleEntry 
	rl::RL = ThrowError
	init_created::Bool = false
	const postinit::Vector{Function} = Vector()
end

GLOBAL_RL::RL = ThrowError

"
Sets the default reporting level of modules; it does not change the setting for modules that already loaded an Inherit.jl macro.
"
function setglobalreportlevel(rl::RL)
	global GLOBAL_RL = rl
end

"
Sets the level of reporting for the given module. Takes precedence over global report level.

`ThrowError`: Checks for interface requirements in the module `__init__()` function, throwing an exception if requirements are not met. Creates `__init__()` upon first use of @abstractbase or @implement.  

`ShowMessage`: Same as above, but an `Error` level log message is produced rather than throwing exception.

`SkipInitCheck`: Still creates `__init__()` function (which sets up datastructures that may be needed by other modules) but won't verfiy interfaces. Cannot be set if `__init__()` has already been created
"
function setreportlevel(mod::Module, rl::RL)
	me = getmoduleentry(mod)
	# if init has already been created, we cannot change between DisableInit and other states 
	if me.init_created && ((rl==SkipInitCheck) ⊻ (me.rl==SkipInitCheck))
		throw(SettingsError("cannot change from current setting from $(me.rl) to $(rl)"))
	else
		me.rl = rl
	end

end

function getmoduleentry(mod::Module)
	if !isdefined(mod, H_FLAGS)
		setproperty!(mod, H_FLAGS, ModuleEntry(rl = Inherit.GLOBAL_RL))
	end
	getproperty(mod, H_FLAGS)
end