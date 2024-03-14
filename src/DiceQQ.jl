using HTTP

function run_bot(::QQMode, foo::Function)
    global onebot_ws_server = get(ENV, "CQ_WS_SERVER", "")
    global onebot_http_server = get(ENV, "CQ_HTTP_SERVER", "")
    WebSockets.open(onebot_ws_server) do ws
        for str ∈ ws
            msg = JSON3.read(str)
            try
                foo(QQMessage(msg))
            catch err
                @error err
                if err isa InterruptException
                    break
                end
            end
        end
    end
end

function onebotPostJSON(action, params)
    HTTP.post(onebot_http_server * "/" * action, ["Content-Type" => "application/json"], body = params)
end

function sendGroupMessage(::QQMode; text, chat_id)
    msg_json = """
    {
        "group_id": $chat_id,
        "message": "$text"
    }
    """
    onebotPostJSON("send_group_msg", msg_json)
end

function leaveGroup(::QQMode; chat_id)
    msg_json = """
    {
        "group_id": $chat_id
    }
    """
    onebotPostJSON("set_group_leave", msg_json)
end

function isQQFriend(userId)
    return true

    reply = onebotPostJSON("get_friend_list", "")
    list = JSON3.read(reply.body)
    qq_list = map(x -> x.user_id, list)
    return userId ∈ qq_list
end

function parseMsg(wrapped::QQMessage)
    msg = wrapped.body
    !haskey(msg, "post_type") && return nothing
    msg.post_type == "request" && return handleRequest(msg)
    msg.post_type == "notice" && return handleNotice(msg)
    msg.post_type != "message" && return nothing

    groupId = "private"
    userId = msg.user_id |> string
    if msg.message_type == "group"
        msg.sub_type != "normal" && return nothing
        groupId = msg.group_id |> string
    elseif msg.message_type == "private"
        msg.sub_type != "friend" && return nothing
    else
        return nothing
    end

    text = replace(msg.raw_message, r"&amp;" => "&", r"&#91;" => "[", r"&#93;" => "]")
    m = match(r"^\[CQ:at,qq=(\d*)\]\s*([\S\s]*)", text)
    if m !== nothing
        qq = m.captures[1]
        hash(qq) != selfQQ && return nothing
        text = m.captures[2]
    end
    return DiceMsg(groupId, userId, msg.message_id, text)
end

function makeReplyJSON(msg; text::AbstractString, type::AbstractString = msg.message_type, ref::Bool = false)
    json_data = Dict()
    json_data["message_type"] = type
    if type == "private"
        json_data["user_id"] = msg.user_id
        if ref
            text = "[CQ:reply,id=$(msg.message_id)]" * text
        end
    elseif type == "group"
        json_data["group_id"] = msg.group_id
        if ref
            text = "[CQ:reply,id=$(msg.message_id)][CQ:at,qq=$(msg.user_id)]" * text
        end
    end
    json_data["message"] = text
    return JSON3.write(json_data)
end

function diceReply(wrapped::QQMessage, reply::DiceReply)
    msg = wrapped.body
    isempty(reply.text) && return nothing
    if length(reply.text) > 1024
        onebotPostJSON("send_msg", makeReplyJSON(msg, text = "错误，回复消息过长或为空"))
        return nothing
    end
    if reply.hidden
        if isQQFriend(msg.user_id)
            for tt ∈ reply.text
                onebotPostJSON("send_msg", makeReplyJSON(msg, text = tt, type = "private"))
                sleep(0.05)
            end
        else
            onebotPostJSON("send_msg", makeReplyJSON(msg, text = "错误，悟理球无法向非好友发送消息，请先添加好友", ref = true))
        end
    else
        for tt ∈ reply.text
            onebotPostJSON("send_msg", makeReplyJSON(msg, text = tt, ref = reply.ref))
            sleep(0.05)
        end
    end
    nothing
end

function handleRequest(msg)
    @switch msg.request_type begin
        @case "friend"
        msg_json = """
        {
            "flag" => $(msg.flag),
            "approve" => true,
        }
        """
        onebotPostJSON("set_friend_add_request", msg_json)

        @case "group"
        msg.sub_type != "invite" && return nothing
        msg_json = """
        {
            "flag" => $(msg.flag),
            "approve" => true,
        }
        """
        onebotPostJSON("set_group_add_request", msg_json)

        @case _
    end
    nothing
end

function handleNotice(msg)
    @switch msg.notice_type begin
        @case "group_increase"
        msg.user_id == msg.self_id && onebotPostJSON("send_msg", makeReplyJSON(msg, text = "悟理球出现了！", type = "group"))

        @case "friend_add"
        onebotPostJSON("send_msg", makeReplyJSON(msg, text = "你现在也是手上粘着悟理球的 Friends 啦！", type = "private"))

        @case _
    end
    nothing
end