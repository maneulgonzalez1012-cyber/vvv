-- Prometheus config: Medium, minus NumbersToExpressions.
--
-- This is the Medium preset with exactly one step removed. NumbersToExpressions
-- rewrites every numeric literal into an arithmetic expression, which in a
-- bundle this size inflates the output roughly fivefold and, worse, produced
-- chunks that died inside their own runtime before the first user statement.
-- Every other Medium step is kept, in Medium's order:
--   Vmify, EncryptStrings, AntiTamper, ConstantArray, WrapInFunction, Cff.
--
-- The build verifies the shipped bytes under LuaJIT and Luau, so a step that
-- breaks either one fails the build rather than reaching a player.
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
