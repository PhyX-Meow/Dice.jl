const diceVersion = v"0.1.0"

struct DiceError <: Exception
    text::String
end

struct DiceCmd
    func::Symbol
    reg::Regex
    desp::String
    options::Set{Symbol}
end

struct DiceReply
    text::Array{AbstractString}
    hidden::Bool
    ref::Bool
end
DiceReply(str::AbstractString, hidden::Bool, ref::Bool) = DiceReply([str], hidden, ref)
DiceReply(str::AbstractString) = DiceReply(str, false, true)
const noReply = DiceReply(AbstractString[], false, false)

struct DiceConfig
    customReply::Dict{Symbol,Array{String}}
end

mutable struct GroupConfig
    rcRule::Symbol
    isOff::Bool
    team::Array{Int}
end

const groupDefault = GroupConfig(:book, false, Int[])

const diceDefault = DiceConfig(
    Dict(
        :critical => [
            "是大成功哦！"
        ],
        :extreme => [
            "极难成功，干得漂亮~"
        ],
        :hard => [
            "困难成功，不错不错"
        ],
        :regular => [
            "简单的成功了。"
        ],
        :failure => [
            "失败了，惨惨。"
        ],
        :fumble => [
            "你以为能骰出成功？其实是大失败哒！"
        ]
    )
)

const superAdminList = [0xc45c1b20b131d1c8]
const adminList = [0xc45c1b20b131d1c8, 0x192e269af0e0ce03]
const cmdList = [
    DiceCmd(:roll, r"^r(?:([ach])|(\d?)b|(\d?)p)*(.*)", "骰点或检定", Set([:group, :private])),
    DiceCmd(:charMake, r"^coc7?(.*)", "人物做成", Set([:group, :private])),
    DiceCmd(:botStart, r"^start$", "Hello, world!", Set([:private])),
    DiceCmd(:botSwitch, r"^bot (on|off|exit)", "bot开关", Set([:group, :off])),
    DiceCmd(:botInfo, r"^bot$", "bot信息", Set([:group, :private])),
    DiceCmd(:diceConfig, r"^conf(.*)", "Dice设置", Set([:group, :private])),
    DiceCmd(:diceHelp, r"^help(.*)", "获取帮助", Set([:group, :private])),
    DiceCmd(:jrrp, r"^jrrp", "今日人品", Set([:group, :private])),
    DiceCmd(:fuck2060, r"\u2060", "fuck\\u2060", Set([:group, :private]))
]
const kwList = Dict(
    "悟理球" => ["悟理球在！", "需要骰子吗！"]
)

skillList = Dict("安息" => 90)