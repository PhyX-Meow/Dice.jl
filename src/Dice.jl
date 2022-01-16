module Dice

export run_dice

using Telegram, Telegram.API
using FileIO
using MLStyle

include("const.jl")
include("diceCommand.jl")

function diceReply(msg, reply::DiceReply)
    if isempty(reply.text)
        return nothing
    end
    if reply.hidden
        try
            for tt ∈ reply.text
                sendMessage(text = tt, chat_id = msg.message.from.id)
            end
        catch err
            sendMessage(text = "错误，悟理球没有私聊权限，请先私聊向悟理球发送 /start", chat_id = msg.message.chat.id, reply_to_message_id = msg.message.message_id)
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
    if !(haskey(msg, :message) && haskey(msg.message, :text))
        return nothing
    end

    show(msg)
    println()

    str = msg.message.text
    #  user = msg.message.from.username
    if !(str[1] ∈ ['.', '/', '。'])
        return nothing
    end

    str = chop(str, head = 1, tail = 0)

    if msg.message.from.id ∈ superAdminList
        m = match(r"eval\s(.*)", str)
        if m !== nothing
            diceReply(msg, DiceReply("警告！，你在执行一个超级指令！", false, true))
            superCommand = m.captures[1]
            ret = superCommand |> Meta.parse |> eval
            return diceReply(msg, DiceReply("执行结果：$ret", false, false))
        end
    end

    reply = DiceReply("已阅，狗屁不通。") # 无匹配的命令
    for cmd ∈ cmdList
        m = match(cmd.reg, str)
        if m !== nothing
            reply = noReply
            if msg.message.chat.type ∈ ["group", "supergroup"] && :group ∈ cmd.options
                reply = @eval $(cmd.func)($(m.captures))
            elseif msg.message.chat.type == "private" && :private ∈ cmd.options
                reply = @eval $(cmd.func)($(m.captures))
            end
        end
    end
    diceReply(msg, reply)
end

function testMain(msg)
    show(msg)
    println()
end

run_dice() = run_bot(diceMain)

end # module
