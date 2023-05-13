var documenterSearchIndex = {"docs":
[{"location":"index.html","page":"-","title":"-","text":"","category":"page"},{"location":"index.html","page":"-","title":"-","text":"","category":"page"},{"location":"index.html","page":"-","title":"-","text":"Modules = [Inherit]","category":"page"},{"location":"index.html#Inherit.Inherit","page":"-","title":"Inherit.Inherit","text":"Inherit.jl let's the user inherit fields and interface definitions from a supertype. There are two macros which provide abstract templates for concrete types: @abstractbase which declares an abstract supertype with inheritable fields and required method definitions, and @interface which declares a container rather than supertype, while providing the same inheritance features. The @implement macro creates the concrete type that implements either or both of these templates. While a concrete type may  implement only one @abstractbase, multiple @interface's may be implemented.\n\nWe have steered away from using the term \"traits\" to avoid confusion with extensible Holy traits widely used in Julia libraries. While @interface's can be multiplely inherited, they cannot be added to an existing concrete type from another package. \n\nLimitations\n\nConcrete type must be defined in the same module as the method definitions specific t.\n\nShort form function definitions such as f() = nothing are not supported for method declaration; use the long form function f() end instead. Using short form for method implementation can be problematic as well (e.g. when the function is imported from another module); it's generally safer to use long form.\n\nJust like Julia types, definitions should be given in the order of their dependencies. While out-of-order code can work in some circumstances, we don't test for them. Within a given type, field and method definitions must be unique.\n\nInherit.jl has no special knowledge about constructors (inner or otherwise). They're treated like normal functions.\n\nThe package's macros must be used at the toplevel of a module. @abstractbase relies on world age to advance in order to detect a \"real\" method was defined (to differentiate the case where the method definition has identical signature as interface specification). \n\nIf you cannot return to toplevel (e.g. being wrapped in a @testset macro), a work around is to modify the signature slightly but retain the call paths that you require.\n\nCurrently we only handle long form interface definitions such as function f() end.\n\nTODO: multiple levels of interface (not hard) TODO: multiple interfaces (may be hard) TODO: what about parametric types?\n\nA method's signature given only by its positional arguments is unique. If you define a method with the same positional arguments but different keyword arguments from a previously defined method, it will overwrite the previous method. Keyword arguments simply do not particular in method dispatch.\n\nA parametric type signature can be supertype of abstract type signature \tTuple{typeof(f), Real} <: Tuple{typeof(f), T} where T<:Number\n\ntypeof(f).name.mt grows for each evaluation of method definition, even if it overwrites a previous definition. It is not the same as methods(f)\n\n\n\n\n\n","category":"module"},{"location":"index.html#Inherit.DB_FLAGS","page":"-","title":"Inherit.DB_FLAGS","text":"This gives us a list of all modules that are actively using Inherit.jl, if we ever need it\n\n\n\n\n\n","category":"constant"},{"location":"index.html#Inherit.RL","page":"-","title":"Inherit.RL","text":"ThrowError: Checks for interface requirements in the module __init__() function, and throws an exception if requirements are not met. Creates __init__ upon first use of @abstractbase or @implement.  \n\nShowMessage: Same as above, but an error level log message is shown rather than throwing exception.\n\nDisableInit: Will not create a module __init__() function; disables the @postinit macro. Can not be set if __init__ has already been created\n\n\n\n\n\n","category":"type"},{"location":"index.html#Inherit.createshadowmodule-Tuple{Module}","page":"-","title":"Inherit.createshadowmodule","text":"Creates a new module that contains (i.e. imports) only the properties of basemodule which are Types and Modules (i.e. excluding any functions). You can evaluate method declarations in this module to get the signature, without modifying basemodule itself\n\n\n\n\n\n","category":"method"},{"location":"index.html#Inherit.privatize_funcname-Tuple{Expr}","page":"-","title":"Inherit.privatize_funcname","text":"prepend __ to function name\n\n\n\n\n\n","category":"method"},{"location":"index.html#Inherit.setglobalreportlevel-Tuple{Inherit.RL}","page":"-","title":"Inherit.setglobalreportlevel","text":"This sets the default reporting level of modules; it does not change the setting for modules that already have a ModuleEntry.\n\n\n\n\n\n","category":"method"},{"location":"index.html#Inherit.setreportlevel-Tuple{Module, Inherit.RL}","page":"-","title":"Inherit.setreportlevel","text":"Takes precedence over global report level.\n\n\n\n\n\n","category":"method"},{"location":"index.html#Inherit.to_import_expr-Tuple{Symbol, Vararg{Symbol}}","page":"-","title":"Inherit.to_import_expr","text":"Makes a valid import expression like import modpath1.modpath2.modpath3: item\n\n:(import $modpath : $item) won't work even when modpath evaluates to modpath1.modpath2.modpath3\n\n\n\n\n\n","category":"method"},{"location":"index.html#Inherit.to_qualified_expr-Tuple{Vararg{Symbol}}","page":"-","title":"Inherit.to_qualified_expr","text":"converts syntax like a.b.c.d to AST\n\n\n\n\n\n","category":"method"},{"location":"index.html#Inherit.@abstractbase-Tuple{Any}","page":"-","title":"Inherit.@abstractbase","text":"TODO: evaluate in a temporary module TODO: support mutable types\n\n\n\n\n\n","category":"macro"},{"location":"index.html#Inherit.@implement-Tuple{Any}","page":"-","title":"Inherit.@implement","text":"Method declarations may come from a foreign module, in which case, method implementations must belong to functions in that foreign module. If there's no name clash, the foreign modules's function is automatically imported into the implementing module (i.e. your current module). If there is a name clash, you must qualify the method implementation with the foreign module's name.\n\n\n\n\n\n","category":"macro"},{"location":"index.html#Inherit.@interface-Tuple{Any}","page":"-","title":"Inherit.@interface","text":"An @abstractbase follows Julia's type hierarchy; a concrete type may only implement one abstractbase. A @interface is similar in some ways to Holy traits; a type may implement multiple interfaces in addition to its abstractbase. A interface can span type hierarchies, but it may only be used to inherit fields and function definition requirements. It cannot be used as a container element or object type (while carrying the behavior of interfaces).\n\nCan recreate the struct parameterized by the interface, this allows dispatch only on type, or on both type and interface. Basically, store the list of interfaces in the type parameters, and create default constructors that don't require the interface parameters.\n\n\n\n\n\n","category":"macro"},{"location":"index.html#Inherit.@postinit-Tuple{Any}","page":"-","title":"Inherit.@postinit","text":"Executed after Inherit.jl verfies interfaces. You may have any number of @postinit blocks; they will execute in the sequence order in which they're defined.\n\n\n\n\n\n","category":"macro"},{"location":"index.html#Inherit.@test_nothrows-Tuple{Any, Vararg{Any}}","page":"-","title":"Inherit.@test_nothrows","text":"opposite of @test_throws\n\n\n\n\n\n","category":"macro"}]
}
