@active Re{r::Regex}(x) begin
    m = match(r, string(x))
    if m !== nothing
        Some(m.captures)
    else
        nothing
    end
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
end

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

function new_global_state(default_val)
    state = default_val
    function get()
        return state
    end
    function set!(new_state)
        state = new_state
    end
    function set!()
        state = default_val
    end
    return (get, set!)
end

function new_quantum_state()
    state = UInt64[]
    function get()
        return state
    end
end

function getQuantumRng()
    quantumState = getQuantumState()
    if isempty(quantumState)
        append!(quantumState, getQuantum(1024, 4))
    end
    seed = pop!(quantumState)
    return MersenneTwister(seed)
end

function getQuantum(length = 1, size = 4)
    api_key = get(ENV, "SUPER_SECRET_QUANTUM_API_KEY", "")
    headers = Dict("x-api-key" => api_key)
    resp = try
        HTTP.get("https://api.quantumnumbers.anu.edu.au?length=$length&type=hex16&size=4", headers, readtimeout = 1)
    catch err
        if err isa HTTP.Exceptions.TimeoutError
            throw(DiceError("量子超时:("))
        else
            throw(err)
        end
    end
    dataJSON = resp.body |> String |> JSON3.read
    if !dataJSON.success
        throw(DiceError("发生量子错误！"))
    end
    return parse.(UInt64, dataJSON.data, base = 16)
end

function xdy(num::Integer, face::Integer; take::Integer = 0, rng = getRngState())
    check_dice(num, face)
    roll = rand(rng, 1:face, num)
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

function DiceIR(rng::AbstractRNG, num::Integer, face::Integer; lead::Bool = false)
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

    function ↑(rng::AbstractRNG, L::DiceIR, R::DiceIR)
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
    ↑(rng::AbstractRNG, L::Integer, R::Integer) = DiceIR(rng, L, R)
    ↑(rng::AbstractRNG, L::Number, R::DiceIR) = ↑(rng, promote(L, R)...)
    ↑(rng::AbstractRNG, L::DiceIR, R::Number) = ↑(rng, promote(L, R)...)
    ↑(L, R) = ↑(getRngState(), L, R)
    ↓(L, R) = L * R
end