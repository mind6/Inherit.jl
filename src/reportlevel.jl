"
ThrowError: Checks for interface requirements in the module `__init__()` function, and throws an exception if requirements are not met. Creates `__init__` upon first use of @abstractbase or @implement.  

ShowMessage: Same as above, but an error level log message is shown rather than throwing exception.

DisableInit: Will not create a module `__init__()` function; disables the @postinit macro. Can not be set if `__init__` has already been created
"
@enum RL ThrowError ShowMessage DisableInit

@kwdef mutable struct ModuleEntry 
	rl::RL = ThrowError
	init_created::Bool = false
	const postinit::Vector{Function} = Vector()
end

"This gives us a list of all modules that are actively using Inherit.jl, if we ever need it"
const DB_FLAGS = Dict{Module, ModuleEntry}()
GLOBAL_RL::RL = ThrowError

"
This sets the default reporting level of modules; it does not change the setting for modules that already have a ModuleEntry.
"
function setglobalreportlevel(rl::RL)
	global GLOBAL_RL = rl
end

"
Takes precedence over global report level.
"
function setreportlevel(mod::Module, rl::RL)
	# if ME already has been created, we cannot change the between DisableInit and other states 
	if haskey(DB_FLAGS, mod)
		me = getmoduleentry(mod)
		if (rl==DisableInit) ⊻ (me.rl==DisableInit)
			throw(SettingsError("cannot change from current setting from $(me.rl) to $(rl)"))
		else
			me.rl = rl
		end
	else
		me = getmoduleentry(mod)
		me.rl = rl
	end
end

function getmoduleentry(mod::Module)
	if !haskey(DB_FLAGS, mod)
		me = ModuleEntry()	#kw constructor slow?
		me.rl = GLOBAL_RL
		DB_FLAGS[mod] = me
		me
	else
		DB_FLAGS[mod]
	end
end