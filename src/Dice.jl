module Dice

export run_dice, TGMode, QQMode

using JLD2
using JSON3
using Dates
using Random
using MLStyle

include("utils.jl")
include("const.jl")
include("DiceTG.jl")
include("DiceQQ.jl")
include("diceCommand.jl")

function sendGroupMessage(; text, chat_id)
    mode = running_mode
    sendGroupMessage(mode; text = text, chat_id = chat_id)
end

function leaveGroup(; chat_id)
    mode = running_mode
    leaveGroup(mode; chat_id = chat_id)
end

function diceMain(rough_msg::AbstractMessage)

    if debug_flag
        show(rough_msg.body)
        println()
    end

    msg = parseMsg(rough_msg)
    isnothing(msg) && return nothing
    groupId = msg.groupId
    userId = msg.userId
    str = msg.text

    # Keyword reply
    if haskey(kwList, str)
        return diceReply(msg, DiceReply(rand(kwList[str]), false, false))
    end

    str[1] ∉ ['.', '/', '。'] && return nothing
    str = replace(str, r"^[./。]\s*|\s*$" => "")

    # Super command
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
                return @reply("执行失败，错误信息：\n```\n$err_msg\n```", false, false)
            end
            return @reply("执行结果：$ret", false, false)
        end
    end

    chatType = groupId == "private" ? :private : :group
    ignore = groupId == "private" ? false : getConfig(groupId, "everyone", "isOff")

    for cmd ∈ cmdList
        if (ignore && :off ∉ cmd.options) || chatType ∉ cmd.options
            continue
        end
        m = match(cmd.reg, str)
        if m !== nothing
            foo = eval(cmd.func)
            @async try
                foo(msg, m.captures)
            catch err
                if err isa DiceError
                    @reply(err.text)
                else
                    if debug_flag
                        @error err
                        showerror(stdout, err)
                        println()
                        display(stacktrace(catch_backtrace()))
                        println()
                    end
                    err_msg = string(err)
                    @reply("遇到了触及知识盲区的错误QAQ，请联系开发者修复！")
                end
            end
            break
        end
    end
    nothing
end

# Global variables
running_mode = NotRunning()
debug_flag = false
const message_channel = Channel{Tuple{DiceMsg,DiceReply}}(64)
const log_channel = Channel{MessageLog}(64)

function run_dice(mode; debug = false)
    global running_mode = mode
    debug && (global debug_flag = true)

    global groupData = jldopen("groupData.jld2", "a+")
    global jrrpCache = jldopen("jrrpCache.jld2", "a+")
    global userData = jldopen("userData.jld2", "a+")

    @async diceReply(mode, message_channel)
    # @async diceLogging(log_channel)

    try
        run_bot(mode, diceMain)
    finally
        Base.close(groupData)
        Base.close(jrrpCache)
        Base.close(userData)
    end
end

end # Module