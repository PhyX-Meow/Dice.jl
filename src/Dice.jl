module Dice

export run_dice

using HTTP
using JLD2
using JSON3
using Dates
using Random
using MLStyle
using ConfigEnv

include("const.jl")
include("diceCommand.jl")
include("cqhttp.jl")

function makeReplyJson(msg; text::AbstractString, type::AbstractString = msg.message_type, ref::Bool = false)
    json_data = Dict(
        "action" => "send_msg",
        "params" => Dict(),
    )
    json_data["params"]["message_type"] = type
    if type == "private"
        json_data["params"]["user_id"] = msg.user_id
        if ref
            text = "[CQ:reply,id=$(msg.message_id)]" * text
        end
    elseif type == "group"
        json_data["params"]["group_id"] = msg.group_id
        if ref
            text = "[CQ:reply,id=$(msg.message_id)][CQ:at,qq=$(msg.user_id)]" * text
        end
    end
    json_data["params"]["message"] = text
    return JSON3.write(json_data)
end

function isQQFriend(ws; userId)
    return true
end

function diceReplyLagacy(ws, msg, reply::DiceReply)
    isempty(reply.text) && return nothing
    length(reply.text) > 512 && WebSockets.send(ws, makeReplyJson(msg, text = "错误，回复消息过长或为空"))

    if reply.hidden
        if isQQFriend(ws, userId = msg.user_id)
            for tt ∈ reply.text
                WebSockets.send(ws, makeReplyJson(msg, text = tt, type = "private"))
                sleep(0.05)
            end
        else
            WebSockets.send(ws, makeReplyJson(msg, text = "错误，悟理球无法向非好友发送消息，请先添加好友", ref = true))
        end
    else
        for tt ∈ reply.text
            WebSockets.send(ws, makeReplyJson(msg, text = tt, ref = reply.ref))
            sleep(0.05)
        end
    end
end

function handleRequest(ws, msg)
    @switch msg.request_type begin
        @case "friend"
        json_data = Dict(
            "action" => "set_friend_add_request",
            "params" => Dict(
                "flag" => msg.flag,
                "approve" => true,
            ),
        )
        WebSockets.send(ws, JSON3.write(json_data))

        @case "group"
        msg.sub_type != "invite" && return nothing
        json_data = Dict(
            "action" => "set_group_add_request",
            "params" => Dict(
                "flag" => msg.flag,
                "approve" => true,
            ),
        )
        WebSockets.send(ws, JSON3.write(json_data))

        @case _
    end
end

function handleNotice(ws, msg)
    @switch msg.notice_type begin
        @case "group_increase"
        msg.user_id == msg.self_id && WebSockets.send(ws, makeReplyJson(msg, text = "悟理球出现了！", type = "group"))

        @case "friend_add"
        WebSockets.send(ws, makeReplyJson(msg, text = "你现在也是手上粘着悟理球的 Friends 啦！", type = "private"))

        @case _
    end
end

function diceMain(ws, msg)

    if debug_flag
        show(msg)
        println()
    end

    !haskey(msg, "post_type") && return nothing
    msg.post_type == "request" && return handleRequest(ws, msg)
    msg.post_type == "notice" && return handleNotice(ws, msg)
    msg.post_type != "message" && return nothing
    msg.message_type == "group" && msg.sub_type != "normal" && return nothing
    msg.message_type == "private" && msg.sub_type ∉ ["friend", "group"] && return nothing

    str = msg.raw_message
    if haskey(kwList, str)
        data = makeReplyJson(msg, text = rand(kwList[str]))
        return WebSockets.send(ws, data)
    end

    if str[1] ∉ ['.', '/', '。']
        return nothing
    end
    str = replace(str, r"^(\.|/|。)\s*|\s*$" => "")

    ### SuperCommand ### Todo: 回复异常报错
    if hash(msg.user_id) ∈ superAdminQQList
        m = match(r"eval\s+(.*)", str)
        if m !== nothing
            diceReplyLagacy(ws, msg, DiceReply("警告！你在执行一个超级指令！", false, true))
            superCommand = m.captures[1]
            ret = nothing
            try
                ret = "begin $superCommand end" |> Meta.parse |> eval
            catch err
                return diceReplyLagacy(ws, msg, DiceReply("执行失败", false, false))
            end
            return diceReplyLagacy(ws, msg, DiceReply("执行结果：$ret", false, false))
        end
    end

    ignore = true
    groupId = ""
    userId = msg.user_id |> string
    if msg.message_type == "group"
        chatType = :group
        groupId = msg.group_id |> string
        ignore = haskey(groupData, groupId) ? groupData[groupId].isOff : groupDefault.isOff
    elseif msg.message_type == "private"
        chatType = :private
        ignore = false
    else
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
        return diceReplyLagacy(ws, msg, reply)
    end
    return nothing
end

function run_dice(; debug = false)
    global debug_flag = false
    if debug
        debug_flag = true
    end

    if !isfile("groupData.jld2")
        jldsave("groupData.jld2")
    end
    global groupData = jldopen("groupData.jld2", "r+")
    if !isfile("jrrpCache.jld2")
        jldsave("jrrpCache.jld2")
    end
    global jrrpCache = jldopen("jrrpCache.jld2", "r+")
    if !isfile("userData.jld2")
        jldsave("userData.jld2")
    end
    global userData = jldopen("userData.jld2", "r+")

    try
        run_bot(diceMain)
    finally
        Base.close(groupData)
        Base.close(jrrpCache)
        Base.close(userData)
    end
end

end # module
