module Dice

export run_dice

using Telegram, Telegram.API
using HTTP
using JLD2
using JSON3
using Dates
using Random
using MLStyle
using ConfigEnv

include("const.jl")
include("diceCommand.jl")

function diceReply(msg, text::AbstractString; ref = true, pvt = false)
    if isempty(text) || length(text) > 512
        return nothing
    end
    if pvt
        try
            sendMessage(text = text, chat_id = msg.message.from.id)
        catch err
            sendMessage(
                text = "错误，可能是因为悟理球没有私聊权限，请尝试私聊向悟理球发送 /start",
                chat_id = msg.message.chat.id,
                reply_to_message_id = msg.message.message_id,
            )
        end
    elseif ref
        sendMessage(text = text, chat_id = msg.message.chat.id, reply_to_message_id = msg.message.message_id)
    else
        sendMessage(text = text, chat_id = msg.message.chat.id)
    end
end

function diceReplyLagacy(msg, reply::DiceReply)
    if isempty(reply.text) || length(reply.text) > 512
        return nothing
    end
    if reply.hidden
        try
            for tt ∈ reply.text
                sendMessage(text = tt, chat_id = msg.message.from.id)
            end
        catch err
            sendMessage(
                text = "错误，可能是因为悟理球没有私聊权限，请尝试私聊向悟理球发送 /start",
                chat_id = msg.message.chat.id,
                reply_to_message_id = msg.message.message_id,
            )
        end
    elseif reply.ref
        for tt ∈ reply.text
            sendMessage(text = tt, chat_id = msg.message.chat.id, reply_to_message_id = msg.message.message_id)
        end
    else
        for tt ∈ reply.text
            sendMessage(text = tt, chat_id = msg.message.chat.id)
        end
    end
end

function diceMain(msg)

    if debug_flag
        show(msg)
        println()
    end

    if !(haskey(msg, :message) && haskey(msg.message, :text))
        return nothing
    end

    str = msg.message.text
    if haskey(kwList, str)
        return sendMessage(text = rand(kwList[str]), chat_id = chatId)
    end

    str[1] ∉ ['.', '/', '。'] && return nothing
    str = replace(str, r"^(\.|/|。)\s*|\s*$" => "")

    ### SuperCommand ### Todo: 回复异常报错
    if hash(msg.message.from.id) ∈ superAdminList
        m = match(r"eval\s+([.\n]*)", str)
        if m !== nothing
            diceReplyLagacy(msg, DiceReply("警告！你在执行一个超级指令！", false, true))
            superCommand = m.captures[1]
            ret = nothing
            try
                ret = "begin $superCommand end" |> Meta.parse |> eval
            catch err
                return diceReplyLagacy(msg, DiceReply("执行失败", false, false))
            end
            return diceReplyLagacy(msg, DiceReply("执行结果：$ret", false, false))
        end
    end

    ignore = true
    chatType = :na
    groupId = msg.message.chat.id |> string
    userId = msg.message.from.id |> string
    if msg.message.chat.type ∈ ["group", "supergroup"]
        chatType = :group
        ignore = haskey(groupData, groupId) ? groupData[groupId].isOff : groupDefault.isOff
    elseif msg.message.chat.type == "private"
        chatType = :private
        ignore = false
    end
    if chatType == :na
        return nothing
    end

    reply = noReply
    for cmd ∈ cmdList
        if (ignore && :off ∉ cmd.options) || chatType ∉ cmd.options
            continue
        end
        m = match(cmd.reg, str)
        if m !== nothing
            ignore = false
            try
                reply = @eval $(cmd.func)($(m.captures); groupId = $groupId, userId = $userId)
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
        return diceReplyLagacy(msg, reply)
    end
    return nothing
end

function run_dice(; debug = false)
    global debug_flag = false
    debug && (debug_flag = true)

    !isfile("groupData.jld2") && jldsave("groupData.jld2")
    global groupData = jldopen("groupData.jld2", "r+")

    !isfile("jrrpCache.jld2") && jldsave("jrrpCache.jld2")
    global jrrpCache = jldopen("jrrpCache.jld2", "r+")

    !isfile("userData.jld2") && jldsave("userData.jld2")
    global userData = jldopen("userData.jld2", "r+")

    try
        run_bot(diceMain)
    finally
        Base.close(groupData)
        Base.close(jrrpCache)
        Base.close(userData)
    end
end

function julia_main()::Cint
    dotenv()
    try
        run_dice()
    catch
        Base.invokelatest(Base.display_error, Base.catch_stack())
        return 1
    end
    return 0
end

end # module
