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

function parseMsg(wrapped::TGMessage)
    msg = wrapped.body
    !haskey(msg, :message) && return nothing
    !haskey(msg.message, :text) && return nothing
    groupId = msg.message.chat.id |> string
    userId = msg.message.from.id |> string
    msg.message.chat.type ∉ ["group", "supergroup", "private"] && return nothing
    if msg.message.chat.type == "private"
        groupId = "private"
    end
    return DiceMsg(groupId, userId, msg.message.message_id, msg.message.text)
end

function diceReply(wrapped::TGMessage, reply::DiceReply)
    msg = wrapped.body
    isempty(reply.text) && return nothing
    if maximum(length.(reply.text)) > 1024
        Telegram.API.sendMessage(
            text = "结果过长，无法发送！",
            chat_id = msg.message.chat.id,
            reply_to_message_id = msg.message.message_id,
        )
        return nothing
    end

    parsed_text = replace.(reply.text, r"([_*[\]()~>#+\-=|{}.!])" => s"\\\1")
    if reply.hidden
        try
            for tt ∈ parsed_text
                Telegram.API.sendMessage(text = tt, chat_id = msg.message.from.id, parse_mode = "MarkdownV2")
            end
        catch err
            Telegram.API.sendMessage(
                text = "错误，可能是因为悟理球没有私聊权限，请尝试私聊向悟理球发送 /start",
                chat_id = msg.message.chat.id,
                reply_to_message_id = msg.message.message_id,
            )
        end
    elseif reply.ref
        for tt ∈ parsed_text
            Telegram.API.sendMessage(text = tt, chat_id = msg.message.chat.id, reply_to_message_id = msg.message.message_id, parse_mode = "MarkdownV2")
        end
    else
        for tt ∈ parsed_text
            Telegram.API.sendMessage(text = tt, chat_id = msg.message.chat.id, parse_mode = "MarkdownV2")
        end
    end
    nothing
end