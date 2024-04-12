using Telegram

function run_bot(::TGMode, foo::Function)
    wrapped_foo(msg) = foo(TGMessage(msg))
    Telegram.run_bot(wrapped_foo)
end

function sendGroupMessage(::TGMode; text, chat_id)
    Telegram.API.sendMessage(text = text, chat_id = chat_id)
end

function leaveGroup(::TGMode; chat_id)
    Telegram.API.leaveChat(chat_id = chat_id)
end

function sendGroupFile(::TGMode; path, chat_id, name = "")
    Telegram.API.sendMessage(text = "上传文件的功能还没有做好，联系Master让他发给你吧qwq", chat_id = chat_id)
end

function parseMsg(wrapped::TGMessage)
    msg = wrapped.body
    !haskey(msg, :message) && return nothing
    !haskey(msg.message, :text) && return nothing
    time = unix2datetime(msg.message.date) + local_time_shift
    groupId = msg.message.chat.id |> string
    userId = msg.message.from.id |> string
    userName = msg.message.from.first_name
    haskey(msg.message.from, :last_name) && (userName *= " " * msg.message.from.last_name)
    userName *= "(@$(msg.message.from.username))"
    msg.message.chat.type ∉ ["group", "supergroup", "private"] && return nothing
    type = :group
    if msg.message.chat.type == "private"
        type = :private
        groupId = "private"
    end
    text = replace(msg.message.text, r"^\s*|\s*$" => "")
    isempty(text) && return nothing
    return DiceMsg(time, type, groupId, userId, userName, msg.message.message_id, text)
end

function diceReply(::TGMode, C::Channel)
    for (msg, reply) ∈ C

        if debug_flag
            println(string(msg))
            println(string(reply))
        end

        isempty(reply.text) && return nothing
        user_id = parse(Int64, msg.userId)
        chat_id = parse(Int64, msg.type == :group ? msg.groupId : msg.userId)
        resp = if length(reply.text) > 1024
            Telegram.API.sendMessage(
                text = "结果太长了，悟理球不想刷屏，所以就不发啦！",
                chat_id = chat_id,
                reply_to_message_id = msg.message_id,
            )
        else
            parsed_text = replace(reply.text, r"([_*[\]()~>#+\-=|{}.!])" => s"\\\1")
            if reply.hidden
                try
                    Telegram.API.sendMessage(text = parsed_text, chat_id = user_id, parse_mode = "MarkdownV2")
                catch err
                    Telegram.API.sendMessage(
                        text = "错误，可能是因为悟理球没有私聊权限，请尝试私聊向悟理球发送 /start",
                        chat_id = chat_id,
                        reply_to_message_id = msg.message_id,
                    )
                end
            elseif reply.ref
                Telegram.API.sendMessage(text = parsed_text, chat_id = chat_id, reply_to_message_id = msg.message_id, parse_mode = "MarkdownV2")
            else
                Telegram.API.sendMessage(text = parsed_text, chat_id = chat_id, parse_mode = "MarkdownV2")
            end
        end

        if debug_flag
            println(resp)
        end

        if msg.type == :group # ToDo: 处理撤回和引用
            put!(log_channel, MessageLog(
                :msg,
                resp.message_id,
                unix2datetime(resp.date) + local_time_shift,
                string(chat_id),
                string(resp.from.id),
                resp.from.first_name * "(@$(resp.from.username))",
                reply.text,
            ))
        end
    end
end