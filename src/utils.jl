struct DiceMsg
    time::DateTime
    type::Symbol
    groupId::String
    userId::String
    userName::String
    message_id::Int64
    text::String
end

struct DiceError <: Exception
    text::String
end

struct DiceCmd
    func::Function
    reg::Regex
    desp::String
    options::Vector{Symbol}
end

struct DiceReply
    text::String
    hidden::Bool
    ref::Bool
end
DiceReply(str::AbstractString, hidden::Bool, ref::Bool) = DiceReply(str, hidden, ref)
DiceReply(str::AbstractString) = DiceReply(str, false, true)
const noReply = DiceReply("", false, false)

@active Re{r::Regex}(x) begin
    m = match(r, string(x))
    if m !== nothing
        Some(m.captures)
    else
        nothing
    end
end

macro assure(ex)
    quote
        !$(ex) && return nothing
    end |> esc
end

macro async_log(expr)
    quote
        @async try
            $(esc(expr))
        catch err
            bt = stacktrace(catch_backtrace())
            showerror(stderr, err, bt)
            rethrow(err)
        end
    end
end

function _reply_(msg, reply::DiceReply)
    put!(message_channel, (msg, reply))
end

function (reply::DiceReply)(msg::DiceMsg)
    _reply_(msg, reply)
end

macro reply(args...)
    quote
        _reply_(msg, DiceReply($(args...)))
        return nothing
    end |> esc
end

function expr_replace(ex, cond::Function, func::Function; skip::Function = _ -> false)
    function foo(ex)
        cond(ex) && return deepcopy(func(ex))
        if ex isa Expr
            skip(ex) && return ex
            for i in eachindex(ex.args)
                ex.args[i] = foo(ex.args[i])
            end
        end
        ex
    end

    foo(deepcopy(ex))
end # Rewrite to in place version?

function expr_replace(ex, rules::Pair...; skip::Function = _ -> false)
    for (key, val) in rules
        ex = expr_replace(ex, key, val; skip = skip)
    end
    ex
end

function setJLD!(dataSet, path::AbstractString, val)
    if haskey(dataSet, path)
        delete!(dataSet, path)
    end
    dataSet[path] = val
end

function setJLD!(dataSet, settings::Pair...)
    for (key, val) ∈ settings
        setJLD!(dataSet, key, val)
    end
end

# function new_global_state(default_val)
#     state = default_val
#     function get()
#         return state
#     end
#     function set!(new_state)
#         state = new_state
#     end
#     function set!()
#         state = default_val
#     end
#     return (get, set!)
# end

# function new_global_vector(T::DataType)
#     state = T[]
#     function get()
#         return state
#     end
# end

struct QuantumRNG end # This is not a real Rng!
Base.rand(::QuantumRNG, args...) = rand(getQuantumRNG(), args...)

function getQuantumRNG()
    getJrrpSeed()
    return MersenneTwister(getQuantumSeed() ⊻ hash(now()))
end

function getJrrpSeed()
    date = today() |> string
    haskey(jrrpCache, date) && return jrrpCache[date]
    empty!(quantum_state[])
    jrrpCache[date] = seed = getQuantumSeed()
    return seed
end

function getQuantumSeed()
    if isempty(quantum_state[])
        api_key = get(ENV, "FREE_QUANTUM_API_KEY", "")
        headers = Dict("x-api-key" => api_key)
        length = 16
        resp = try
            HTTP.get("https://api.quantumnumbers.anu.edu.au?length=$length&type=hex16&size=10", headers, readtimeout = 1)
        catch err
            if err isa HTTP.Exceptions.TimeoutError
                throw(DiceError("量子超时:("))
            else
                throw(DiceError("发生量子错误！"))
            end
        end
        dataJSON = resp.body |> String |> JSON.parse
        if !dataJSON.success
            throw(DiceError("发生量子错误！"))
        end

        data = dataJSON.data
        for i ∈ 1:2:length
            a = SubString(data[i], 1, 16)
            b = SubString(data[i], 17, 32)
            c = SubString(data[i], 33, 40) * SubString(data[i+1], 1, 8)
            d = SubString(data[i+1], 9, 24)
            e = SubString(data[i+1], 25, 40)
            append!(quantum_state[], parse.(UInt64, [a, b, c, d, e], base = 16))
        end
    end
    return pop!(quantum_state[])
end

function getConfig(groupId, userId) # This is read only
    config = getConfig!(groupId, userId)
    config_dict = Dict()
    for key ∈ keys(config)
        config_dict[key] = config[key]
    end
    return config_dict
end

function getConfig(groupId, userId, conf::AbstractString)
    return getConfig!(groupId, userId)[conf]
end

