-- Prometheus config: Medium, minus NumbersToExpressions.
--
-- Why the deviation: the stock Medium preset ends with NumbersToExpressions,
-- and its output failed to load in two of the three interpreters the build is
-- verified against (the obfuscated chunk died inside its own runtime before the
-- first user statement). Every other Medium step is kept:
--   Vmify, EncryptStrings, AntiTamper, ConstantArray, WrapInFunction, Cff.
--
-- Verified output runs identically under LuaJIT 2.1, Lua 5.4 and Luau.
return {
    LuaVersion = "Lua51",
    VarNamePrefix = "",
    NameGenerator = "MangledShuffled",
    PrettyPrint = false,
    Seed = 0,
    Steps = {
        { Name = "Vmify", Settings = {} },
        { Name = "EncryptStrings", Settings = { HoistVmStrings = true } },
        { Name = "AntiTamper", Settings = { UseDebug = false } },
        {
            Name = "ConstantArray",
            Settings = {
                Threshold = 1,
                StringsOnly = true,
                Shuffle = true,
                Rotate = true,
                LocalWrapperThreshold = 0,
            },
        },
        { Name = "WrapInFunction", Settings = {} },
        { Name = "Cff", Settings = { ExcludeVm = true } },
    },
}
