var documenterSearchIndex = {"docs":
[{"location":"index.html#Introduction","page":"Home","title":"Introduction","text":"","category":"section"},{"location":"index.html","page":"Home","title":"Home","text":"Inherit.jl is used to inherit fields and interface definitions from a supertype. It supports programming with an object-oriented flavor in Julia, whenever this is more appropriate than developing under traditional Julia patterns. ","category":"page"},{"location":"index.html","page":"Home","title":"Home","text":"Fields defined in a supertype are automatically inherited by each subtype, and method declarations are checked for each subtype's implementation. An inheritance hierachy across multiple modules is supported. To accomplish this, macro processing is used to construct native Julia types, which allows the the full range of Julia syntax to be used in most situations.","category":"page"},{"location":"index.html","page":"Home","title":"Home","text":"DocTestSetup = quote\r\n\timport Inherit\r\n\tENV[\"JULIA_DEBUG\"] = \"\"\r\n\tENV[Inherit.E_SUMMARY_LEVEL] = \"info\"\r\nend","category":"page"},{"location":"index.html#Quick-Start","page":"Home","title":"Quick Start","text":"","category":"section"},{"location":"index.html","page":"Home","title":"Home","text":"Use @abstractbase to declare an abstract supertype, and use @implement to inherit from such a type. Standard struct syntax is used.","category":"page"},{"location":"index.html","page":"Home","title":"Home","text":"using Inherit\r\n\r\n\"\r\nBase type of Fruity objects. \r\nCreates a julia native type with \r\n\t`abstract type Fruit end`\r\n\"\r\n@abstractbase struct Fruit\r\n\tweight::Float64\r\n\t\"declares an interface which must be implemented\"\r\n\tfunction cost(fruit::Fruit, unitprice::Float64) end\r\nend\r\n\r\n\"\r\nConcrete type which represents an apple, inheriting from Fruit.\r\nCreates a julia native type with \r\n\t`struct Apple <: Fruit weight::Float64; coresize::Int end`\r\n\"\r\n@implement struct Apple <: Fruit \r\n\tcoresize::Int\r\nend\r\n\r\n\"\r\nImplements supertype's interface declaration `cost` for the type `Apple`\r\n\"\r\nfunction cost(apple::Apple, unitprice::Float64)\r\n\tapple.weight * unitprice * (apple.coresize < 5 ? 2.0 : 1.0)\r\nend\r\n\r\nprintln(cost(Apple(3.0, 4), 1.0))\r\n\r\n# output\r\n6.0","category":"page"},{"location":"index.html","page":"Home","title":"Home","text":"Note that the definition of cost function inside of Fruit is interpreted as an interface declaration; it does not result in a method being defined.","category":"page"},{"location":"index.html","page":"Home","title":"Home","text":"info: Info\nWhat this declaration means is that when invoking the cost function, passing an object which is a subtype of Fruit (declared with the @implement macro) to the fruit::Fruit parameter must be able to dispatch to some method instance. This is verified when a module is first loaded. ","category":"page"},{"location":"index.html#Interaction-with-modules","page":"Home","title":"Interaction with modules","text":"","category":"section"},{"location":"index.html","page":"Home","title":"Home","text":"An object oriented programming style can be useful to applications that span across multiple modules. Even though Inherit.jl can be used inside of scripts, its true usefulness is to assert common interfaces shared by different data types from different modules. Verification of method declarations take place in the __init__() function of the module which the implementing type belongs to (i.e. where the @implement macro is used).","category":"page"},{"location":"index.html#The-module-__init__()-function","page":"Home","title":"The module __init__() function","text":"","category":"section"},{"location":"index.html","page":"Home","title":"Home","text":"The specially named module-level (i.e. top-level) function __init__() is called after the module has been fully loaded by Julia. If an interface definition has not been met, an exception will be thrown.","category":"page"},{"location":"index.html","page":"Home","title":"Home","text":"module M1\r\n\tusing Inherit\r\n\t@abstractbase struct Fruit\r\n\t\tweight::Float64\r\n\t\tfunction cost(fruit::Fruit, unitprice::Float64) end\r\n\tend\r\n\t@implement struct Apple <: Fruit end\r\n\t@implement struct Orange <: Fruit end\r\n\t@implement struct Kiwi <: Fruit end\r\n\r\n\tfunction cost(fruit::Union{Apple, Kiwi}, unitprice::Float64) \r\n\t\t1.0 \r\n\tend\r\nend\r\n\r\n# output\r\nERROR: InitError: ImplementError: subtype M1.Orange missing Tuple{typeof(M1.cost), M1.Orange, Float64} declared as:\r\nfunction cost(fruit::Fruit, unitprice::Float64)\r\n[...]","category":"page"},{"location":"index.html","page":"Home","title":"Home","text":"Upon loading module M1, Inherit.jl throws an ImplementError from the __init__() function, telling you that it's looking for a method signature that can dispatch cost(::M1.Orange, ::Float64). It makes no complaints about Apple and Kiwi because their dispatch can be satisfied.","category":"page"},{"location":"index.html#The-@postinit-macro","page":"Home","title":"The @postinit macro","text":"","category":"section"},{"location":"index.html","page":"Home","title":"Home","text":"The presence of an @abstractbase or @implement macro causes Inherit.jl to generate and overwrite the module's __init__() function. To execute your own module initialization code, the @postinit macro is available. It accepts a function as argument and registers that function to be executed after __init__(). Multiple occurrences of @postinit will result in each function being called successively.","category":"page"},{"location":"index.html#Putting-it-all-together","page":"Home","title":"Putting it all together","text":"","category":"section"},{"location":"index.html","page":"Home","title":"Home","text":"Let's demonstrate @postinit as well as other features in a more extended example.","category":"page"},{"location":"index.html","page":"Home","title":"Home","text":"module M1\r\n\tusing Inherit\r\n\r\n\t@abstractbase struct Fruit\r\n\t\tweight::Float64\r\n\t\t\"docstrings of method declarations are appended at the end of method docstrings\"\r\n\t\tfunction cost(fruit::Fruit, unitprice::Float64) end\r\n\tend\r\n\t\"this implementation satisfies the interface declaration for all subtypes of Fruit\"\r\n\tfunction cost(item::Fruit, unitprice::Real)\r\n\t\tunitprice * item.weight\r\n\tend\t\t\r\nend\r\n\r\nmodule M2\r\n\tusing Inherit\r\n\timport ..M1\r\n\r\n\t@abstractbase struct Berry <: M1.Fruit\r\n\t\t\"the supertype can appear in a variety of positions\"\r\n\t\tfunction pack(time::Int, bunch::Dict{String, AbstractVector{<:Berry}})::Float32 end\r\n\tend\r\n\r\n\t@implement struct BlueBerry <: Berry end\r\n\r\n\t\"the implementing method's argument types can be broader than the interface's argument types\"\r\n\tfunction pack(time::Number, bunch::Dict{String, AbstractVector{<:BlueBerry}})::Float32 end\r\n\r\n\t@postinit function myinit()\r\n\t\tprintln(\"docstring of imported `cost` function:\\n\", @doc cost)\r\n\tend\r\nend\r\nnothing\r\n\r\n# output\r\n[ Info: Inherit.jl: processed M1 with 1 supertype having 1 method requirement. 0 subtypes were checked with 0 missing methods.\r\n[ Info: Inherit.jl: processed M2 with 1 supertype having 2 method requirements. 1 subtype was checked with 0 missing methods.\r\ndocstring of imported `cost` function:\r\nthis implementation satisfies the interface declaration for all subtypes of Fruit\r\n \r\ndocstrings of method declarations are appended at the end of method docstrings\r\n","category":"page"},{"location":"index.html","page":"Home","title":"Home","text":"We can make a few observations regarding the above example:","category":"page"},{"location":"index.html","page":"Home","title":"Home","text":"A summary message is printed after each module is loaded, showing Inherit.jl is active.\nMultiple levels of inheritance is possible across multiple modules.\nMethod definitions are quite flexible. In a method declaration, you can name a supertype anywhere that's valid in Julia, and it will be checked for proper dispatch of subtypes.\nThe function M1.cost was automatically imported into module M2. The function still lives in module M1 together with its method instances, but it is available in M2 through the symbol cost.\nWhile not shown in this example, you can extend M1.cost by writing function cost(...) ... end in module M2\nDocstrings are preserved. Docstring for method declarations are added to the end of any  method docstrings. ","category":"page"},{"location":"index.html#Changing-the-reporting-level","page":"Home","title":"Changing the reporting level","text":"","category":"section"},{"location":"index.html","page":"Home","title":"Home","text":"To have module __init__() log an error message instead of throwing an exception, add setreportlevel(ShowMessage) near the front of the module. You can also disable interface checking altogether with setreportlevel(DisableInitCheck)","category":"page"},{"location":"index.html","page":"Home","title":"Home","text":"By default, module __init__() writes its summary message at the Info log level. You can change this by setting ENV[\"INHERIT_JL_SUMMARY_LEVEL\"] to one of [\"debug\", \"info\", \"warn\", \"error\", \"none\"].","category":"page"},{"location":"index.html#Limitations","page":"Home","title":"Limitations","text":"","category":"section"},{"location":"index.html","page":"Home","title":"Home","text":"Parametric types are currently not supported. Basic support for parametric concrete types is being planned.","category":"page"},{"location":"index.html","page":"Home","title":"Home","text":"Methods are examined only for their positional arguments. Inherit.jl has no special knowledge of keyword arguments, but this may improve in the future.","category":"page"},{"location":"index.html","page":"Home","title":"Home","text":"Inherit.jl has no special knowledge about constructors (inner or otherwise). They're treated like normal functions. As a result, constructor inheritance is not available.","category":"page"},{"location":"index.html","page":"Home","title":"Home","text":"Short form function definitions such as f() = nothing are not supported for method declaration; use the long form function f() end instead. Using short form for method implementation can be problematic as well (e.g. when the function is imported from another module); it's generally safer to use long form.","category":"page"},{"location":"index.html#Multiple-inheritance","page":"Home","title":"Multiple inheritance","text":"","category":"section"},{"location":"index.html","page":"Home","title":"Home","text":"Multiple inheritance is currently not supported, but is being planned. It will have the following syntax:","category":"page"},{"location":"index.html","page":"Home","title":"Home","text":"@abstractbase struct Fruit\r\n\tweight::Float64\r\n\tfunction cost(fruit::Fruit, unitprice::Float64) end\r\nend\r\n\r\n@trait struct SweetFood\r\n\tsugartype::Symbol\r\n\t\"\r\n\tSubtype must define:\r\n\t\tfunction sugarlevel(obj::T) end  \r\n\twhere T<--SweetFood\r\n\t\"\r\n\tfunction sugarlevel(obj<--SweetFood) end  \r\nend\r\n\r\n@implement struct Apple <: Fruit _ <-- SweetFood \r\n\tcoresize::Int\r\nend\r\n\r\nfunction sugarlevel(apple::Apple) \"depends on \"*join(fieldnames(Apple),\", \") end\t","category":"page"},{"location":"index.html","page":"Home","title":"Home","text":"\"depends on weight, sugartype, coresize\"","category":"page"},{"location":"index.html#API","page":"Home","title":"API","text":"","category":"section"},{"location":"index.html","page":"Home","title":"Home","text":"environment variable value description\nJULIA_DEBUG \"Inherit\" Enables printing of more detailed Debug level messsages. Default is \"\" which only prints Info level messages\nINHERIT_JL_SUMMARY_LEVEL \"debug\", \"info\", \"warn\", \"error\", or \"none\" logs the per-module summary message at the chosen level, or none at all. Default is \"info\".","category":"page"},{"location":"index.html","page":"Home","title":"Home","text":"","category":"page"},{"location":"index.html","page":"Home","title":"Home","text":"@abstractbase\r\n@implement\r\n@postinit\r\nsetreportlevel\r\nsetglobalreportlevel","category":"page"},{"location":"index.html#Inherit.@abstractbase","page":"Home","title":"Inherit.@abstractbase","text":"Creates a Julia abstract type, while allowing field and method declarations to be inherited by subtypes created with the @implement macro.\n\nRequires a single expression of one of following forms:\n\nstruct T ... end\nmutable struct T ... end\nstruct T <: S ... end\nmutable struct T <: S ... end\n\nSupertype S can be any valid Julia abstract type. In addition, if S was created with @abstractbase, all its fields and method declarations will be prepended to T's own definitions, and they will be inherited by any subtype of T. \n\nMutability must be the same as the supertype's mutability.\n\n\n\n\n\n","category":"macro"},{"location":"index.html#Inherit.@implement","page":"Home","title":"Inherit.@implement","text":"Creates a Julia struct or mutable struct type which contains all the fields of its supertype. Method interfaces declared (and inherited) by the supertype are required to be implemented.\n\nRequires a single expression of one of following forms:\n\nstruct T <: S ... end\nmutable struct T <: S ... end\n\nMutability must be the same as the supertype's mutability.\n\nMethod declarations may be from a foreign module, in which case method implementations must be added to the foreign module's function. If there is no name clash, the foreign modules's function is automatically imported into the implementing module (i.e. your current module). If there is a name clash, you must qualify the function name with the foreign module's name.\n\n\n\n\n\n","category":"macro"},{"location":"index.html#Inherit.@postinit","page":"Home","title":"Inherit.@postinit","text":"Requires a single function definition expression.\n\nThe function will be executed after Inherit.jl verfies interfaces. You may have any number of @postinit blocks; they will execute in the order in which they were defined.\n\n\n\n\n\n","category":"macro"},{"location":"index.html#Inherit.setreportlevel","page":"Home","title":"Inherit.setreportlevel","text":"Sets the level of reporting for the given module. Takes precedence over global report level.\n\nThrowError: Checks for interface requirements in the module __init__() function, throwing an exception if requirements are not met. Creates __init__() upon first use of @abstractbase or @implement.  \n\nShowMessage: Same as above, but an Error level log message is produced rather than throwing exception.\n\nSkipInitCheck: Still creates __init__() function (which sets up datastructures that may be needed by other modules) but won't verfiy interfaces. Cannot be set if __init__() has already been created\n\n\n\n\n\n","category":"function"},{"location":"index.html#Inherit.setglobalreportlevel","page":"Home","title":"Inherit.setglobalreportlevel","text":"Sets the default reporting level of modules; it does not change the setting for modules that already loaded an Inherit.jl macro.\n\n\n\n\n\n","category":"function"}]
}