function getConfig!(groupId, userId) # This allows modification
    isempty(userId) && throw(DiceError("错误，未知的用户"))
    isempty(groupId) && throw(DiceError("错误，群号丢失"))

    dataSet = groupId == "private" ? userData : groupData
    path = groupId == "private" ? "$userId/ config" : groupId
    default = groupId == "private" ? defaultUserConfig : defaultGroupConfig

    if !haskey(dataSet, path)
        config = JLD2.Group(dataSet, path)
    else
        config = dataSet[path]
    end

    for (key, val) in default
        if !haskey(config, key)
            config[key] = val
        end
    end

    return config
end

function getUserRNG(userId)
    path = "$userId/ jrrpRng"
    if haskey(userData, path)
        if userData[path][1] == today()
            return userData[path][2]
        end
        delete!(userData, path)
    end
    rng = Random.MersenneTwister(getJrrpSeed() ⊻ parse(UInt64, userId))
    userData[path] = (today(), rng)
    return rng
end

function saveUserRNG(userId)
    if getConfig("private", userId, "randomMode") == :jrrp
        setJLD!(userData, "$userId/ jrrpRng", (today(), deepcopy(rng_state[])))
    end
    rng_state[] = Random.default_rng()
end

function xdy(num::Integer, face::Integer; take::Integer = 0)
    check_dice(num, face)
    roll = rand(rng_state[], 1:face, num)
    @match take begin
        GuardBy(>(0)) => sum(sort(roll, rev = true)[1:min(take, num)])
        GuardBy(<(0)) => sum(sort(roll)[1:min(-take, num)])
        _ => sum(roll)
    end
end

struct DiceIR <: Number
    expr::String
    result::String
    total::Integer
    precedence::Integer
end

const dice_op_precedence = Dict(
    :+ => 11, :- => 11,
    :* => 12, :/ => 12, :÷ => 12,
    :d => 15, :↑ => 15, :↓ => 15,
    :num => 20,
    :br => 255,
)

function check_dice(num, face)
    (num <= 0 || face <= 0) && throw(DiceError("悟理球无法骰不存在的骰子！"))
    num > 42 && throw(DiceError("骰子太多了，骰不过来了qwq"))
    face > 153 && throw(DiceError("你这骰子已经是个球球了，没法骰了啦！"))
end

function DiceIR(rng, num::Integer, face::Integer; lead::Bool = false)
    check_dice(num, face)
    expr = "$(num)d$(face)"
    result = if lead
        fill(face, num)
    else
        rand(rng, 1:face, num)
    end
    result_str = "["
    l = length(result)
    for i ∈ 1:l
        result_str *= string(result[i])
        if i != l
            result_str *= ","
        end
    end
    result_str *= "]"
    DiceIR(expr, result_str, sum(result), dice_op_precedence[:d])
end

DiceIR(a::Integer) = convert(DiceIR, a)

begin
    import Base: +, -, *, /, ÷, promote_rule, convert

    convert(::Type{DiceIR}, a::Integer) = DiceIR("$a", "$a", a, dice_op_precedence[:num])
    promote_rule(::Type{DiceIR}, ::Type{T} where {T<:Number}) = DiceIR

    for (func, str) ∈ Dict(:+ => "+", :- => "-", :* => "*", :÷ => "/")
        quote
            function $func(L::DiceIR, R::DiceIR)
                current_precedence = $(dice_op_precedence[func])

                expr = ""
                expr *= L.precedence < current_precedence ? "($(L.expr))" : L.expr
                expr *= $str
                expr *= R.precedence < current_precedence ? "($(R.expr))" : R.expr

                result = ""
                result *= L.precedence < current_precedence ? "($(L.result))" : L.result
                result *= $str
                result *= R.precedence < current_precedence ? "($(R.result))" : R.result

                total = $func(L.total, R.total)

                return DiceIR(expr, result, total, current_precedence)
            end
        end |> eval
    end

    function +(L::DiceIR)
        return L
    end

    function -(L::DiceIR)
        current_precedence = 11

        expr = "-"
        expr *= L.precedence < current_precedence ? "($(L.expr))" : L.expr

        result = "-"
        result *= L.precedence < current_precedence ? "($(L.result))" : L.result

        total = -L.total

        return DiceIR(expr, result, total, current_precedence)
    end

    ÷(x::Number, y::Number) = ÷(promote(x, y)...)

    function ↑(rng, L::DiceIR, R::DiceIR)
        current_precedence = dice_op_precedence[:↑]

        expr = ""
        expr *= L.precedence <= current_precedence ? "($(L.expr))" : L.expr
        expr *= "d"
        expr *= R.precedence <= current_precedence ? "($(R.expr))" : R.expr

        dice = DiceIR(rng, L.total, R.total)
        result = "[$(dice.expr)=$(dice.result)]"

        total = dice.total

        return DiceIR(expr, result, total, current_precedence)
    end
    ↑(rng, L::Integer, R::Integer) = DiceIR(rng, L, R)
    ↑(rng, L::Number, R::DiceIR) = ↑(rng, promote(L, R)...)
    ↑(rng, L::DiceIR, R::Number) = ↑(rng, promote(L, R)...)
    ↑(L, R) = ↑(rng_state[], L, R)
    ↓(L, R) = L * R
