module Dice

export run_dice, TGMode, QQMode

using JLD2
using JSON3
using Dates
using Random
using MLStyle

struct DiceMsg
    groupId::String
    userId::String
    messageId::Int64
    text::String
end

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
DiceReply(str::AbstractString) = DiceReply([str], false, true)
const noReply = DiceReply(AbstractString[], false, false)

abstract type AbstractMessage end
struct TGMessage <: AbstractMessage
    body
end
struct QQMessage <: AbstractMessage
    body
end

abstract type RunningMode end
struct TGMode <: RunningMode end
struct QQMode <: RunningMode end

include("DiceTG.jl")
include("DiceQQ.jl")
include("const.jl")
include("utils.jl")
include("diceCommand.jl")

function sendGroupMessage(; text, chat_id)
    mode = running_mode
    sendGroupMessage(mode; text = text, chat_id = chat_id)
end

function leaveGroup(; chat_id)
    mode = running_mode
    leaveGroup(mode; chat_id = chat_id)
end

function diceMain(msg::AbstractMessage)

    if debug_flag
        show(msg.body)
        println()
    end

    msg_parsed = parseMsg(msg)
    isnothing(msg_parsed) && return nothing
    groupId = msg_parsed.groupId
    userId = msg_parsed.userId
    str = msg_parsed.text
    isempty(str) && return nothing

    if haskey(kwList, str)
        return diceReply(msg, DiceReply(rand(kwList[str]), false, false))
    end

    str[1] ∉ ['.', '/', '。'] && return nothing
    str = replace(str, r"^[./。]\s*|\s*$" => "")

    if hash(userId) ∈ superAdminList[running_mode]
        m = match(r"eval\s+([\s\S]*)", str)
        if m !== nothing
            superCommand = m.captures[1]
            ret = nothing
            try
                ret = "begin $superCommand end" |> Meta.parse |> eval
            catch err
                if err isa Base.Meta.ParseError
                    err_msg = err.msg
                else
                    err_msg = string(err)
                end
                return diceReply(msg, DiceReply("执行失败，错误信息：\n```\n$err_msg\n```", false, false))
            end
            return diceReply(msg, DiceReply("执行结果：$ret", false, false))
        end
    end

    chatType = groupId == "private" ? :private : :group
    ignore = groupId == "private" ? false : getConfig(groupId, "everyone", "isOff")

    reply = noReply
    for cmd ∈ cmdList
        if (ignore && :off ∉ cmd.options) || chatType ∉ cmd.options
            continue
        end
        m = match(cmd.reg, str)
        if m !== nothing
            ignore = false
            try
                foo = eval(cmd.func)
                reply = foo(m.captures; groupId = groupId, userId = userId)
            catch err
                if err isa DiceError
                    reply = DiceReply(err.text)
                else
                    if debug_flag
                        showerror(stdout, err)
                        println()
                        display(stacktrace(catch_backtrace()))
                        println()
                    end
                    reply = DiceReply("遇到了触及知识盲区的错误.jpg")
                end
            end
            break
        end
    end
    if !ignore
        return diceReply(msg, reply)
    end
    return nothing
end

function run_dice(mode; debug = false)
    global debug_flag = false
    debug && (debug_flag = true)

    global running_mode = mode

    global groupData = jldopen("groupData.jld2", "a+")
    global jrrpCache = jldopen("jrrpCache.jld2", "a+")
    global userData = jldopen("userData.jld2", "a+")

    try
        run_bot(mode, diceMain)
    finally
        Base.close(groupData)
        Base.close(jrrpCache)
        Base.close(userData)
    end
end

end # Module