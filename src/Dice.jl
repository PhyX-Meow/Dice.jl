module Dice

export run_dice

using HTTP
using JLD2
using JSON
using Dates
using Random
using MLStyle
using DataStructures

include("utils.jl")
include("const.jl")
include("DiceQQ.jl")
include("DiceCommand.jl")

function diceMain(rough_msg)

    if debug_flag
        JSON.json(rough_msg; pretty = true) |> println
    end

    msg = parseMsg(rough_msg)
    isnothing(msg) && return nothing
    groupId = msg.groupId
    userId = msg.userId
    str = msg.text

    if msg.type == :group
        put!(log_channel, MessageLog(msg))
    end

    # Keyword reply
    if haskey(kwList, str)
        @reply(rand(kwList[str]), false, false)
    end

    str[1] ∉ ['.', '/', '。'] && return nothing
    str = replace(str, r"^[./。]\s*|\s*$" => "")

    # Super command
    if hash(userId) ∈ superAdminList
        m = match(r"eval\s+([\s\S]*)", str)
        if m !== nothing
            superCommand = m.captures[1]
            ret = nothing
            try
                ret = "begin $superCommand end" |> Meta.parse |> eval
            catch err
                err isa InterruptException && rethrow()
                if err isa Meta.ParseError
                    err_msg = err.msg
                else
                    buffer = IOBuffer()
                    showerror(buffer, err)
                    err_msg = String(take!(buffer))
                end
                @reply("执行失败，错误信息：\n```\n$err_msg\n```", false, false)
            end
            ret_msg = sprint(show, MIME"text/plain"(), ret)
            if '\n' ∈ ret_msg
                ret_msg = "\n" * ret_msg
            end
            @reply("执行结果：$ret_msg", false, false)
        end
    end

    # Dice command
    ignore = groupId == "private" ? false : getConfig(groupId, "everyone", "isOff")
    randomMode = getConfig("private", userId, "randomMode")

    for cmd ∈ cmdList
        if (ignore && :off ∉ cmd.options) || msg.type ∉ cmd.options
            continue
        end
        m = match(cmd.reg, str)
        if m !== nothing
            try
                rng_state[] = @match randomMode begin
                    :jrrp => getUserRNG(userId)
                    :quantum => QuantumRNG()
                    _ => Random.default_rng()
                end
                cmd.func(msg, m.captures)
            catch err
                err isa DiceError && @reply(err.text)
                err isa InterruptException && rethrow()
                showerror(stdout, err)
                println()
                if debug_flag
                    display(stacktrace(catch_backtrace()))
                    println()
                end
                @reply("遇到了触及知识盲区的错误QAQ，请联系开发者修复！")
            finally
                randomMode == :jrrp && saveUserRNG(userId)
            end
            break
        end
    end
end

# Global variables
debug_flag = false
const message_channel = Channel{Tuple{DiceMsg,DiceReply}}(64)
const log_channel = Channel{MessageLog}(64)
const active_logs = Dict{String,Ref{GameLog}}()
const group_init_list = Dict{String,Ref{InitialList}}()
const rng_state = Ref{Union{AbstractRNG,QuantumRNG}}(Random.default_rng())
const quantum_state = Ref{Vector{UInt64}}(UInt64[])

function run_dice(; debug = false)
    debug && (global debug_flag = true)

    global groupData = jldopen("groupData.jld2", "a+")
    global jrrpCache = jldopen("jrrpCache.jld2", "a+")
    global userData = jldopen("userData.jld2", "a+")
    global drawData = JSON.parsefile("draw.json")

    @async_log diceReply(message_channel) # backport
    @async_log diceLogging(log_channel)

    try
        run_bot(diceMain)
    catch err
        bt = stacktrace(catch_backtrace())
        showerror(stdout, err, bt)
    end
end

function handle_exit()
    Base.close(message_channel)
    Base.close(log_channel)
    Base.close(groupData)
    Base.close(jrrpCache)
    Base.close(userData)
end

end # Module