end

struct InitialItem
    name::String
    number::Int64
end
struct InitialList
    multiple::Accumulator{String,Int64}
    items::PriorityQueue{InitialItem,Int64}
end
InitialList() = InitialList(counter(String), PriorityQueue{InitialItem,Int64}(Base.Order.Reverse))
Base.length(L::InitialList) = length(L.items)

function query_initial_list(the_list::InitialList, name::AbstractString)
    isempty(name) && throw(DiceError("错误，遇到了空的条目名"))
    if the_list.multiple[name] > 0
        local max_item = InitialItem(name, 0)
        for it ∈ keys(the_list.items)
            if it.name == name && it.number > max_item.number
                max_item = it
            end
        end
        return max_item.number > 0 ? max_item : nothing
    end
    if 'a' <= last(name) <= 'z'
        base_name = @view name[1:prevind(name, end, 1)]
        isempty(base_name) && throw(DiceError("错误，遇到了空的条目名"))
        if the_list.multiple[base_name] > 0
            number = last(name) - 'a' + 1
            for it ∈ keys(the_list.items)
                if it.name == base_name && it.number == number
                    return it
                end
            end
            return nothing
        end
    end
    return nothing
end
function add_to_initial_list(the_list::InitialList, name::AbstractString, val::Int64; number = 0)
    the_list.multiple[name] > 25 && throw(DiceError("同名条目过多，字母都要用光了！"))
    if number == 0
        number = inc!(the_list.multiple, name)
    elseif the_list.multiple[name] < number
        the_list.multiple[name] = number
    end
    enqueue!(the_list.items, InitialItem(name, number), val)
    name_with_number = name * ('`' + number)
    the_list.multiple[name_with_number] > 0 && throw("存在冲突条目：$(name_with_number)，请先清理冲突的条目")
    return number > 1 ? name_with_number : name
end
function delete_from_initial_list(the_list::InitialList, name::AbstractString, number::Int64; preserve_multiple = true)
    the_list.multiple[name] <= 0 && return nothing
    to_be_deleted = InitialItem[]
    count = 0
    for (it, val) ∈ the_list.items
        it.name != name && continue
        if number == 0 || it.number == number
            push!(to_be_deleted, it)
        else
            count = max(count, val)
        end
    end
    for it ∈ to_be_deleted
        delete!(the_list.items, it)
    end
    if !preserve_multiple
        if count > 0
            the_list.multiple[name] = count
        else
            reset!(the_list.multiple, name)
        end
    end
    return nothing
end

struct MessageLog
    type::Symbol
    id::Int64
    time::DateTime
    groupId::String
    userId::String
    userName::String
    content::String
end
MessageLog(msg::DiceMsg) = MessageLog(:msg, msg.message_id, msg.time, msg.groupId, msg.userId, msg.userName, msg.text)
function Base.string(item::MessageLog)
    item.userName * "($(item.userId)) " * Dates.format(item.time, dateformat"YYYY/mm/dd HH:MM:SS") * " [$(item.id)]\n" * item.content
end

struct GameLog
    name::String
    groupId::String
    time::DateTime
    items::Vector{MessageLog}
    deleted_items::Vector{Int64}
end

function diceLogging(C::Channel)
    for log_item in C
        !haskey(active_logs, log_item.groupId) && continue
        the_log = active_logs[log_item.groupId][]
        @switch log_item.type begin
            @case :msg
            push!(the_log.items, log_item)

            @case :recall
            push!(the_log.deleted_items, log_item.id)

            @case _
        end
    end
end

function exportLog(the_log::GameLog)
    path = "GameLogs/$(the_log.groupId)"
    mkpath(path)
    file = path * "/$(the_log.name).txt"
    stream = open(file, "w")
    title = "日志记录：$(the_log.name)(000) " * Dates.format(the_log.time, dateformat"YYYY/mm/dd HH:MM:SS") * "\n—————————————————\n\n"
    deleted = Set(the_log.deleted_items)
    write(stream, title)
    for log_item ∈ the_log.items
        log_item.id ∈ deleted && continue
        write(stream, string(log_item), "\n\n")
    end
    close(stream)
    sendGroupFile(path = file, chat_id = parse(Int, the_log.groupId), name = "日志-$(the_log.name).txt")
end