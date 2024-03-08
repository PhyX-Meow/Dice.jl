function run_bot(f::Function)
    global cq_ws_server = get(ENV, "CQ_WS_SERVER", "")
    global cq_http_server = get(ENV, "CQ_HTTP_SERVER", "")
    WebSockets.open(cq_ws_server) do ws
        for str ∈ ws
            msg = JSON3.read(str)
            try
                f(ws, msg)
            catch err
                @error err
                if err isa InterruptException
                    break
                end
            end
        end
    end
end


### Very ugly hack, REWRITE later! ###
function sendMessage(; text, chat_id)
    msg_json = """
    {
        "action": "send_group_msg",
        "params": {
            "group_id": $chat_id,
            "message": "$text"
        }
    }
    """
    HTTP.post(cq_http_server, ["Content-Type" => "application/json"], body = msg_json)
end

function leaveChat(; chat_id)
    msg_json = """
    {
        "action": "set_group_leave",
        "params": {
            "group_id": $chat_id
        }
    }
    """
    HTTP.post(cq_http_server, ["Content-Type" => "application/json"], body = msg_json)
end

function isQQFriend(; userId)
    return true

    msg_json = """
    {
        "action": "get_friend_list"
    }
    """
    reply = HTTP.post(cq_http_server, ["Content-Type" => "application/json"], body = msg_json)
    list = JSON3.read(reply.body)
    qq_list = map(x -> x.user_id, list)
    return userId ∈ qq_list
end
###