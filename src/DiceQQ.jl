using HTTP

function run_bot(::QQMode, foo::Function)
    global onebot_ws_server = get(ENV, "CQ_WS_SERVER", "")
    global onebot_http_server = get(ENV, "CQ_HTTP_SERVER", "")
    global selfQQ, selfQQName = getSelf()
    WebSockets.open(onebot_ws_server) do ws
        for str ∈ ws
            msg = JSON3.read(str)
            foo(QQMessage(msg))
        end
    end
end

function onebotPostJSON(action, params; server = onebot_http_server)
    HTTP.post(server * "/" * action, ["Content-Type" => "application/json"], body = params)
end

function onebotPostJSON(action; server = onebot_http_server)
    HTTP.post(server * "/" * action, ["Content-Type" => "application/json"], body = "{}")
end

function getSelf()
    resp = onebotPostJSON("get_login_info")
    info = JSON3.read(resp.body).data
    selfId = string(info.user_id)
    selfName = info.nickname
    return (selfId, selfName)
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

function sendPrivateMessage(::QQMode; text, chat_id)
    msg_json = """
    {
        "user_id": $chat_id,
        "message": "$text"
    }
    """
    onebotPostJSON("send_private_msg", msg_json)
end

function leaveGroup(::QQMode; chat_id)
    msg_json = """
    {
        "group_id": $chat_id
    }
    """
    onebotPostJSON("set_group_leave", msg_json)
end

function sendGroupFile(::QQMode; path, chat_id, name = "")
    isempty(name) && (name = splitpath(path)[end])
    full_path = joinpath(pwd(), path)
    msg_json = """
    {
        "group_id": $chat_id,
        "file": "$full_path",
        "name": "$name"
    }
    """
    onebotPostJSON("upload_group_file", msg_json)
end

function isQQFriend(user_id::Int64)
    return true

    reply = onebotPostJSON("get_friend_list")
    list = JSON3.read(reply.body)
    qq_list = map(x -> x.user_id, list)
    return user_id ∈ qq_list
end
isQQFriend(userId::String) = isQQFriend(parse(Int64, userId))

function parseMsg(wrapped::QQMessage)
    msg = wrapped.body
    !haskey(msg, "post_type") && return nothing
    msg.post_type == "request" && return handleRequest(msg)
    msg.post_type == "notice" && return handleNotice(msg)
    msg.post_type != "message" && return nothing

    time = unix2datetime(msg.time) + local_time_shift
    groupId = "private"
    userId = msg.user_id |> string
    userName = msg.sender.nickname
    type = Symbol(msg.message_type)
    if type == :group
        msg.sub_type != "normal" && return nothing
        groupId = msg.group_id |> string
        !isempty(msg.sender.card) && (userName = msg.sender.card)
    elseif type == :private
        msg.sub_type != "friend" && return nothing
    else
        return nothing
    end

    text = replace(msg.raw_message, r"&amp;" => "&", r"&#91;" => "[", r"&#93;" => "]")
    m = match(r"^\[CQ:at,qq=(\d*)\]\s*([\S\s]*)", text)
    if m !== nothing
        m.captures[1] != selfQQ && return nothing
        text = m.captures[2]
    end
    text = replace(text, r"^\s*|\s*$" => "")
    isempty(text) && return nothing
    return DiceMsg(time, type, groupId, userId, userName, msg.message_id, text)
end

function makeReplyJSON(msg::DiceMsg; text::AbstractString, type::Symbol = msg.type, ref::Bool = false)
    @switch type begin
        @case :group
        target = "group"
        target_id = msg.groupId
        CQref = ref ? "[CQ:reply,id=$(msg.message_id)][CQ:at,qq=$(msg.userId)]" : ""

        @case :private
        target = "user"
        target_id = msg.userId
        CQref = ref ? "[CQ:reply,id=$(msg.message_id)]" : ""

        @case _
    end
    text_escape = replace(text, r"\r" => "\\r", r"\n" => "\\n", r"\"" => "\\\"", r"\t" => "\\t")
    """
    {
        "message_type": "$type",
        "$(target)_id": $(target_id),
        "message": "$(CQref)$(text_escape)"
    }
    """
end

function diceReply(::QQMode, C::Channel)
    for (msg, reply) ∈ C

        if debug_flag
            println(string(msg))
            println(string(reply))
        end

        isempty(reply.text) && return nothing
        reply_json = if length(reply.text) > 1024
            makeReplyJSON(msg, text = "结果太长了，悟理球不想刷屏，所以就不发啦！")
        elseif reply.hidden
            if isQQFriend(msg.userId)
                makeReplyJSON(msg, text = reply.text, type = :private)
            else
                makeReplyJSON(msg, text = "错误，悟理球无法向非好友发送消息，请先添加好友", ref = true)
            end
        else
            makeReplyJSON(msg, text = reply.text, ref = reply.ref)
        end
        resp = onebotPostJSON("send_msg", reply_json)

        if debug_flag
            println(resp)
        end

        if msg.type == :group
            reply_id = JSON3.read(resp.body).data.message_id
            text = reply.text
            if reply.ref
                text = "[CQ:reply,id=$(msg.message_id)][CQ:at,qq=$(msg.userId)]" * text
            end
            put!(log_channel, MessageLog(
                :msg,
                reply_id,
                now(),
                msg.groupId,
                selfQQ,
                selfQQName,
                text,
            ))
        end
    end
end

function handleRequest(msg)
    @switch msg.request_type begin
        @case "friend"
        request_json = """
        {
            "flag": "$(msg.flag)",
            "approve": true
        }
        """
        onebotPostJSON("set_friend_add_request", request_json)

        @case "group"
        msg.sub_type != "invite" && return nothing
        request_json = """
        {
            "flag": "$(msg.flag)",
            "approve": true
        }
        """
        onebotPostJSON("set_group_add_request", request_json)

        @case _
    end
    nothing
end

function handleNotice(msg)
    @switch msg.notice_type begin
        @case "group_increase"
        msg.user_id == msg.self_id && sendGroupMessage(QQMode(); text = "悟理球出现了！", chat_id = msg.group_id)

        @case "friend_add"
        sendPrivateMessage(QQMode(); text = "你现在也是手上粘着悟理球的 Friends 啦！", chat_id = msg.user_id)

        @case "group_recall"
        put!(log_channel, MessageLog(
            :recall,
            msg.message_id,
            unix2datetime(msg.time) + local_time_shift,
            string(msg.group_id),
            string(msg.user_id),
            "绯红之王",
            "",
        ))

        @case _
    end
    nothing
end