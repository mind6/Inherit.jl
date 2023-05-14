var documenterSearchIndex = {"docs":
[{"location":"index.html#Introduction","page":"Introduction","title":"Introduction","text":"","category":"section"},{"location":"index.html","page":"Introduction","title":"Introduction","text":"Inherit.jl is used to inherit fields and interface definitions from a supertype. It supports programming with an object-oriented flavor in Julia, whenever this is more appropriate than developing under traditional Julia patterns. ","category":"page"},{"location":"index.html","page":"Introduction","title":"Introduction","text":"Fields defined in a supertype are automatically inherited by each subtype, and method declarations are checked for each subtype's implementation. An inheritance hierachy across multiple modules is supported. To accomplish this, macro processing is used to construct native Julia types, which allows the the full range of Julia syntax to be used in most situations.","category":"page"},{"location":"index.html#Quick-Start","page":"Introduction","title":"Quick Start","text":"","category":"section"},{"location":"index.html","page":"Introduction","title":"Introduction","text":"Use @abstractbase to declare an abstract supertype, and use @implement to inherit from such a type. Standard struct syntax is used.","category":"page"},{"location":"index.html","page":"Introduction","title":"Introduction","text":"using Inherit\r\n\r\n\"abstract base type of Fruity objects\"\r\n@abstractbase struct Fruit\r\n\tweight::Float64\r\n\t\"declares an interface which must be implemented\"\r\n\tfunction cost(fruit::Fruit, unitprice::Float64) end\r\nend\r\n\r\n\"\r\nconcrete type which represents an apple, inheriting from Fruit\r\nit has two fields: `weight` and `cost`\r\n\"\r\n@implement struct Apple <: Fruit \r\n\tcoresize::Int\r\nend\r\n\r\n\"implements supertype's interface declaration `cost` for the type `Apple`\"\r\nfunction cost(apple::Apple, unitprice::Float64)\r\n\tapple.weight * unitprice * (apple.coresize < 5 ? 2.0 : 1.0)\r\nend\r\n\r\nprintln(cost(Apple(3.0, 4), 1.0))\r\n\r\n# output\r\n6.0","category":"page"},{"location":"index.html","page":"Introduction","title":"Introduction","text":"Note that the definition of cost function inside of Fruit is interpreted as an interface declaration; it does not result in a method being defined.","category":"page"},{"location":"index.html","page":"Introduction","title":"Introduction","text":"info: Info\nWhat this declaration means is that when invoking the cost function, passing an object which is a subtype of Fruit (declared with the @implement macro) to the fruit::Fruit parameter must be able to dispatch to some method instance. This is verified when a module is first loaded. ","category":"page"},{"location":"index.html#Interaction-with-modules","page":"Introduction","title":"Interaction with modules","text":"","category":"section"},{"location":"index.html#The-module-__init__()-function","page":"Introduction","title":"The module __init__() function","text":"","category":"section"},{"location":"index.html#The-@postinit-macro","page":"Introduction","title":"The @postinit macro","text":"","category":"section"},{"location":"index.html#Changing-the-reporting-level","page":"Introduction","title":"Changing the reporting level","text":"","category":"section"},{"location":"index.html","page":"Introduction","title":"Introduction","text":"By default, module __init__() writes a summary message at the info log level. You change this by setting ENV[\"INHERIT_JL_SUMMARY_LEVEL\"] to one of [\"debug\", \"info\", \"warn\", \"error\", \"none\"]","category":"page"},{"location":"index.html#Limitations","page":"Introduction","title":"Limitations","text":"","category":"section"},{"location":"index.html#Multiple-inheritance","page":"Introduction","title":"Multiple inheritance","text":"","category":"section"},{"location":"index.html","page":"Introduction","title":"Introduction","text":"","category":"page"},{"location":"index.html","page":"Introduction","title":"Introduction","text":"","category":"page"},{"location":"index.html","page":"Introduction","title":"Introduction","text":"Modules = [Inherit]","category":"page"},{"location":"index.html#Inherit.Inherit","page":"Introduction","title":"Inherit.Inherit","text":"Inherit.jl let's the user inherit fields and interface definitions from a supertype. There are two macros which provide abstract templates for concrete types: @abstractbase which declares an abstract supertype with inheritable fields and required method definitions, and @interface which declares a container rather than supertype, while providing the same inheritance features. The @implement macro creates the concrete type that implements either or both of these templates. While a concrete type may  implement only one @abstractbase, multiple @interface's may be implemented.\n\nWe have steered away from using the term \"traits\" to avoid confusion with extensible Holy traits widely used in Julia libraries. While @interface's can be multiplely inherited, they cannot be added to an existing concrete type from another package. \n\nLimitations\n\nConcrete type must be defined in the same module as the method definitions specific t.\n\nShort form function definitions such as f() = nothing are not supported for method declaration; use the long form function f() end instead. Using short form for method implementation can be problematic as well (e.g. when the function is imported from another module); it's generally safer to use long form.\n\nJust like Julia types, definitions should be given in the order of their dependencies. While out-of-order code can work in some circumstances, we don't test for them. Within a given type, field and method definitions must be unique.\n\nInherit.jl has no special knowledge about constructors (inner or otherwise). They're treated like normal functions.\n\nThe package's macros must be used at the toplevel of a module. @abstractbase relies on world age to advance in order to detect a \"real\" method was defined (to differentiate the case where the method definition has identical signature as interface specification). \n\nIf you cannot return to toplevel (e.g. being wrapped in a @testset macro), a work around is to modify the signature slightly but retain the call paths that you require.\n\nCurrently we only handle long form interface definitions such as function f() end.\n\nTODO: multiple levels of interface (not hard) TODO: multiple interfaces (may be hard) TODO: what about parametric types?\n\nA method's signature given only by its positional arguments is unique. If you define a method with the same positional arguments but different keyword arguments from a previously defined method, it will overwrite the previous method. Keyword arguments simply do not particular in method dispatch.\n\nA parametric type signature can be supertype of abstract type signature \tTuple{typeof(f), Real} <: Tuple{typeof(f), T} where T<:Number\n\ntypeof(f).name.mt grows for each evaluation of method definition, even if it overwrites a previous definition. It is not the same as methods(f)\n\n\n\n\n\n","category":"module"},{"location":"index.html#Inherit.DB_FLAGS","page":"Introduction","title":"Inherit.DB_FLAGS","text":"This gives us a list of all modules that are actively using Inherit.jl, if we ever need it\n\n\n\n\n\n","category":"constant"},{"location":"index.html#Inherit.RL","page":"Introduction","title":"Inherit.RL","text":"ThrowError: Checks for interface requirements in the module __init__() function, and throws an exception if requirements are not met. Creates __init__ upon first use of @abstractbase or @implement.  \n\nShowMessage: Same as above, but an error level log message is shown rather than throwing exception.\n\nDisableInit: Will not create a module __init__() function; disables the @postinit macro. Can not be set if __init__ has already been created\n\n\n\n\n\n","category":"type"},{"location":"index.html#Inherit.createshadowmodule-Tuple{Module}","page":"Introduction","title":"Inherit.createshadowmodule","text":"Creates a new module that contains (i.e. imports) only the properties of basemodule which are Types and Modules (i.e. excluding any functions). You can evaluate method declarations in this module to get the signature, without modifying basemodule itself\n\n\n\n\n\n","category":"method"},{"location":"index.html#Inherit.privatize_funcname-Tuple{Expr}","page":"Introduction","title":"Inherit.privatize_funcname","text":"prepend __ to function name\n\n\n\n\n\n","category":"method"},{"location":"index.html#Inherit.setglobalreportlevel-Tuple{Inherit.RL}","page":"Introduction","title":"Inherit.setglobalreportlevel","text":"This sets the default reporting level of modules; it does not change the setting for modules that already have a ModuleEntry.\n\n\n\n\n\n","category":"method"},{"location":"index.html#Inherit.setreportlevel-Tuple{Module, Inherit.RL}","page":"Introduction","title":"Inherit.setreportlevel","text":"Takes precedence over global report level.\n\n\n\n\n\n","category":"method"},{"location":"index.html#Inherit.to_import_expr-Tuple{Symbol, Vararg{Symbol}}","page":"Introduction","title":"Inherit.to_import_expr","text":"Makes a valid import expression like import modpath1.modpath2.modpath3: item\n\n:(import $modpath : $item) won't work even when modpath evaluates to modpath1.modpath2.modpath3\n\n\n\n\n\n","category":"method"},{"location":"index.html#Inherit.to_qualified_expr-Tuple{Vararg{Symbol}}","page":"Introduction","title":"Inherit.to_qualified_expr","text":"converts syntax like a.b.c.d to AST\n\n\n\n\n\n","category":"method"},{"location":"index.html#Inherit.@abstractbase-Tuple{Any}","page":"Introduction","title":"Inherit.@abstractbase","text":"TODO: evaluate in a temporary module TODO: support mutable types\n\n\n\n\n\n","category":"macro"},{"location":"index.html#Inherit.@implement-Tuple{Any}","page":"Introduction","title":"Inherit.@implement","text":"Method declarations may come from a foreign module, in which case, method implementations must belong to functions in that foreign module. If there's no name clash, the foreign modules's function is automatically imported into the implementing module (i.e. your current module). If there is a name clash, you must qualify the method implementation with the foreign module's name.\n\n\n\n\n\n","category":"macro"},{"location":"index.html#Inherit.@interface-Tuple{Any}","page":"Introduction","title":"Inherit.@interface","text":"An @abstractbase follows Julia's type hierarchy; a concrete type may only implement one abstractbase. A @interface is similar in some ways to Holy traits; a type may implement multiple interfaces in addition to its abstractbase. A interface can span type hierarchies, but it may only be used to inherit fields and function definition requirements. It cannot be used as a container element or object type (while carrying the behavior of interfaces).\n\nCan recreate the struct parameterized by the interface, this allows dispatch only on type, or on both type and interface. Basically, store the list of interfaces in the type parameters, and create default constructors that don't require the interface parameters.\n\n\n\n\n\n","category":"macro"},{"location":"index.html#Inherit.@postinit-Tuple{Any}","page":"Introduction","title":"Inherit.@postinit","text":"Executed after Inherit.jl verfies interfaces. You may have any number of @postinit blocks; they will execute in the sequence order in which they're defined.\n\n\n\n\n\n","category":"macro"},{"location":"index.html#Inherit.@test_nothrows-Tuple{Any, Vararg{Any}}","page":"Introduction","title":"Inherit.@test_nothrows","text":"opposite of @test_throws\n\n\n\n\n\n","category":"macro"}]
}
