using HTTP

function run_bot(foo::Function)
    global onebot_ws_server = get(ENV, "CQ_WS_SERVER", "")
    global onebot_http_server = get(ENV, "CQ_HTTP_SERVER", "")
    global selfQQ, selfQQName = getSelf()
    global friendList = getFriends()
    if debug_flag
        println("[Debug] Login OK, uin: $(selfQQ), nickname: $(selfQQName)")
    end
    WebSockets.open(onebot_ws_server) do ws
        for str ∈ ws
            msg = JSON.parse(str)
            foo(msg)
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
    info = JSON.parse(resp.body).data
    selfId = string(info.uin)
    selfName = info.nickname
    return (selfId, selfName)
end

function getFriends()
    resp = onebotPostJSON("get_friend_list")
    data = JSON.parse(resp.body).data
    return map(x -> x.user_id, data.friends) |> Set
end

function sendGroupMessage(; text, chat_id)
    msg_json = """
    {
        "group_id": $chat_id,
        "message": [
            {"type":"text","data":{"text":"$text"}}
        ]
    }
    """
    onebotPostJSON("send_group_message", msg_json)
end

function sendPrivateMessage(; text, chat_id)
    msg_json = """
    {
        "user_id": $chat_id,
        "message": [
            {"type":"text","data":{"text":"$text"}}
        ]
    }
    """
    onebotPostJSON("send_private_message", msg_json)
end

function leaveGroup(; chat_id)
    msg_json = """
    {
        "group_id": $chat_id
    }
    """
    onebotPostJSON("quit_group", msg_json)
end

function sendGroupFile(; path, chat_id, name = "")
    isempty(name) && (name = splitpath(path)[end])
    full_path = joinpath(pwd(), path)
    msg_json = """
    {
        "group_id": $chat_id,
        "file_uri": "file://$full_path",
        "file_name": "$name"
    }
    """
    onebotPostJSON("upload_group_file", msg_json)
end

isFriend(user_id::Int64) = user_id ∈ friendList
isFriend(userId::String) = isFriend(parse(Int64, userId))

function parseMsg(rough_msg)
    !haskey(rough_msg, "event_type") && return nothing
    rough_msg.event_type != "message_receive" && return handleRequestNotice(rough_msg)
    msg = rough_msg.data

    time = unix2datetime(msg.time) + local_time_shift
    userName = userId = msg.sender_id |> string
    type = :private
    groupId = "private"
    @switch msg.message_scene begin
        @case "group"
        type = :group
        groupId = msg.group.group_id |> string
        userName = isempty(msg.group_member.card) ? msg.group_member.nickname : msg.group_member.card

        @case "friend"
        userName = msg.friend.nickname
        if userName === nothing # What the hell?
            userName = "null"
        end

        @case _ # "temp"
        return nothing
    end
    userName = replace(userName, r"^\s*|\s*$" => "")

    text = ""
    for seg in msg.segments
        @switch seg.type begin
            @case "mention"
            seg.data.user_id != selfQQ && return nothing

            @case "text"
            text *= seg.data.text

            @case "market_face"
            m = match(r"\[(.*)\]", seg.data.summary)
            if m !== nothing && (haskey(defaultSkill, m.captures[1]) || haskey(skillAlias, m.captures[1]))
                text *= ".rc $(m.captures[1])"
            end

            @case _
            text *= ' '
        end
    end
    text = replace(text, r"^\s*|\s*$" => "")
    isempty(text) && return nothing

    return DiceMsg(time, type, groupId, userId, userName, msg.message_seq, text)
end

function makeReplyJSON(msg::DiceMsg; text::AbstractString, type::Symbol = msg.type, ref::Bool = false)
    @switch type begin
        @case :group
        target = "group"
        target_id = msg.groupId

        @case :private
        target = "user"
        target_id = msg.userId

        @case _
    end
    seg_reply = ref ?
                """
                {
                    "type": "reply",
                    "data": {"message_seq": $(msg.message_id)}
                },
                """ : ""
    text_escape = replace(text, r"\r" => "\\r", r"\n" => "\\n", r"\"" => "\\\"", r"\t" => "\\t", r"\\([\(\)\[\]])" => s"\\\\\1")
    """
    {
        "$(target)_id": $(target_id),
        "message": [
            $(seg_reply)
            {
                "type": "text",
                "data": {"text": "$(text_escape)"}
            }
        ]
    }
    """
end

function diceReply(C::Channel)
    for (msg, reply) ∈ C

        if debug_flag
            println(string(msg))
            println(string(reply))
        end

        isempty(reply.text) && return nothing
        reply_json = if length(reply.text) > 1024
            makeReplyJSON(msg, text = "结果太长了，悟理球不想刷屏，所以就不发啦！")
        elseif reply.hidden
            if isFriend(msg.userId)
                makeReplyJSON(msg, text = reply.text, type = :private)
            else
                makeReplyJSON(msg, text = "悟理球只给好友发消息！请先添加好友", ref = true)
            end
        else
            makeReplyJSON(msg, text = reply.text, ref = reply.ref)
        end
        api = "send_$(msg.type)_message"
        resp = onebotPostJSON(api, reply_json)

        if debug_flag
            println(resp)
        end

        if msg.type == :group
            data = JSON.parse(resp.body).data
            reply_id = data.message_seq
            time = unix2datetime(data.time) + local_time_shift
            text = reply.text
            if reply.ref
                text = "[CQ:reply,id=$(msg.message_id)][CQ:at,qq=$(msg.userId)]" * text
            end
            put!(log_channel, MessageLog(
                :msg,
                reply_id,
                time,
                msg.groupId,
                selfQQ,
                selfQQName,
                text,
            ))
        end
    end
end

function handleRequestNotice(msg)
    @switch msg.event_type begin
        @case "friend_request" # Add black list
        uid = msg.data.initiator_uid
        request_json = """
        {
            "initiator_uid": "$(uid)",
            "is_filtered": false
        }
        """
        onebotPostJSON("accept_friend_request", request_json)
        @async_log begin
            sleep(1)
            sendPrivateMessage(; text = "你现在也是手上粘着悟理球的 Friends 啦！", chat_id = msg.data.initiator_id)
        end

        @case "group_invitation" # Add black list
        group_id = msg.data.group_id
        seq_id = msg.data.invitation_seq
        request_json = """
        {
            "group_id": $(group_id),
            "invitation_seq": $(seq_id)
        }
        """
        onebotPostJSON("accept_group_invitation", request_json)

        @case "group_member_increase"
        msg.self_id == msg.data.user_id && sendGroupMessage(; text = "悟理球出现了！", chat_id = msg.data.group_id)

        @case "message_recall"
        if msg.data.message_scene == "group"
            put!(log_channel, MessageLog(
                :recall,
                msg.data.message_seq,
                unix2datetime(msg.time) + local_time_shift,
                string(msg.data.peer_id),
                string(msg.data.sender_id),
                "绯红之王",
                "",
            ))
        end

        @case _
    end
    nothing
end